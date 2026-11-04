//! Direct seat, input and KMS ownership. Nested development stays in winit.
use crate::{scene::Cursors, CalloopData, Smallvil};
use anyhow::{Context, Result};
use smithay::{
    backend::{
        allocator::{
            gbm::{GbmAllocator, GbmBufferFlags, GbmDevice},
            Fourcc,
        },
        drm::{
            compositor::{DrmCompositor, FrameFlags},
            exporter::gbm::GbmFramebufferExporter,
            DrmDevice, DrmDeviceFd, DrmEvent,
        },
        egl::{EGLContext, EGLDevice, EGLDisplay},
        libinput::{LibinputInputBackend, LibinputSessionInterface},
        renderer::{gles::GlesRenderer, ImportDma},
        session::{libseat::LibSeatSession, Event as SessionEvent, Session},
        udev::{primary_gpu, UdevBackend, UdevEvent},
    },
    output::{Mode, Output, OutputModeSource, PhysicalProperties, Scale, Subpixel},
    reexports::{
        calloop::{
            timer::{TimeoutAction, Timer},
            EventLoop,
        },
        drm::control::{connector, crtc, Device, ModeTypeFlags},
        input::Libinput,
        rustix::fs::OFlags,
        wayland_server::backend::GlobalId,
    },
    utils::{DeviceFd, Transform},
    wayland::dmabuf::DmabufFeedbackBuilder,
};
use std::{
    cell::RefCell,
    rc::Rc,
    time::{Duration, Instant},
};

type Scanout =
    DrmCompositor<GbmAllocator<DrmDeviceFd>, GbmFramebufferExporter<DrmDeviceFd>, (), DrmDeviceFd>;
struct Head {
    connector: connector::Handle,
    crtc: crtc::Handle,
    output: Output,
    global: GlobalId,
    scanout: Scanout,
    pending: bool,
    dirty: bool,
}
struct Native {
    session: LibSeatSession,
    drm: DrmDevice,
    gbm: GbmDevice<DrmDeviceFd>,
    renderer: GlesRenderer,
    heads: Vec<Head>,
    cursors: Cursors,
    active: bool,
    rescan: bool,
}
impl Native {
    fn scan(&mut self, data: &mut CalloopData) -> Result<()> {
        let resources = self.drm.resource_handles()?;
        let connectors: Vec<_> = resources
            .connectors()
            .iter()
            .filter_map(|h| self.drm.get_connector(*h, true).ok())
            .filter(|c| c.state() == connector::State::Connected && !c.modes().is_empty())
            .collect();
        let mut i = 0;
        while i < self.heads.len() {
            if connectors
                .iter()
                .any(|c| c.handle() == self.heads[i].connector)
            {
                i += 1;
                continue;
            }
            let head = self.heads.remove(i);
            data.state.space.unmap_output(&head.output);
            data.display_handle.remove_global::<Smallvil>(head.global);
        }
        for connector in connectors {
            if self.heads.iter().any(|h| h.connector == connector.handle()) {
                continue;
            }
            let possible: Vec<_> = connector
                .encoders()
                .iter()
                .filter_map(|h| self.drm.get_encoder(*h).ok())
                .flat_map(|e| resources.filter_crtcs(e.possible_crtcs()))
                .collect();
            let Some(crtc) = possible
                .into_iter()
                .find(|c| !self.heads.iter().any(|h| h.crtc == *c))
            else {
                eprintln!("No free CRTC for {:?}", connector.interface());
                continue;
            };
            let mode = *connector
                .modes()
                .iter()
                .find(|m| m.mode_type().contains(ModeTypeFlags::PREFERRED))
                .unwrap_or(&connector.modes()[0]);
            let name = format!(
                "{}-{}",
                connector.interface().as_str(),
                connector.interface_id()
            );
            let size = (mode.size().0 as i32, mode.size().1 as i32).into();
            let surface = self.drm.create_surface(crtc, mode, &[connector.handle()])?;
            let scanout = DrmCompositor::new(
                OutputModeSource::Static {
                    size,
                    scale: 1.0.into(),
                    transform: Transform::Normal,
                },
                surface,
                None,
                GbmAllocator::new(
                    self.gbm.clone(),
                    GbmBufferFlags::RENDERING | GbmBufferFlags::SCANOUT,
                ),
                GbmFramebufferExporter::new(self.gbm.clone(), None),
                [Fourcc::Argb8888, Fourcc::Abgr8888],
                self.renderer
                    .egl_context()
                    .dmabuf_render_formats()
                    .iter()
                    .copied(),
                self.drm.cursor_size(),
                None,
            )?;
            let output = Output::new(
                name.clone(),
                PhysicalProperties {
                    size: connector
                        .size()
                        .map(|(w, h)| (w as i32, h as i32))
                        .unwrap_or((0, 0))
                        .into(),
                    subpixel: Subpixel::Unknown,
                    make: "Unknown".into(),
                    model: name.clone(),
                },
            );
            let global = output.create_global::<Smallvil>(&data.display_handle);
            let wlmode = Mode {
                size,
                refresh: mode.vrefresh() as i32 * 1000,
            };
            output.change_current_state(
                Some(wlmode),
                Some(Transform::Normal),
                Some(Scale::Custom {
                    advertised_integer: 2,
                    fractional: data.state.ui_scale,
                }),
                Some((0, 0).into()),
            );
            output.set_preferred(wlmode);
            data.state.space.map_output(&output, (0, 0));
            eprintln!("Shine output {name}: {}×{}", size.w, size.h);
            self.heads.push(Head {
                connector: connector.handle(),
                crtc,
                output,
                global,
                scanout,
                pending: false,
                dirty: true,
            });
        }
        data.state.relayout();
        data.state.sync_focus();
        self.rescan = false;
        Ok(())
    }
    fn draw(&mut self, data: &mut CalloopData) -> Result<()> {
        if !self.active {
            return Ok(());
        }
        if self.rescan {
            self.scan(data)?;
        }
        let state = &mut data.state;
        state.import_buffers(&mut self.renderer);
        state.space.refresh();
        state.maintain_scene();
        if state.needs_redraw {
            for h in &mut self.heads {
                h.dirty = true;
            }
            state.needs_redraw = false;
        }
        for head in &mut self.heads {
            if head.pending || !head.dirty {
                continue;
            }
            state.cursor_rendered_elements = 0;
            let elements =
                state.output_elements(&mut self.renderer, &head.output, Some(&mut self.cursors));
            let result = head.scanout.render_frame(
                &mut self.renderer,
                &elements,
                [0.035, 0.035, 0.055, 1.0],
                FrameFlags::empty(),
            )?;
            head.dirty = false;
            if !result.is_empty {
                head.scanout.queue_frame(())?;
                head.pending = true;
                state.rendered_frames += 1;
            } else {
                state.send_output_frames(&head.output);
            }
        }
        state.popups.cleanup();
        Ok(())
    }
}

pub fn init_native(event_loop: &mut EventLoop<CalloopData>, data: &mut CalloopData) -> Result<()> {
    let (session, notifier) = LibSeatSession::new().context("Open a logind/libseat session")?;
    let seat = session.seat();
    let mut input =
        Libinput::new_with_udev::<LibinputSessionInterface<LibSeatSession>>(session.clone().into());
    input
        .udev_assign_seat(&seat)
        .map_err(|_| anyhow::anyhow!("Assign input seat {seat}"))?;
    event_loop
        .handle()
        .insert_source(
            LibinputInputBackend::new(input.clone()),
            |event, _, data| {
                data.state.process_input_event(event);
            },
        )
        .map_err(|e| anyhow::anyhow!("{}", e.error))?;
    let path = primary_gpu(&seat)?.context("No graphics device on this seat")?;
    let mut opener = session.clone();
    let fd = DrmDeviceFd::new(DeviceFd::from(opener.open(
        &path,
        OFlags::RDWR | OFlags::CLOEXEC | OFlags::NOCTTY | OFlags::NONBLOCK,
    )?));
    let (drm, drm_events) = DrmDevice::new(fd.clone(), true)?;
    let device_id = drm.device_id();
    let gbm = GbmDevice::new(fd)?;
    let display = unsafe { EGLDisplay::new(gbm.clone()) }?;
    let context = EGLContext::new(&display)?;
    let renderer = unsafe { GlesRenderer::new(context) }?;
    let render_device = EGLDevice::device_for_display(&display)
        .ok()
        .and_then(|d| d.try_get_render_node().ok().flatten())
        .map(|n| n.dev_id())
        .unwrap_or(device_id);
    let feedback = DmabufFeedbackBuilder::new(render_device, renderer.dmabuf_formats()).build()?;
    data.state.dmabuf_global = Some(
        data.state
            .dmabuf_state
            .create_global_with_default_feedback::<Smallvil>(&data.display_handle, &feedback),
    );
    let mut native = Native {
        active: session.is_active(),
        session,
        drm,
        gbm,
        renderer,
        heads: vec![],
        cursors: Cursors::default(),
        rescan: true,
    };
    native.scan(data)?;
    let native = Rc::new(RefCell::new(native));
    let backend = native.clone();
    event_loop
        .handle()
        .insert_source(drm_events, move |event, _, data| {
            let mut backend = backend.borrow_mut();
            match event {
                DrmEvent::VBlank(crtc) => {
                    if let Some(h) = backend.heads.iter_mut().find(|h| h.crtc == crtc) {
                        if let Err(e) = h.scanout.frame_submitted() {
                            eprintln!("Page flip completion: {e}");
                        }
                        h.pending = false;
                        data.state.send_output_frames(&h.output);
                    }
                }
                DrmEvent::Error(e) => eprintln!("DRM event: {e}"),
            }
        })
        .map_err(|e| anyhow::anyhow!("{}", e.error))?;
    let backend = native.clone();
    event_loop
        .handle()
        .insert_source(notifier, move |event, _, data| {
            let mut backend = backend.borrow_mut();
            match event {
                SessionEvent::PauseSession => {
                    backend.active = false;
                    input.suspend();
                    data.state.release_keys();
                    backend.drm.pause();
                }
                SessionEvent::ActivateSession => {
                    let result = (|| -> Result<()> {
                        input
                            .resume()
                            .map_err(|_| anyhow::anyhow!("Resume input"))?;
                        backend.drm.activate(false)?;
                        for h in &mut backend.heads {
                            h.scanout.reset_state()?;
                            h.scanout.reset_buffers();
                            h.pending = false;
                            h.dirty = true;
                        }
                        backend.active = true;
                        backend.rescan = true;
                        Ok(())
                    })();
                    if let Err(e) = result {
                        data.state.runtime_error = Some(format!("Resume seat: {e:#}"));
                        data.state.loop_signal.stop();
                    }
                }
            }
        })
        .map_err(|e| anyhow::anyhow!("{}", e.error))?;
    let backend = native.clone();
    event_loop
        .handle()
        .insert_source(UdevBackend::new(&seat)?, move |event, _, _| {
            let changed = match event {
                UdevEvent::Changed { device_id: id }
                | UdevEvent::Removed { device_id: id }
                | UdevEvent::Added { device_id: id, .. } => id == device_id,
            };
            if changed {
                backend.borrow_mut().rescan = true;
            }
        })
        .map_err(|e| anyhow::anyhow!("{}", e.error))?;
    let mut tick = Instant::now();
    event_loop
        .handle()
        .insert_source(Timer::immediate(), move |_, _, data| {
            let now = Instant::now();
            if data.state.layout.tick((now - tick).as_secs_f64()) {
                data.state.apply_positions();
            }
            tick = now;
            let mut backend = native.borrow_mut();
            if let Some(vt) = data.state.vt_request.take() {
                if let Err(e) = backend.session.change_vt(vt) {
                    eprintln!("Switch VT: {e}");
                }
            }
            if let Err(e) = backend.draw(data) {
                data.state.runtime_error = Some(format!("Render displays: {e:#}"));
                data.state.loop_signal.stop();
            }
            TimeoutAction::ToDuration(Duration::from_millis(16))
        })
        .map_err(|e| anyhow::anyhow!("{}", e.error))?;
    Ok(())
}
