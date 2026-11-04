use crate::{CalloopData, Smallvil};
use ::winit::platform::wayland::WindowAttributesExtWayland;
use smithay::{
    backend::{
        egl::EGLDevice,
        renderer::{
            damage::OutputDamageTracker,
            element::{
                surface::{render_elements_from_surface_tree, WaylandSurfaceRenderElement},
                Kind,
            },
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

pub fn init_winit(
    event_loop: &mut EventLoop<CalloopData>,
    data: &mut CalloopData,
) -> anyhow::Result<()> {
    let attributes = ::winit::window::Window::default_attributes()
        .with_name("ohmansy-compositor", "ohmansy")
        .with_title(if data.state.test_input {
            "ohmansy compositor test"
        } else {
            "ohmansy compositor"
        })
        .with_inner_size(::winit::dpi::LogicalSize::new(1360.0, 850.0));
    let (mut graphics, events) = winit::init_from_attributes::<GlesRenderer>(attributes)
        .map_err(|error| anyhow::anyhow!("{error}"))?;
    let formats = graphics.renderer().dmabuf_formats();
    let device = EGLDevice::device_for_display(graphics.renderer().egl_context().display())
        .and_then(|device| {
            device
                .render_device_path()
                .or_else(|_| device.drm_device_path())
        })
        .ok()
        .and_then(|path| std::fs::metadata(path).ok())
        .map(|metadata| metadata.rdev());
    let global = if let Some(device) = device {
        let feedback = DmabufFeedbackBuilder::new(device, formats.clone()).build()?;
        data.state
            .dmabuf_state
            .create_global_with_default_feedback::<Smallvil>(&data.display_handle, &feedback)
    } else {
        eprintln!("No EGL device metadata: using DMA-BUF v3 fallback");
        data.state
            .dmabuf_state
            .create_global::<Smallvil>(&data.display_handle, formats)
    };
    data.state.dmabuf_global = Some(global);
    let mode = Mode {
        size: graphics.window_size(),
        refresh: 60_000,
    };
    let output = Output::new(
        "ohmansy-lab".into(),
        PhysicalProperties {
            size: (0, 0).into(),
            subpixel: Subpixel::Unknown,
            make: "ohmansy".into(),
            model: "Nested desktop".into(),
        },
    );
    let _global = output.create_global::<Smallvil>(&data.display_handle);
    output.change_current_state(
        Some(mode),
        Some(Transform::Flipped180),
        Some(Scale::Custom {
            advertised_integer: 2,
            fractional: data.state.ui_scale,
        }),
        Some((0, 0).into()),
    );
    output.set_preferred(mode);
    data.state.space.map_output(&output, (0, 0));
    data.state.relayout();
    let mut damage_tracker = OutputDamageTracker::from_output(&output);
    let mut last_scale = data.state.ui_scale;
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
            if state.windows.values().any(|window| !window.alive()) {
                state.relayout();
                state.sync_focus();
            }
            if state.screenshot.is_some() && state.start_time.elapsed() > Duration::from_secs(2) {
                state.needs_redraw = true;
            }
            if state.needs_redraw || !state.pending_imports.is_empty() {
                timer_backend.borrow().window().request_redraw();
            }
            TimeoutAction::ToDuration(Duration::from_millis(16))
        })
        .map_err(|error| anyhow::anyhow!("{}", error.error))?;

    event_loop
        .handle()
        .insert_source(events, move |event, _, data| {
            let mut backend = backend.borrow_mut();
            let state = &mut data.state;
            match event {
                WinitEvent::Resized { size, .. } => {
                    output.change_current_state(
                        Some(Mode {
                            size,
                            refresh: 60_000,
                        }),
                        None,
                        None,
                        None,
                    );
                    state.relayout();
                }
                WinitEvent::Input(event) => state.process_input_event(event),
                WinitEvent::Redraw => {
                    use smithay::input::pointer::{CursorImageAttributes, CursorImageStatus};
                    match &state.cursor_image {
                        CursorImageStatus::Named(icon) => {
                            backend.window().set_cursor_visible(true);
                            backend.window().set_cursor(*icon);
                        }
                        _ => backend.window().set_cursor_visible(false),
                    }
                    for (buffer, notifier) in state.pending_imports.drain(..) {
                        if backend.renderer().import_dmabuf(&buffer, None).is_ok() {
                            state.dmabuf_imports += 1;
                            let _ = notifier.successful::<Smallvil>();
                        } else {
                            state.dmabuf_failures += 1;
                            notifier.failed();
                        }
                    }
                    if state.ui_scale != last_scale {
                        last_scale = state.ui_scale;
                        output.change_current_state(
                            None,
                            None,
                            Some(Scale::Custom {
                                advertised_integer: 2,
                                fractional: last_scale,
                            }),
                            None,
                        );
                        state.relayout();
                        backend.window().set_title(&format!(
                            "ohmansy compositor · {:.0}% scale",
                            last_scale * 100.0
                        ));
                    }
                    state.space.refresh();
                    state.needs_redraw = false;
                    let size = backend.window_size();
                    if size.w <= 0 || size.h <= 0 {
                        return;
                    }
                    let damage = Rectangle::from_size(size);
                    let mut screenshot = None;
                    let render = (|| -> anyhow::Result<()> {
                        let (renderer, mut framebuffer) = backend.bind()?;
                        let mut overlays: Vec<WaylandSurfaceRenderElement<GlesRenderer>> = vec![];
                        let pointer = state.seat.get_pointer().unwrap().current_location();
                        if let CursorImageStatus::Surface(surface) = &state.cursor_image {
                            let hotspot =
                                smithay::wayland::compositor::with_states(surface, |states| {
                                    states
                                        .data_map
                                        .get::<std::sync::Mutex<CursorImageAttributes>>()
                                        .map(|attributes| attributes.lock().unwrap().hotspot)
                                        .unwrap_or_default()
                                });
                            overlays.extend(render_elements_from_surface_tree(
                                renderer,
                                surface,
                                (pointer - hotspot.to_f64())
                                    .to_physical_precise_round(state.ui_scale),
                                state.ui_scale,
                                1.0,
                                Kind::Cursor,
                            ));
                        }
                        if let Some(surface) = &state.drag_icon {
                            overlays.extend(render_elements_from_surface_tree(
                                renderer,
                                surface,
                                pointer.to_physical_precise_round(state.ui_scale),
                                state.ui_scale,
                                1.0,
                                Kind::Unspecified,
                            ));
                        }
                        smithay::desktop::space::render_output::<
                            _,
                            WaylandSurfaceRenderElement<GlesRenderer>,
                            _,
                            _,
                        >(
                            &output,
                            renderer,
                            &mut framebuffer,
                            1.0,
                            0,
                            [&state.space],
                            &overlays,
                            &mut damage_tracker,
                            [0.035, 0.035, 0.055, 1.0],
                        )?;
                        if state.start_time.elapsed() > Duration::from_secs(2) {
                            if let Some(path) = state.screenshot.take() {
                                let mapping = renderer.copy_framebuffer(
                                    &framebuffer,
                                    Rectangle::from_size((size.w, size.h).into()),
                                    smithay::backend::allocator::Fourcc::Abgr8888,
                                )?;
                                screenshot = Some((path, mapping));
                            }
                        }
                        Ok(())
                    })();
                    if let Err(error) = render {
                        state.runtime_error = Some(format!("{error:#}"));
                        state.loop_signal.stop();
                        return;
                    }
                    if let Err(error) = backend.submit(Some(&[damage])) {
                        state.runtime_error = Some(error.to_string());
                        state.loop_signal.stop();
                        return;
                    }
                    state.rendered_frames += 1;
                    if let Some((path, mapping)) = screenshot {
                        let result = (|| -> anyhow::Result<()> {
                            // Map after swap: readback makes the EGL context surfaceless.
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
                            image.save(&path)?;
                            eprintln!("Saved compositor image: {}", path.display());
                            Ok(())
                        })();
                        if let Err(error) = result {
                            eprintln!("Screenshot failed: {error:#}");
                        }
                    }
                    state.space.elements().for_each(|window| {
                        window.send_frame(
                            &output,
                            state.start_time.elapsed(),
                            Some(Duration::ZERO),
                            |_, _| Some(output.clone()),
                        );
                    });
                    state.popups.cleanup();
                    let _ = data.display_handle.flush_clients();
                }
                WinitEvent::CloseRequested => state.loop_signal.stop(),
                _ => (),
            }
        })
        .map_err(|error| anyhow::anyhow!("{}", error.error))?;
    Ok(())
}
