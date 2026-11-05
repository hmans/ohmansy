use crate::{CalloopData, Smallvil};
use ::winit::platform::wayland::WindowAttributesExtWayland;
use smithay::{
    backend::{
        egl::EGLDevice,
        renderer::{
            damage::OutputDamageTracker,
            element::utils::{Relocate, RelocateRenderElement},
            gles::GlesRenderer,
            ExportMem, ImportDma, TextureMapping,
        },
        winit::{self, WinitEvent},
    },
    output::{Mode, Output, PhysicalProperties, Scale, Subpixel},
    reexports::calloop::{
        timer::{TimeoutAction, Timer},
        EventLoop,
    },
    utils::{IsAlive, Rectangle, Transform},
    wayland::dmabuf::DmabufFeedbackBuilder,
};
use std::{
    cell::RefCell,
    os::unix::fs::MetadataExt,
    rc::Rc,
    time::{Duration, Instant},
};

fn resize(
    state: &mut Smallvil,
    outputs: &[Output],
    size: smithay::utils::Size<i32, smithay::utils::Physical>,
) {
    state.nested_canvas_size = Some((size.w, size.h));
    for (i, output) in outputs.iter().enumerate() {
        let left = size.w * i as i32 / outputs.len() as i32;
        let right = size.w * (i + 1) as i32 / outputs.len() as i32;
        let mode = Mode {
            size: ((right - left).max(1), size.h.max(1)).into(),
            refresh: 60_000,
        };
        output.change_current_state(Some(mode), None, None, None);
        output.set_preferred(mode);
    }
    state.relayout();
}

pub fn init_winit(
    event_loop: &mut EventLoop<CalloopData>,
    data: &mut CalloopData,
) -> anyhow::Result<()> {
    let attributes = ::winit::window::Window::default_attributes()
        .with_name("ohmansy-compositor", "ohmansy")
        .with_title(if data.state.test_input {
            "Shine test"
        } else {
            "Shine"
        })
        .with_inner_size(::winit::dpi::LogicalSize::new(1360.0, 850.0));
    let (mut graphics, events) = winit::init_from_attributes::<GlesRenderer>(attributes)
        .map_err(|e| anyhow::anyhow!("{e}"))?;
    let formats = graphics.renderer().dmabuf_formats();
    let mut decorations = crate::decoration::Renderer::new(graphics.renderer())?;
    let device = EGLDevice::device_for_display(graphics.renderer().egl_context().display())
        .and_then(|d| d.render_device_path().or_else(|_| d.drm_device_path()))
        .ok()
        .and_then(|path| std::fs::metadata(path).ok())
        .map(|m| m.rdev());
    let global = if let Some(device) = device {
        let feedback = DmabufFeedbackBuilder::new(device, formats).build()?;
        data.state
            .dmabuf_state
            .create_global_with_default_feedback::<Smallvil>(&data.display_handle, &feedback)
    } else {
        data.state
            .dmabuf_state
            .create_global::<Smallvil>(&data.display_handle, formats)
    };
    data.state.dmabuf_global = Some(global);
    let mut outputs = vec![];
    for i in 0..data.state.virtual_outputs {
        let output = Output::new(
            format!("SHINE-{}", i + 1),
            PhysicalProperties {
                size: (0, 0).into(),
                subpixel: Subpixel::Unknown,
                make: "ohmansy".into(),
                model: "Shine preview".into(),
            },
        );
        output.create_global::<Smallvil>(&data.display_handle);
        output.change_current_state(
            None,
            Some(Transform::Normal),
            Some(Scale::Custom {
                advertised_integer: 2,
                fractional: data.state.ui_scale,
            }),
            Some((0, 0).into()),
        );
        data.state.space.map_output(&output, (0, 0));
        outputs.push(output);
    }
    resize(&mut data.state, &outputs, graphics.window_size());
    let mut tracker = OutputDamageTracker::new(graphics.window_size(), 1.0, Transform::Flipped180);
    let backend = Rc::new(RefCell::new(graphics));
    let timer_backend = backend.clone();
    let mut tick = Instant::now();
    event_loop
        .handle()
        .insert_source(Timer::immediate(), move |_, _, data| {
            let now = Instant::now();
            let state = &mut data.state;
            if state.layout.tick((now - tick).as_secs_f64()) {
                state.apply_positions();
            }
            tick = now;
            state.maintain_scene();
            if state.screenshot.is_some() && state.start_time.elapsed() > Duration::from_secs(2) {
                state.needs_redraw = true;
            }
            if state.needs_redraw || !state.pending_imports.is_empty() {
                timer_backend.borrow().window().request_redraw();
            }
            TimeoutAction::ToDuration(Duration::from_millis(16))
        })
        .map_err(|e| anyhow::anyhow!("{}", e.error))?;
    event_loop
        .handle()
        .insert_source(events, move |event, _, data| {
            let mut backend = backend.borrow_mut();
            let state = &mut data.state;
            match event {
                WinitEvent::Resized { size, .. } => {
                    resize(state, &outputs, size);
                    tracker = OutputDamageTracker::new(size, 1.0, Transform::Flipped180);
                }
                WinitEvent::Input(event) => state.process_input_event(event),
                WinitEvent::Focus(false) if !state.test_input => state.release_keys(),
                WinitEvent::Redraw => {
                    state.import_buffers(backend.renderer());
                    state.space.refresh();
                    state.maintain_scene();
                    for output in &outputs {
                        state.capture_output(backend.renderer(), output, &mut decorations);
                    }
                    state.needs_redraw = false;
                    let size = backend.window_size();
                    if size.w <= 0 || size.h <= 0 {
                        return;
                    }
                    let damage = Rectangle::from_size(size);
                    let mut screenshot = None;
                    let render = (|| -> anyhow::Result<()> {
                        let (renderer, mut framebuffer) = backend.bind()?;
                        let mut elements = vec![];
                        let mut left = 0;
                        state.cursor_rendered_elements = 0;
                        for output in &outputs {
                            elements.extend(
                                state
                                    .output_elements(
                                        renderer,
                                        output,
                                        None,
                                        &mut decorations,
                                        (left, 0).into(),
                                        crate::scene::RenderPurpose::Display,
                                    )
                                    .into_iter()
                                    .map(|e| {
                                        RelocateRenderElement::from_element(
                                            e,
                                            (left, 0),
                                            Relocate::Relative,
                                        )
                                    }),
                            );
                            left += output.current_mode().unwrap().size.w;
                        }
                        tracker.render_output(
                            renderer,
                            &mut framebuffer,
                            0,
                            &elements,
                            [0.035, 0.035, 0.055, 1.0],
                        )?;
                        if state.start_time.elapsed() > Duration::from_secs(2) {
                            if let Some(path) = state.screenshot.take() {
                                screenshot = Some((
                                    path,
                                    renderer.copy_framebuffer(
                                        &framebuffer,
                                        Rectangle::from_size((size.w, size.h).into()),
                                        smithay::backend::allocator::Fourcc::Abgr8888,
                                    )?,
                                ));
                            }
                        }
                        Ok(())
                    })();
                    if let Err(e) =
                        render.and_then(|_| backend.submit(Some(&[damage])).map_err(Into::into))
                    {
                        state.runtime_error = Some(format!("{e:#}"));
                        state.loop_signal.stop();
                        return;
                    }
                    state.rendered_frames += 1;
                    match &state.cursor_image {
                        smithay::input::pointer::CursorImageStatus::Named(icon) => {
                            backend.window().set_cursor(*icon);
                            backend.window().set_cursor_visible(true);
                        }
                        _ => backend.window().set_cursor_visible(false),
                    }
                    if let Some((path, mapping)) = screenshot {
                        let result = (|| -> anyhow::Result<()> {
                            let bytes = backend.renderer().map_texture(&mapping)?;
                            let mut image = image::RgbaImage::from_raw(
                                size.w as u32,
                                size.h as u32,
                                bytes.to_vec(),
                            )
                            .ok_or_else(|| anyhow::anyhow!("Invalid screenshot buffer"))?;
                            if mapping.flipped() {
                                image::imageops::flip_vertical_in_place(&mut image);
                            }
                            image.save(path)?;
                            Ok(())
                        })();
                        if let Err(e) = result {
                            eprintln!("Screenshot failed: {e:#}");
                        }
                    }
                    for output in &outputs {
                        state.send_output_frames(output);
                    }
                    state.popups.cleanup();
                    let _ = data.display_handle.flush_clients();
                }
                WinitEvent::CloseRequested => state.loop_signal.stop(),
                _ => (),
            }
        })
        .map_err(|e| anyhow::anyhow!("{}", e.error))?;
    Ok(())
}

impl Smallvil {
    pub fn release_keys(&mut self) {
        let keyboard = self.seat.get_keyboard().unwrap();
        let time = self.start_time.elapsed().as_millis() as u32;
        for key in keyboard.pressed_keys() {
            self.process_key(key, smithay::backend::input::KeyState::Released, time);
        }
    }
    pub fn import_buffers(&mut self, renderer: &mut GlesRenderer) {
        for (buffer, notifier) in self.pending_imports.drain(..) {
            if renderer.import_dmabuf(&buffer, None).is_ok() {
                self.dmabuf_imports += 1;
                let _ = notifier.successful::<Smallvil>();
            } else {
                self.dmabuf_failures += 1;
                notifier.failed();
            }
        }
    }
    pub fn maintain_scene(&mut self) {
        self.poll_screenshot();
        self.poll_output_config();
        let before = self.window_preferences_applied.len();
        self.apply_window_preferences();
        if self.window_preferences_applied.len() != before {
            self.apply_positions();
        }
        if self.windows.values().any(|w| !w.alive()) {
            self.relayout();
            self.sync_focus();
        }
        if matches!(&self.cursor_image,smithay::input::pointer::CursorImageStatus::Surface(s) if !s.alive())
        {
            self.cursor_image = smithay::input::pointer::CursorImageStatus::default_named();
            self.needs_redraw = true;
        }
        let pointer = self.seat.get_pointer().unwrap();
        let position = pointer.current_location();
        let under = self.surface_under(position).map(|(s, _)| s);
        if !pointer.is_grabbed() && pointer.current_focus() != under {
            self.process_motion(position, self.start_time.elapsed().as_millis() as u32);
        }
    }
}
