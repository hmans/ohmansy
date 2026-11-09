//! Output-local rendering: scrolling columns cannot leak onto their neighbours.
use crate::Smallvil;

#[derive(Clone, Copy, PartialEq, Eq)]
pub enum RenderPurpose {
    Display,
    Capture,
    CaptureWithCursor,
}
use smithay::{
    backend::{
        allocator::Fourcc,
        renderer::{
            element::{
                memory::{MemoryRenderBuffer, MemoryRenderBufferRenderElement},
                render_elements,
                surface::{
                    render_elements_from_surface_tree, WaylandSurfaceRenderElement,
                    WaylandSurfaceTexture,
                },
                utils::{CropRenderElement, RescaleRenderElement},
                AsRenderElements, Element, Kind,
            },
            gles::GlesRenderer,
        },
    },
    input::pointer::{CursorImageAttributes, CursorImageStatus},
    output::Output,
    utils::{Physical, Point, Rectangle, Transform},
    wayland::compositor::with_states,
};
use std::collections::HashMap;

render_elements! {
    pub WindowVisual<=GlesRenderer>;
    Surface=WaylandSurfaceRenderElement<GlesRenderer>,
    Rounded=crate::decoration::RoundedSurface,
    Decoration=smithay::backend::renderer::gles::element::PixelShaderElement,
    Title=MemoryRenderBufferRenderElement<GlesRenderer>,
    Frost=crate::frost::ElementType,
}
render_elements! {
    pub SceneElement<=GlesRenderer>;
    Window=CropRenderElement<WaylandSurfaceRenderElement<GlesRenderer>>,
    Visual=CropRenderElement<RescaleRenderElement<WindowVisual>>,
    Surface=WaylandSurfaceRenderElement<GlesRenderer>,
    Cursor=MemoryRenderBufferRenderElement<GlesRenderer>,
}
pub type OutputElement = RescaleRenderElement<SceneElement>;

#[derive(Default)]
pub struct Cursors {
    images: HashMap<(String, u32), (MemoryRenderBuffer, (i32, i32))>,
}
impl Cursors {
    pub(crate) fn image(
        &mut self,
        icon: ::winit::window::CursorIcon,
        scale: f64,
    ) -> &(MemoryRenderBuffer, (i32, i32)) {
        let density = scale.ceil().max(1.0) as u32;
        let key = (icon.name().to_owned(), density);
        self.images.entry(key).or_insert_with(|| {
            let theme = xcursor::CursorTheme::load(
                &std::env::var("XCURSOR_THEME").unwrap_or_else(|_| "Adwaita".into()),
            );
            let size = std::env::var("XCURSOR_SIZE")
                .ok()
                .and_then(|v| v.parse::<u32>().ok())
                .unwrap_or(24)
                * density;
            let image = std::iter::once(icon.name())
                .chain(icon.alt_names().iter().copied())
                .chain(["default"])
                .find_map(|name| {
                    theme
                        .load_icon(name)
                        .and_then(|p| std::fs::read(p).ok())
                        .and_then(|bytes| xcursor::parser::parse_xcursor(&bytes))
                })
                .and_then(|images| {
                    images
                        .into_iter()
                        .min_by_key(|image| image.size.abs_diff(size))
                });
            let (pixels, width, height, hotspot) = if let Some(image) = image {
                (
                    image.pixels_rgba,
                    image.width,
                    image.height,
                    (
                        image.xhot as i32 / density as i32,
                        image.yhot as i32 / density as i32,
                    ),
                )
            } else {
                eprintln!("Cursor theme unavailable; using built-in arrow");
                let mut pixels = vec![0; 24 * 24 * 4];
                for y in 0..22 {
                    for x in 0..=y / 2 {
                        let i = (y * 24 + x) * 4;
                        let value = if x == 0 || x == y / 2 { 0 } else { 255 };
                        pixels[i..i + 4].copy_from_slice(&[value, value, value, 255]);
                    }
                }
                (pixels, 24, 24, (0, 0))
            };
            (
                MemoryRenderBuffer::from_slice(
                    &pixels,
                    Fourcc::Abgr8888,
                    (width as i32, height as i32),
                    density as i32,
                    Transform::Normal,
                    None,
                ),
                hotspot,
            )
        })
    }
}

impl Smallvil {
    pub fn output_elements(
        &mut self,
        renderer: &mut GlesRenderer,
        output: &Output,
        mut named: Option<&mut Cursors>,
        decorations: &mut crate::decoration::Renderer,
        canvas: Point<i32, Physical>,
        purpose: RenderPurpose,
    ) -> Vec<OutputElement> {
        let Some(index) = self
            .layout
            .monitors
            .iter()
            .position(|m| m.name == output.name())
        else {
            return vec![];
        };
        let monitor = &self.layout.monitors[index];
        let origin: Point<i32, smithay::utils::Logical> = monitor.origin.into();
        let scale = monitor.scale;
        let crop = Rectangle::<i32, Physical>::from_size(monitor.layout.size.into());
        let mut elements: Vec<SceneElement> = vec![];
        let pointer = self.seat.get_pointer().unwrap().current_location();
        if self.layout.at(pointer.x, pointer.y) == Some(index) {
            let local = pointer - origin.to_f64();
            match &self.cursor_image {
                _ if purpose == RenderPurpose::Capture => (),
                CursorImageStatus::Surface(surface) => {
                    let hotspot = with_states(surface, |s| {
                        s.data_map
                            .get::<std::sync::Mutex<CursorImageAttributes>>()
                            .map(|a| a.lock().unwrap().hotspot)
                            .unwrap_or_default()
                    });
                    let rendered = render_elements_from_surface_tree::<
                        GlesRenderer,
                        WaylandSurfaceRenderElement<GlesRenderer>,
                    >(
                        renderer,
                        surface,
                        (local - hotspot.to_f64()).to_physical_precise_round(1.0),
                        1.0,
                        1.0,
                        Kind::Cursor,
                    );
                    self.cursor_rendered_elements = rendered.len();
                    elements.extend(rendered.into_iter().map(SceneElement::Surface));
                }
                CursorImageStatus::Named(icon) => {
                    if let Some(cursors) = named.as_mut() {
                        let (image, hotspot) = cursors.image(*icon, scale);
                        if let Ok(element) = MemoryRenderBufferRenderElement::from_buffer(
                            renderer,
                            (local.x - hotspot.0 as f64, local.y - hotspot.1 as f64),
                            image,
                            None,
                            None,
                            None,
                            Kind::Cursor,
                        ) {
                            elements.push(SceneElement::Cursor(element));
                        }
                    }
                }
                _ => (),
            }
            if let Some(surface) = &self.drag_icon {
                elements.extend(
                    render_elements_from_surface_tree::<
                        GlesRenderer,
                        WaylandSurfaceRenderElement<GlesRenderer>,
                    >(
                        renderer,
                        surface,
                        local.to_physical_precise_round(1.0),
                        1.0,
                        1.0,
                        Kind::Unspecified,
                    )
                    .into_iter()
                    .map(SceneElement::Surface),
                );
            }
        }
        let layer_map = smithay::desktop::layer_map_for_output(output);
        let layers: Vec<_> = layer_map
            .layers()
            .filter(|layer| {
                purpose == RenderPurpose::Display
                    || layer.namespace() != "ohmansy-screenshot-result"
            })
            .filter_map(|layer| {
                layer_map
                    .layer_geometry(layer)
                    .map(|geometry| (layer.clone(), geometry.loc))
            })
            .collect();
        drop(layer_map);
        let fullscreen = monitor.layout.workspace().fullscreen.is_some();
        let mut direct_background = None;
        let mut render_layers =
            |renderer: &mut GlesRenderer, kinds: &[smithay::wayland::shell::wlr_layer::Layer]| {
                let mut rendered = Vec::new();
                for kind in kinds {
                    for (layer, location) in layers
                        .iter()
                        .rev()
                        .filter(|(layer, _)| layer.layer() == *kind)
                    {
                        for element in layer
                            .render_elements::<WaylandSurfaceRenderElement<GlesRenderer>>(
                                renderer,
                                (location.x, location.y).into(),
                                1.0.into(),
                                1.0,
                            )
                        {
                            if layer.namespace() == "ohmansy-wallpaper"
                                && element.geometry(1.0.into()).contains_rect(crop)
                                && element.transform() == Transform::Normal
                                && element.alpha() == 1.0
                                // Let ordinary surface compositing normalize
                                // inverted imports before the shared filter.
                                && matches!(element.texture(), WaylandSurfaceTexture::Texture(texture) if !texture.is_y_inverted())
                            {
                                if let WaylandSurfaceTexture::Texture(texture) = element.texture() {
                                    let geometry = element.geometry(1.0.into());
                                    let src = element.src();
                                    let ratio = src.size / geometry.size.to_f64();
                                    let source = Rectangle::new(
                                        (
                                            src.loc.x
                                                + (crop.loc.x - geometry.loc.x) as f64 * ratio.x,
                                            src.loc.y
                                                + (crop.loc.y - geometry.loc.y) as f64 * ratio.y,
                                        )
                                            .into(),
                                        (
                                            crop.size.w as f64 * ratio.x,
                                            crop.size.h as f64 * ratio.y,
                                        )
                                            .into(),
                                    );
                                    direct_background = Some((
                                        element.id().clone(),
                                        crate::frost::DirectSource {
                                            texture: texture.clone(),
                                            source,
                                        },
                                    ));
                                }
                            }
                            if let Some(element) =
                                CropRenderElement::from_element(element, 1.0, crop)
                            {
                                rendered.push(SceneElement::Window(element));
                            }
                        }
                    }
                }
                rendered
            };
        use smithay::wayland::shell::wlr_layer::Layer;
        elements.extend(render_layers(renderer, &[Layer::Overlay]));
        if !fullscreen {
            elements.extend(render_layers(renderer, &[Layer::Top]));
        }
        decorations.begin_output();
        let background = render_layers(renderer, &[Layer::Bottom, Layer::Background]);
        let direct_background = direct_background
            .as_ref()
            .filter(|(id, _)| background.len() == 1 && background[0].id() == id)
            .map(|(_, source)| source);
        let mut windows: Vec<crate::frost::Layer> = Vec::new();
        let owned = self
            .windows
            .keys()
            .copied()
            .filter(|id| self.layout.owner(*id) == Some(index))
            .collect();
        // Build bottom-to-top so glass snapshots contain only the scene behind
        // each window. Final elements remain ordered front-to-back.
        for window in self.space.elements() {
            let Some(id) = self.window_id(window.toplevel().unwrap().wl_surface()) else {
                continue;
            };
            if self.layout.owner(id) != Some(index) {
                continue;
            }
            let fullscreen = self.layout.fullscreen_for(id);
            let location =
                self.space.element_location(window).unwrap() - window.geometry().loc - origin;
            let surface = window.toplevel().unwrap().wl_surface();
            let bounds = Rectangle::new(location + window.geometry().loc, window.geometry().size);
            let frame_bounds = self
                .output_settings
                .decorations
                .frame
                .bounds(bounds, fullscreen);
            let center = (frame_bounds.loc
                + Point::from((frame_bounds.size.w / 2, frame_bounds.size.h / 2)))
            .to_physical_precise_round(1.0);
            let visual_scale = self.window_visual_scale(id);
            let mut backdrop_bounds = frame_bounds;
            let mut visual = Vec::new();
            let amount = self.inactive_amount(id) as f32;
            let inactive = &self.output_settings.decorations.inactive;
            // Popups have their own geometry and may extend beyond the window.
            for (popup, offset) in smithay::desktop::PopupManager::popups_for_surface(surface) {
                let popup_location =
                    location + window.geometry().loc + offset - popup.geometry().loc;
                for element in render_elements_from_surface_tree::<
                    GlesRenderer,
                    WaylandSurfaceRenderElement<GlesRenderer>,
                >(
                    renderer,
                    popup.wl_surface(),
                    (popup_location.x, popup_location.y),
                    1.0,
                    1.0,
                    Kind::Unspecified,
                ) {
                    let geometry = smithay::backend::renderer::element::Element::geometry(
                        &element,
                        1.0.into(),
                    );
                    let bounds =
                        Rectangle::new(geometry.loc.to_logical(1), geometry.size.to_logical(1));
                    backdrop_bounds = backdrop_bounds.merge(bounds);
                    visual.push(WindowVisual::Rounded(
                        decorations
                            .rounded(
                                id, element, bounds, 0, None, scale, canvas, amount, inactive,
                            )
                            .rescale(center, visual_scale, scale, canvas),
                    ));
                }
            }
            let style = &self.output_settings.decorations;
            if !fullscreen && style.frame.enabled {
                let mut ring_style = style.clone();
                ring_style.frame.active_color = self.frame_focus_color(id);
                {
                    if let Some(title) = decorations.titles.element(
                        renderer,
                        id,
                        window,
                        frame_bounds,
                        &ring_style.frame,
                        scale,
                    ) {
                        visual.push(WindowVisual::Title(title));
                    }
                    if !style.frame.glass.enabled {
                        for ring in decorations.frame(id, frame_bounds, &ring_style, scale) {
                            visual.push(WindowVisual::Decoration(ring));
                        }
                    }
                }
            }
            if !fullscreen
                && style.frame.enabled
                && style.frame.inset_shadow.enabled
                && style.frame.inset_shadow.width > 0.0
                && style.frame.inset_shadow.color[3] > 0.0
            {
                for shadow in decorations.inset(id, bounds, style, scale) {
                    // After popups/caption in the front-to-back list, but above
                    // every client subsurface. This never modifies app buffers.
                    visual.push(WindowVisual::Decoration(shadow));
                }
            }
            for element in render_elements_from_surface_tree::<
                GlesRenderer,
                WaylandSurfaceRenderElement<GlesRenderer>,
            >(
                renderer,
                surface,
                (location.x, location.y),
                1.0,
                1.0,
                Kind::Unspecified,
            ) {
                if !fullscreen {
                    let element = decorations.rounded(
                        id,
                        element,
                        bounds,
                        style.inner_radius(),
                        style
                            .frame
                            .enabled
                            .then_some((frame_bounds, style.outer_radius())),
                        scale,
                        canvas,
                        amount,
                        inactive,
                    );
                    visual.push(WindowVisual::Rounded(element.rescale(
                        center,
                        visual_scale,
                        scale,
                        canvas,
                    )));
                } else {
                    visual.push(WindowVisual::Surface(element));
                }
            }
            let terminal_blur = &style.terminal_blur;
            let terminal = terminal_blur.enabled
                && terminal_blur.radius > 0
                && with_states(surface, |states| {
                    let metadata = states
                        .data_map
                        .get::<smithay::wayland::shell::xdg::XdgToplevelSurfaceData>()
                        .unwrap()
                        .lock()
                        .unwrap();
                    metadata
                        .app_id
                        .as_ref()
                        .is_some_and(|app| terminal_blur.app_ids.contains(app))
                });
            // Window::geometry also reads renderer surface state. Resolve it
            // before taking that lock, including for partial opaque regions.
            let client_geometry = window.geometry();
            let opaque = terminal
                && with_states(surface, |states| {
                    states
                        .data_map
                        .get::<smithay::backend::renderer::utils::RendererSurfaceStateUserData>()
                        .is_some_and(|data| {
                            data.lock()
                                .unwrap()
                                .opaque_regions()
                                .is_some_and(|regions| {
                                    client_geometry
                                        .subtract_rects(regions.iter().copied())
                                        .is_empty()
                                })
                        })
                });
            if terminal
                && !opaque
                && frame_bounds.overlaps(Rectangle::from_size(crop.size.to_logical(1)))
            {
                let mut glass = style.frame.clone();
                glass.glass.blur_radius = terminal_blur.radius;
                if fullscreen || !glass.enabled {
                    glass.width = 0;
                    glass.titlebar_height = 0;
                    glass.outer_corner_radius = if fullscreen { 0 } else { style.corner_radius };
                    glass.inner_corner_radius = glass.outer_corner_radius;
                }
                match decorations.frost.element(
                    renderer,
                    &output.name(),
                    id,
                    frame_bounds,
                    &glass,
                    scale,
                    visual_scale,
                    canvas,
                    crop.size.to_logical(1).to_physical_precise_round(scale),
                    &windows,
                    &background,
                    direct_background,
                    true,
                ) {
                    Ok(backdrop) => visual.push(WindowVisual::Frost(backdrop)),
                    Err(error) => eprintln!("Terminal blur unavailable: {error:#}"),
                }
            }
            // Elements are ordered front to back: each shadow sits below its
            // own window and above windows behind it, with output-local clipping.
            if !fullscreen
                && style.frame.enabled
                && style.frame.glass.enabled
                && frame_bounds.overlaps(Rectangle::from_size(crop.size.to_logical(1)))
            {
                let mut glass = style.frame.clone();
                glass.active_color = self.frame_focus_color(id);
                match decorations.frost.element(
                    renderer,
                    &output.name(),
                    id,
                    frame_bounds,
                    &glass,
                    scale,
                    visual_scale,
                    canvas,
                    crop.size.to_logical(1).to_physical_precise_round(scale),
                    &windows,
                    &background,
                    direct_background,
                    false,
                ) {
                    Ok(frame) => visual.push(WindowVisual::Frost(frame)),
                    Err(error) => {
                        eprintln!("Window glass unavailable: {error:#}");
                        let mut fallback = style.clone();
                        fallback.frame = glass;
                        for frame in decorations.frame(id, frame_bounds, &fallback, scale) {
                            visual.push(WindowVisual::Decoration(frame));
                        }
                    }
                }
            }
            if !fullscreen && style.shadow.enabled && style.shadow.color[3] > 0.0 {
                for shadow in decorations.shadow(id, frame_bounds, style, scale) {
                    visual.push(WindowVisual::Decoration(shadow));
                }
            }
            let mut current = Vec::new();
            for element in visual {
                let element = RescaleRenderElement::from_element(element, center, visual_scale);
                if let Some(element) = CropRenderElement::from_element(element, 1.0, crop) {
                    current.push(SceneElement::Visual(element));
                }
            }
            windows.insert(
                0,
                crate::frost::Layer {
                    id,
                    bounds: backdrop_bounds,
                    elements: current,
                },
            );
        }
        decorations.restore_draw_buffer |=
            std::mem::take(&mut decorations.frost.offscreen_rendered);
        decorations.finish_output(&self.windows.keys().copied().collect(), &owned);
        decorations.frost.finish_output(&output.name());
        self.blur_stats = decorations.frost.stats();
        elements.extend(windows.into_iter().flat_map(|layer| layer.elements));
        elements.extend(background);
        elements
            .into_iter()
            .map(|element| RescaleRenderElement::from_element(element, (0, 0).into(), scale))
            .collect()
    }

    pub fn send_output_frames(&mut self, output: &Output) {
        for layer in smithay::desktop::layer_map_for_output(output).layers() {
            layer.send_frame(
                output,
                self.start_time.elapsed(),
                Some(std::time::Duration::ZERO),
                |_, _| Some(output.clone()),
            );
        }
        for window in self.space.elements() {
            let Some(id) = self.window_id(window.toplevel().unwrap().wl_surface()) else {
                continue;
            };
            if self
                .layout
                .owner(id)
                .is_some_and(|index| self.layout.monitors[index].name == output.name())
            {
                // Mapped columns can sit entirely outside the scrolled view.
                // Include popups in the bounds so a visible menu still advances.
                let visible = self
                    .space
                    .element_location(window)
                    .and_then(|location| {
                        let mut bounds = window.bbox_with_popups();
                        bounds.loc += location - window.geometry().loc;
                        self.space
                            .output_geometry(output)
                            .map(|view| bounds.overlaps(view))
                    })
                    .unwrap_or(false);
                if !visible {
                    continue;
                }
                window.send_frame(
                    output,
                    self.start_time.elapsed(),
                    Some(std::time::Duration::ZERO),
                    |_, _| Some(output.clone()),
                );
            }
        }
        if let CursorImageStatus::Surface(surface) = &self.cursor_image {
            smithay::desktop::utils::send_frames_surface_tree(
                surface,
                output,
                self.start_time.elapsed(),
                Some(std::time::Duration::ZERO),
                |_, _| Some(output.clone()),
            );
        }
    }
}
