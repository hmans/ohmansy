//! Cache a small window-only image; blur and enlarge it behind the window.
use crate::{layout::WindowId, preferences::Halo};
use smithay::{
    backend::{
        allocator::Fourcc,
        renderer::{
            damage::OutputDamageTracker,
            element::{
                surface::WaylandSurfaceRenderElement,
                texture::{TextureBuffer, TextureRenderElement},
                utils::CropRenderElement,
                Element, Id, Kind,
            },
            gles::{
                GlesError, GlesRenderer, GlesTexProgram, GlesTexture, Uniform, UniformName,
                UniformType,
            },
            utils::CommitCounter,
            Bind, Frame, Offscreen, Renderer as _, Texture,
        },
    },
    utils::{Logical, Physical, Rectangle, Size, Transform},
};
use std::collections::{HashMap, HashSet};

type Signature = Vec<(Id, CommitCounter, Rectangle<i32, Physical>)>;
pub type ElementType = CropRenderElement<TextureRenderElement<GlesTexture>>;
struct Cached {
    signature: Signature,
    size: Size<i32, Logical>,
    style: Halo,
    buffers: [TextureBuffer<GlesTexture>; 4],
}
pub struct Renderer {
    program: GlesTexProgram,
    windows: HashMap<WindowId, Cached>,
    used: HashSet<WindowId>,
    pub offscreen_rendered: bool,
}
impl Renderer {
    pub fn new(renderer: &mut GlesRenderer, source: &str) -> Result<Self, GlesError> {
        Ok(Self {
            program: renderer.compile_custom_texture_shader(
                source,
                &[
                    UniformName::new("blur_step", UniformType::_2f),
                    UniformName::new("window_ratio", UniformType::_2f),
                ],
            )?,
            windows: HashMap::new(),
            used: HashSet::new(),
            offscreen_rendered: false,
        })
    }
    pub fn retain(&mut self, live: &HashSet<WindowId>, owned: &HashSet<WindowId>) {
        self.windows
            .retain(|id, _| live.contains(id) && (!owned.contains(id) || self.used.contains(id)));
        self.used.clear();
    }
    pub fn element(
        &mut self,
        renderer: &mut GlesRenderer,
        id: WindowId,
        bounds: Rectangle<i32, Logical>,
        style: &Halo,
        surfaces: Vec<WaylandSurfaceRenderElement<GlesRenderer>>,
    ) -> anyhow::Result<Vec<ElementType>> {
        self.used.insert(id);
        let signature: Signature = surfaces
            .iter()
            .map(|s| (s.id().clone(), s.current_commit(), s.geometry(1.0.into())))
            .collect();
        let changed = self
            .windows
            .get(&id)
            .is_none_or(|c| c.signature != signature || c.size != bounds.size || c.style != *style);
        let padding = style.width as i32;
        let expanded =
            Size::<i32, Logical>::from((bounds.size.w + 2 * padding, bounds.size.h + 2 * padding));
        let target_size: Size<i32, Physical> = expanded.to_physical_precise_round(0.25);
        if changed {
            self.offscreen_rendered = true;
            // Fixed quarter density bounds work independently of display scale.
            // The source excludes desktop pixels, popups and decorations.
            let source_size: Size<i32, Physical> = bounds.size.to_physical_precise_round(0.25);
            let source_size = Size::from((source_size.w.max(1), source_size.h.max(1)));
            let mut source: GlesTexture =
                renderer.create_buffer(Fourcc::Abgr8888, (source_size.w, source_size.h).into())?;
            {
                let mut framebuffer = renderer.bind(&mut source)?;
                OutputDamageTracker::new(source_size, 0.25, Transform::Flipped180).render_output(
                    renderer,
                    &mut framebuffer,
                    0,
                    &surfaces,
                    [0.0; 4],
                )?;
            }
            let mut target: GlesTexture =
                renderer.create_buffer(Fourcc::Abgr8888, (target_size.w, target_size.h).into())?;
            {
                let mut framebuffer = renderer.bind(&mut target)?;
                let mut frame =
                    renderer.render(&mut framebuffer, target_size, Transform::Flipped180)?;
                let rect = Rectangle::from_size(target_size);
                frame.clear([0.0; 4].into(), &[rect])?;
                frame.override_default_tex_program(
                    self.program.clone(),
                    vec![
                        Uniform::new(
                            "blur_step",
                            (
                                padding as f32 / bounds.size.w as f32 / 2.0,
                                padding as f32 / bounds.size.h as f32 / 2.0,
                            ),
                        ),
                        Uniform::new(
                            "window_ratio",
                            (
                                bounds.size.w as f32 / expanded.w as f32,
                                bounds.size.h as f32 / expanded.h as f32,
                            ),
                        ),
                    ],
                );
                let result = Frame::render_texture_from_to(
                    &mut frame,
                    &source,
                    Rectangle::from_size(source.size()).to_f64(),
                    rect,
                    &[rect],
                    &[],
                    Transform::Normal,
                    style.opacity,
                );
                frame.clear_tex_program_override();
                result?;
                // All sampling follows on the same GL command stream.
                let _ = frame.finish()?;
            }
            self.windows.insert(
                id,
                Cached {
                    signature,
                    size: bounds.size,
                    style: style.clone(),
                    // Separate identities let each edge track its own damage.
                    buffers: std::array::from_fn(|_| {
                        TextureBuffer::from_texture(
                            renderer,
                            target.clone(),
                            1,
                            Transform::Normal,
                            None,
                        )
                    }),
                },
            );
        }
        let (x, y, w, h, p) = (
            bounds.loc.x,
            bounds.loc.y,
            bounds.size.w,
            bounds.size.h,
            padding,
        );
        // Exclude the entire client interior, including translucent windows.
        Ok([
            Rectangle::new((x - p, y - p).into(), (w + 2 * p, p).into()),
            Rectangle::new((x - p, y + h).into(), (w + 2 * p, p).into()),
            Rectangle::new((x - p, y).into(), (p, h).into()),
            Rectangle::new((x + w, y).into(), (p, h).into()),
        ]
        .into_iter()
        .enumerate()
        .filter_map(|(index, band)| {
            let element = TextureRenderElement::from_texture_buffer(
                ((x - p) as f64, (y - p) as f64),
                &self.windows[&id].buffers[index],
                None,
                Some(Rectangle::from_size(target_size.to_logical(1).to_f64())),
                Some(expanded),
                Kind::Unspecified,
            );
            CropRenderElement::from_element(element, 1.0, band)
        })
        .collect())
    }
}
