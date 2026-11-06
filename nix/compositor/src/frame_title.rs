//! Cached, shaped title text and desktop-entry icons for compositor frames.
use crate::{layout::WindowId, preferences::Frame};
use smithay::{
    backend::{
        allocator::Fourcc,
        renderer::{
            element::{
                memory::{MemoryRenderBuffer, MemoryRenderBufferRenderElement},
                Kind,
            },
            gles::GlesRenderer,
        },
    },
    desktop::Window,
    utils::{Logical, Rectangle, Transform},
    wayland::{compositor::with_states, shell::xdg::XdgToplevelSurfaceData},
};
use std::{
    collections::{HashMap, HashSet},
    path::PathBuf,
};

#[derive(PartialEq)]
struct Key {
    title: String,
    app: String,
    width: i32,
    height: i32,
    density: i32,
    font_size: f64,
    icon_width: u32,
    icon_height: u32,
    padding: u32,
    gap: u32,
    radius: u32,
    window_height: i32,
}
struct Title {
    key: Key,
    buffer: MemoryRenderBuffer,
}
#[derive(Default)]
pub struct Renderer {
    titles: HashMap<WindowId, Title>,
    icons: HashMap<(String, u32), Option<cairo::ImageSurface>>,
    applications: Option<HashMap<String, String>>,
}
impl Renderer {
    pub fn retain(&mut self, live: &HashSet<WindowId>) {
        self.titles.retain(|id, _| live.contains(id));
    }
    pub fn element(
        &mut self,
        renderer: &mut GlesRenderer,
        id: WindowId,
        window: &Window,
        bounds: Rectangle<i32, Logical>,
        frame: &Frame,
        scale: f64,
    ) -> Option<MemoryRenderBufferRenderElement<GlesRenderer>> {
        let (title, app) = with_states(window.toplevel()?.wl_surface(), |states| {
            let metadata = states
                .data_map
                .get::<XdgToplevelSurfaceData>()
                .unwrap()
                .lock()
                .unwrap();
            (
                metadata.title.clone().unwrap_or_default(),
                metadata.app_id.clone().unwrap_or_default(),
            )
        });
        let key = Key {
            title,
            app,
            width: bounds.size.w,
            height: frame.titlebar_height as i32,
            density: scale.ceil() as i32,
            font_size: frame.title_font_size,
            icon_width: frame.icon_width,
            icon_height: frame.icon_height,
            padding: frame.title_padding,
            gap: frame.icon_title_gap,
            radius: frame.outer_corner_radius,
            window_height: bounds.size.h,
        };
        if self.titles.get(&id).is_none_or(|cached| cached.key != key) {
            let buffer = self
                .render(&key)
                .map_err(|e| eprintln!("Window title unavailable: {e:#}"))
                .ok()?;
            self.titles.insert(id, Title { key, buffer });
        }
        let cached = self.titles.get(&id)?;
        MemoryRenderBufferRenderElement::from_buffer(
            renderer,
            bounds.loc.to_f64().to_physical(1.0),
            &cached.buffer,
            None,
            None,
            None,
            Kind::Unspecified,
        )
        .ok()
    }
    fn render(&mut self, key: &Key) -> anyhow::Result<MemoryRenderBuffer> {
        let mut surface = cairo::ImageSurface::create(
            cairo::Format::ARgb32,
            key.width * key.density,
            key.height * key.density,
        )?;
        {
            let context = cairo::Context::new(&surface)?;
            context.scale(key.density as f64, key.density as f64);
            let r = (key.radius as f64).min(key.width.min(key.window_height) as f64 / 2.0);
            let (w, h) = (key.width as f64, key.window_height as f64);
            use std::f64::consts::{FRAC_PI_2, PI};
            context.new_sub_path();
            context.arc(w - r, r, r, -FRAC_PI_2, 0.0);
            context.arc(w - r, h - r, r, 0.0, FRAC_PI_2);
            context.arc(r, h - r, r, FRAC_PI_2, PI);
            context.arc(r, r, r, PI, PI + FRAC_PI_2);
            context.close_path();
            context.clip();
            context.set_source_rgb(0.95, 0.94, 0.97);
            let y = (key.height as f64 - key.icon_height as f64) / 2.0;
            context.save()?;
            context.translate(key.padding as f64, y);
            context.scale(key.icon_width as f64 / 16.0, key.icon_height as f64 / 16.0);
            if let Some(icon) = self.icon(
                &key.app,
                key.icon_width.max(key.icon_height) * key.density as u32,
            ) {
                context.scale(16.0 / icon.width() as f64, 16.0 / icon.height() as f64);
                context.set_source_surface(&icon, 0.0, 0.0)?;
                context.paint()?;
            } else {
                // A quiet window glyph when an app has no installed desktop icon.
                context.set_line_width(1.0);
                context.rectangle(1.5, 2.5, 13.0, 11.0);
                context.move_to(2.0, 5.5);
                context.line_to(14.0, 5.5);
                context.stroke()?;
            }
            context.restore()?;
            let text_x = key.padding + key.icon_width + key.gap;
            let layout = pangocairo::functions::create_layout(&context);
            let mut font = pango::FontDescription::from_string("Inter Medium");
            font.set_absolute_size(key.font_size * pango::SCALE as f64);
            layout.set_font_description(Some(&font));
            layout.set_single_paragraph_mode(true);
            layout.set_ellipsize(pango::EllipsizeMode::End);
            layout.set_width(
                (key.width - text_x as i32 - key.padding as i32 - 1).max(1) * pango::SCALE,
            );
            layout.set_text(if key.title.is_empty() {
                &key.app
            } else {
                &key.title
            });
            let (_, text_height) = layout.pixel_size();
            context.move_to(
                text_x as f64,
                ((key.height - text_height) as f64 / 2.0).floor(),
            );
            pangocairo::functions::show_layout(&context, &layout);
        }
        surface.flush();
        let data = surface.data()?;
        Ok(MemoryRenderBuffer::from_slice(
            &data,
            Fourcc::Argb8888,
            (key.width * key.density, key.height * key.density),
            key.density,
            Transform::Normal,
            None,
        ))
    }
    fn icon(&mut self, app: &str, size: u32) -> Option<cairo::ImageSurface> {
        if self.applications.is_none() {
            self.applications = Some(applications());
        }
        self.icons
            .entry((app.to_owned(), size))
            .or_insert_with(|| {
                let name = self
                    .applications
                    .as_ref()?
                    .get(&app.to_lowercase())
                    .map(String::as_str)
                    .unwrap_or(app);
                let path = if name.starts_with('/') {
                    PathBuf::from(name)
                } else {
                    freedesktop_icons::lookup(name)
                        .with_size(size as u16)
                        .with_theme("Adwaita")
                        .find()?
                };
                let bytes = std::fs::read(&path).ok()?;
                if path.extension().is_some_and(|ext| ext == "svg") {
                    let options = resvg::usvg::Options {
                        resources_dir: path.parent().map(|p| p.to_owned()),
                        ..Default::default()
                    };
                    let tree = resvg::usvg::Tree::from_data(&bytes, &options).ok()?;
                    let mut pixmap = resvg::tiny_skia::Pixmap::new(size, size)?;
                    resvg::render(
                        &tree,
                        resvg::tiny_skia::Transform::from_scale(
                            size as f32 / tree.size().width(),
                            size as f32 / tree.size().height(),
                        ),
                        &mut pixmap.as_mut(),
                    );
                    let mut pixels = pixmap.take();
                    for pixel in pixels.chunks_exact_mut(4) {
                        pixel.swap(0, 2);
                    }
                    cairo::ImageSurface::create_for_data(
                        pixels,
                        cairo::Format::ARgb32,
                        size as i32,
                        size as i32,
                        size as i32 * 4,
                    )
                    .ok()
                } else {
                    cairo::ImageSurface::create_from_png(&mut std::io::Cursor::new(bytes)).ok()
                }
            })
            .clone()
    }
}

fn applications() -> HashMap<String, String> {
    let mut roots = Vec::new();
    if let Some(data) = std::env::var_os("XDG_DATA_HOME") {
        roots.push(PathBuf::from(data));
    } else if let Some(home) = std::env::var_os("HOME") {
        roots.push(PathBuf::from(home).join(".local/share"));
    }
    roots.extend(std::env::split_paths(
        &std::env::var_os("XDG_DATA_DIRS").unwrap_or_else(|| "/usr/local/share:/usr/share".into()),
    ));
    let mut entries = HashMap::new();
    for root in roots {
        let Ok(files) = std::fs::read_dir(root.join("applications")) else {
            continue;
        };
        for file in files.flatten() {
            let path = file.path();
            if path.extension().is_none_or(|ext| ext != "desktop") {
                continue;
            }
            let Ok(contents) = std::fs::read_to_string(&path) else {
                continue;
            };
            let mut in_entry = false;
            let (mut icon, mut class) = (None, None);
            for line in contents.lines().map(str::trim) {
                if line.starts_with('[') {
                    in_entry = line == "[Desktop Entry]";
                }
                if !in_entry {
                    continue;
                }
                if let Some(value) = line.strip_prefix("Icon=") {
                    icon = Some(value.to_owned());
                }
                if let Some(value) = line.strip_prefix("StartupWMClass=") {
                    class = Some(value.to_lowercase());
                }
            }
            if let Some(icon) = icon {
                if let Some(stem) = path.file_stem().and_then(|s| s.to_str()) {
                    entries
                        .entry(stem.to_lowercase())
                        .or_insert_with(|| icon.clone());
                }
                if let Some(class) = class {
                    entries.entry(class).or_insert(icon);
                }
            }
        }
    }
    entries
}
