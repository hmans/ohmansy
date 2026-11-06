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
                surface::{render_elements_from_surface_tree, WaylandSurfaceRenderElement},
                utils::{CropRenderElement, RescaleRenderElement},
                AsRenderElements, Kind,
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
    pub SceneElement<=GlesRenderer>;
    Window=CropRenderElement<WaylandSurfaceRenderElement<GlesRenderer>>,
    Rounded=CropRenderElement<crate::decoration::RoundedSurface>,
    Ring=CropRenderElement<smithay::backend::renderer::gles::element::PixelShaderElement>,
    Surface=WaylandSurfaceRenderElement<GlesRenderer>,
    Cursor=MemoryRenderBufferRenderElement<GlesRenderer>,
}
pub type OutputElement = RescaleRenderElement<SceneElement>;

#[derive(Default)]
pub struct Cursors {
    images: HashMap<(String, u32), (MemoryRenderBuffer, (i32, i32))>,
}
impl Cursors {
    fn image(
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
        let render_layers =
            |renderer: &mut GlesRenderer, kinds: &[smithay::wayland::shell::wlr_layer::Layer]| {
                let mut rendered = Vec::new();
                for kind in kinds {
                    for (layer, location) in layers
                        .iter()
                        .rev()
                        .filter(|(layer, _)| layer.layer() == *kind)
                    {
                        rendered.extend(
                            layer
                                .render_elements::<WaylandSurfaceRenderElement<GlesRenderer>>(
                                    renderer,
                                    (location.x, location.y).into(),
                                    1.0.into(),
                                    1.0,
                                )
                                .into_iter()
                                .filter_map(|element| {
                                    CropRenderElement::from_element(element, 1.0, crop)
                                })
                                .map(SceneElement::Window),
                        );
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
        let owned = self
            .windows
            .keys()
            .copied()
            .filter(|id| self.layout.owner(*id) == Some(index))
            .collect();
        for window in self.space.elements().rev() {
            let Some(id) = self.window_id(window.toplevel().unwrap().wl_surface()) else {
                continue;
            };
            if self.layout.owner(id) != Some(index) {
                continue;
            }
            let location =
                self.space.element_location(window).unwrap() - window.geometry().loc - origin;
            let surface = window.toplevel().unwrap().wl_surface();
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
                    if let Some(element) = CropRenderElement::from_element(element, 1.0, crop) {
                        elements.push(SceneElement::Window(element));
                    }
                }
            }
            let bounds = Rectangle::new(location + window.geometry().loc, window.geometry().size);
            let style = &self.output_settings.decorations;
            if !fullscreen
                && self.layout.focused() == Some(id)
                && style.focus_ring_width > 0
                && self.seat.get_keyboard().unwrap().current_focus().is_some()
            {
                for ring in decorations.ring(id, bounds, style, scale) {
                    if let Some(ring) = CropRenderElement::from_element(ring, 1.0, crop) {
                        elements.push(SceneElement::Ring(ring));
                    }
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
                if !fullscreen && style.corner_radius > 0 {
                    let element = decorations.rounded(
                        id,
                        element,
                        bounds,
                        style.corner_radius,
                        scale,
                        canvas,
                    );
                    if let Some(element) = CropRenderElement::from_element(element, 1.0, crop) {
                        elements.push(SceneElement::Rounded(element));
                    }
                } else if let Some(element) = CropRenderElement::from_element(element, 1.0, crop) {
                    elements.push(SceneElement::Window(element));
                }
            }
            // Elements are ordered front to back: each shadow sits below its
            // own window and above windows behind it, with output-local clipping.
            if !fullscreen && style.shadow.enabled && style.shadow.color[3] > 0.0 {
                for shadow in decorations.shadow(id, bounds, style, scale) {
                    if let Some(shadow) = CropRenderElement::from_element(shadow, 1.0, crop) {
                        elements.push(SceneElement::Ring(shadow));
                    }
                }
            }
        }
        decorations.finish_output(&self.windows.keys().copied().collect(), &owned);
        elements.extend(render_layers(renderer, &[Layer::Bottom, Layer::Background]));
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
