//! Direct seat, input and KMS ownership. Nested development stays in winit.
use crate::{
    output_config::{edid_identity, OutputInfo, VideoMode},
    scene::Cursors,
    CalloopData, Smallvil,
};
use anyhow::{Context, Result};
use smithay::{
    backend::{
        allocator::{
            gbm::{GbmAllocator, GbmBufferFlags, GbmDevice},
            Fourcc,
        },
        drm::{
            compositor::{DrmCompositor, FrameFlags, PrimaryPlaneElement},
            exporter::gbm::GbmFramebufferExporter,
            DrmDevice, DrmDeviceFd, DrmEvent,
        },
        egl::{EGLContext, EGLDevice, EGLDisplay},
        input::InputEvent,
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
        drm::control::{connector, crtc, Device, Mode as DrmMode, ModeTypeFlags},
        input::{Device as InputDevice, Libinput},
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
    mode: DrmMode,
    modes: Vec<DrmMode>,
    failed_revision: Option<u64>,
}
fn video_mode(mode: &DrmMode) -> VideoMode {
    VideoMode {
        width: mode.size().0 as i32,
        height: mode.size().1 as i32,
        refresh: mode.vrefresh() as i32 * 1000,
    }
}
impl Head {
    fn use_mode(&mut self, mode: DrmMode, state: &mut Smallvil) -> Result<()> {
        self.scanout.use_mode(mode)?;
        let video = video_mode(&mode);
        let size = video.size().into();
        self.scanout
            .set_output_mode_source(OutputModeSource::Static {
                size,
                scale: 1.0.into(),
                transform: Transform::Normal,
            });
        self.mode = mode;
        self.dirty = true;
        self.output.change_current_state(
            Some(Mode {
                size,
                refresh: video.refresh,
            }),
            None,
            None,
            None,
        );
        state.relayout();
        Ok(())
    }
    fn rollback(&mut self, mode: DrmMode, state: &mut Smallvil, error: String) -> Result<()> {
        self.use_mode(mode, state)?;
        self.scanout.reset_state()?;
        self.scanout.reset_buffers();
        self.failed_revision = Some(state.config_revision);
        state.config_error = Some(format!(
            "{} mode change failed: {error}; restored previous mode",
            self.output.name()
        ));
        Ok(())
    }
}
pub(crate) struct Native {
    session: LibSeatSession,
    drm: DrmDevice,
    gbm: GbmDevice<DrmDeviceFd>,
    renderer: GlesRenderer,
    heads: Vec<Head>,
    cursors: Cursors,
    decorations: crate::decoration::Renderer,
    active: bool,
    rescan: bool,
    devices: Rc<RefCell<(u64, Vec<InputDevice>)>>,
    input_revision: Option<(u64, u64)>,
    tick: Instant,
}
impl Native {
    fn configure_input(&mut self, state: &mut Smallvil) {
        let mut devices = self.devices.borrow_mut();
        let revision = (devices.0, state.config_revision);
        if self.input_revision == Some(revision) {
            return;
        }
        state.input_devices.clear();
        for device in &mut devices.1 {
            // All devices belong to this udev-backed libinput context.
            let touchpad = device.config_tap_finger_count() > 0
                || unsafe { device.udev_device() }.is_some_and(|d| {
                    d.property_value("ID_INPUT_TOUCHPAD") == Some(std::ffi::OsStr::new("1"))
                });
            if touchpad {
                let options = &state.output_settings.input.touchpad;
                if device.config_tap_finger_count() > 0 {
                    let enabled = options
                        .tap
                        .unwrap_or_else(|| device.config_tap_default_enabled());
                    if let Err(e) = device.config_tap_set_enabled(enabled) {
                        state.config_error =
                            Some(format!("Touchpad tap configuration failed: {e:?}"));
                    }
                }
                if device.config_scroll_has_natural_scroll() {
                    let enabled = options
                        .natural_scroll
                        .unwrap_or_else(|| device.config_scroll_default_natural_scroll_enabled());
                    if let Err(e) = device.config_scroll_set_natural_scroll_enabled(enabled) {
                        state.config_error =
                            Some(format!("Touchpad scroll configuration failed: {e:?}"));
                    }
                }
            }
            state
                .input_devices
                .push(serde_json::json!({"name":device.name(),"touchpad":touchpad,
                "tap":touchpad.then(||device.config_tap_enabled()),
                "natural_scroll":touchpad.then(||device.config_scroll_natural_scroll_enabled())}));
        }
        self.input_revision = Some(revision);
    }
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
            data.state.output_info.remove(&head.output.name());
            data.state.space.unmap_output(&head.output);
            data.display_handle.remove_global::<Smallvil>(head.global);
        }
        for connector in connectors {
            let name = format!(
                "{}-{}",
                connector.interface().as_str(),
                connector.interface_id()
            );
            let edid = self
                .drm
                .get_properties(connector.handle())
                .ok()
                .and_then(|properties| {
                    properties.into_iter().find_map(|(handle, value)| {
                        self.drm
                            .get_property(handle)
                            .ok()
                            .filter(|p| p.name().to_bytes() == b"EDID")
                            .and_then(|_| self.drm.get_property_blob(value).ok())
                    })
                })
                .unwrap_or_default();
            let (id, make, model) = edid_identity(&name, &edid);
            let preferred = *connector
                .modes()
                .iter()
                .find(|m| m.mode_type().contains(ModeTypeFlags::PREFERRED))
                .unwrap_or(&connector.modes()[0]);
            let info = OutputInfo {
                name: name.clone(),
                id,
                make: make.clone(),
                model: model.clone(),
                modes: connector.modes().iter().map(video_mode).collect(),
                preferred: video_mode(&preferred),
                adjustable_mode: true,
            };
            data.state.output_info.insert(name.clone(), info.clone());
            if let Some(head) = self
                .heads
                .iter_mut()
                .find(|h| h.connector == connector.handle())
            {
                head.modes = connector.modes().to_vec();
                head.failed_revision = None;
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
            let selected = data
                .state
                .output_settings
                .selected_mode(&info)
                .unwrap_or_else(|error| {
                    data.state.config_error = Some(error);
                    info.preferred.clone()
                });
            let mode = *connector
                .modes()
                .iter()
                .find(|m| video_mode(m) == selected)
                .unwrap_or(&preferred);
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
                    make,
                    model,
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
                    advertised_integer: data.state.ui_scale.ceil() as i32,
                    fractional: data.state.ui_scale,
                }),
                Some((0, 0).into()),
            );
            for mode in connector.modes() {
                let mode = video_mode(mode);
                output.add_mode(Mode {
                    size: mode.size().into(),
                    refresh: mode.refresh,
                });
            }
            let preferred = video_mode(&preferred);
            output.set_preferred(Mode {
                size: preferred.size().into(),
                refresh: preferred.refresh,
            });
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
                mode,
                modes: connector.modes().to_vec(),
                failed_revision: None,
            });
        }
        let mut counts = std::collections::BTreeMap::new();
        for info in data.state.output_info.values() {
            *counts.entry(info.id.clone()).or_insert(0) += 1;
        }
        for info in data.state.output_info.values_mut() {
            if counts.get(&info.id).copied().unwrap_or(0) > 1 {
                info.id = format!("connector:{}", info.name);
            }
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
        let now = Instant::now();
        if state.layout.tick((now - self.tick).as_secs_f64()) {
            state.apply_positions();
        }
        self.tick = now;
        state.import_buffers(&mut self.renderer);
        state.space.refresh();
        state.maintain_scene();
        state.copy_images(&mut self.renderer, &mut self.decorations);
        self.configure_input(state);
        if state.needs_redraw {
            for h in &mut self.heads {
                h.dirty = true;
            }
            state.needs_redraw = false;
        }
        for head in &mut self.heads {
            state.capture_output(&mut self.renderer, &head.output, &mut self.decorations);
            state.copy_output(&mut self.renderer, &head.output, &mut self.decorations);
            let original_mode = head.mode;
            if !head.pending && head.failed_revision != Some(state.config_revision) {
                let info = state.output_info.get(&head.output.name()).unwrap();
                match state.output_settings.selected_mode(info) {
                    Ok(selected) => {
                        if let Some(mode) = head
                            .modes
                            .iter()
                            .find(|m| video_mode(m) == selected)
                            .copied()
                        {
                            if head.mode != mode {
                                if let Err(error) = head.use_mode(mode, state) {
                                    state.config_error = Some(format!(
                                        "{} mode change rejected: {error:#}",
                                        head.output.name()
                                    ));
                                    head.failed_revision = Some(state.config_revision);
                                }
                            }
                        }
                    }
                    Err(error) => {
                        state.config_error = Some(error);
                        head.failed_revision = Some(state.config_revision);
                    }
                }
            }
            if head.pending || !head.dirty {
                continue;
            }
            state.cursor_rendered_elements = 0;
            let elements = state.output_elements(
                &mut self.renderer,
                &head.output,
                Some(&mut self.cursors),
                &mut self.decorations,
                (0, 0).into(),
                crate::scene::RenderPurpose::Display,
            );
            let result = match head.scanout.render_frame(
                &mut self.renderer,
                &elements,
                [0.035, 0.035, 0.055, 1.0],
                FrameFlags::empty(),
            ) {
                Ok(result) => result,
                Err(error) if head.mode != original_mode => {
                    head.rollback(original_mode, state, error.to_string())?;
                    continue;
                }
                Err(error) => return Err(error.into()),
            };
            head.dirty = false;
            if !result.is_empty {
                // KMS cannot always wait on the renderer's fence (for example,
                // when the driver cannot export it). Finish before submitting.
                if result.needs_sync() {
                    if let PrimaryPlaneElement::Swapchain(element) = &result.primary_element {
                        element.sync.wait().context("Wait for display rendering")?;
                    }
                }
                if let Err(error) = head.scanout.queue_frame(()) {
                    if head.mode != original_mode {
                        head.rollback(original_mode, state, error.to_string())?;
                        continue;
                    }
                    return Err(error.into());
                }
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
    let devices = Rc::new(RefCell::new((0, Vec::<InputDevice>::new())));
    let input_devices = devices.clone();
    event_loop
        .handle()
        .insert_source(
            LibinputInputBackend::new(input.clone()),
            move |event, _, data| {
                match &event {
                    InputEvent::DeviceAdded { device } => {
                        let mut devices = input_devices.borrow_mut();
                        devices.0 += 1;
                        devices.1.push(device.clone());
                    }
                    InputEvent::DeviceRemoved { device } => {
                        let mut devices = input_devices.borrow_mut();
                        devices.0 += 1;
                        devices.1.retain(|d| d != device);
                    }
                    _ => (),
                }
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
    let mut renderer = unsafe { GlesRenderer::new(context) }?;
    let decorations = crate::decoration::Renderer::new(&mut renderer)?;
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
        decorations,
        rescan: true,
        devices,
        input_revision: None,
        tick: Instant::now(),
    };
    native.scan(data)?;
    let native = Rc::new(RefCell::new(native));
    data.native = Some(native.clone());
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
    event_loop
        .handle()
        .insert_source(Timer::immediate(), move |_, _, _| {
            // Keep animations and live configuration moving without imposing a
            // polling delay on input, client commits, or page-flip completion.
            let backend = native.borrow();
            let refresh = backend
                .heads
                .iter()
                .filter_map(|h| h.output.current_mode())
                .map(|m| m.refresh)
                .max()
                .unwrap_or(60_000)
                .max(1);
            TimeoutAction::ToDuration(Duration::from_secs_f64(1000.0 / refresh as f64))
        })
        .map_err(|e| anyhow::anyhow!("{}", e.error))?;
    Ok(())
}

/// Render after dispatching events, so client commits and completed page flips
/// can use the next refresh instead of waiting for an unrelated 16 ms timer.
pub(crate) fn dispatch(data: &mut CalloopData) {
    if let Some(native) = data.native.clone() {
        let mut backend = native.borrow_mut();
        if let Some(vt) = data.state.vt_request.take() {
            if let Err(e) = backend.session.change_vt(vt) {
                eprintln!("Switch VT: {e}");
            } else {
                // Yield so libseat can report a pause before drawing again.
                // Do not mark the seat inactive here: switching to the current
                // VT succeeds without a later activation event.
                return;
            }
        }
        if let Err(e) = backend.draw(data) {
            let temporarily_inactive = e.chain().any(|cause| match cause
                .downcast_ref::<smithay::backend::drm::DrmError>(
            ) {
                Some(smithay::backend::drm::DrmError::DeviceInactive) => true,
                Some(smithay::backend::drm::DrmError::Access(access)) => {
                    access.source.kind() == std::io::ErrorKind::PermissionDenied
                }
                _ => false,
            });
            if temporarily_inactive {
                // An externally initiated VT switch can race a page flip too.
                data.state.needs_redraw = true;
            } else {
                data.state.runtime_error = Some(format!("Render displays: {e:#}"));
                data.state.loop_signal.stop();
            }
        }
    }
}
