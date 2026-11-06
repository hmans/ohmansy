//! Cached GPU backdrop snapshots. Build bottom-to-top so a frame never samples
//! its own client, captions, shadow or pixels from a previous display frame.
use crate::{layout::WindowId, preferences::Frame, scene::SceneElement};
use smithay::{
    backend::{
        allocator::Fourcc,
        renderer::{
            damage::OutputDamageTracker,
            element::{
                texture::TextureRenderElement,
                utils::{Relocate, RelocateRenderElement, RescaleRenderElement},
                Element, Id, Kind, RenderElement,
            },
            gles::{
                element::TextureShaderElement, GlesError, GlesFrame, GlesRenderer, GlesTexProgram,
                GlesTexture, Uniform, UniformName, UniformType,
            },
            utils::{CommitCounter, DamageSet, OpaqueRegions},
            Bind, Offscreen, Renderer as _,
        },
    },
    utils::{Buffer, Logical, Physical, Point, Rectangle, Scale, Size, Transform},
};
use std::collections::{HashMap, HashSet};

type Signature = (
    Id,
    CommitCounter,
    Rectangle<i32, Physical>,
    Rectangle<f64, Buffer>,
    u32,
);
#[derive(PartialEq)]
struct Key {
    scene: Vec<Signature>,
    bounds: Rectangle<i32, Logical>,
    canvas: Point<i32, Physical>,
    size: Size<i32, Physical>,
    scale: f64,
    visual_scale: f64,
    style: Frame,
}
struct Snapshot {
    key: Key,
    texture: GlesTexture,
    id: Id,
}
pub struct Renderer {
    program: GlesTexProgram,
    snapshots: HashMap<(String, WindowId), Snapshot>,
    pub offscreen_rendered: bool,
}
impl Renderer {
    pub fn new(
        renderer: &mut GlesRenderer,
        source: &str,
        coverage: &str,
    ) -> Result<Self, GlesError> {
        let program = renderer.compile_custom_texture_shader(
            source.replace("//_COVERAGE_", coverage),
            &[
                UniformName::new("source_rect", UniformType::_4f),
                UniformName::new("sample_bounds", UniformType::_4f),
                UniformName::new("texture_size", UniformType::_2f),
                UniformName::new("frame_size", UniformType::_2f),
                UniformName::new("radius", UniformType::_1f),
                UniformName::new("inner_radius", UniformType::_1f),
                UniformName::new("thickness", UniformType::_1f),
                UniformName::new("titlebar_height", UniformType::_1f),
                UniformName::new("blur_radius", UniformType::_1f),
                UniformName::new("opacity", UniformType::_1f),
                UniformName::new("noise_strength", UniformType::_1f),
                UniformName::new("frame_color", UniformType::_4f),
                UniformName::new("density", UniformType::_1f),
            ],
        )?;
        Ok(Self {
            program,
            snapshots: HashMap::new(),
            offscreen_rendered: false,
        })
    }
    pub fn retain(&mut self, live: &HashSet<WindowId>) {
        self.snapshots.retain(|(_, id), _| live.contains(id));
    }
    #[allow(clippy::too_many_arguments)]
    pub fn element(
        &mut self,
        renderer: &mut GlesRenderer,
        output: &str,
        id: WindowId,
        bounds: Rectangle<i32, Logical>,
        style: &Frame,
        scale: f64,
        visual_scale: f64,
        canvas: Point<i32, Physical>,
        size: Size<i32, Physical>,
        windows: &[SceneElement],
        background: &[SceneElement],
    ) -> anyhow::Result<ElementType> {
        let scene: Vec<_> = windows.iter().chain(background).collect();
        let key = Key {
            scene: scene
                .iter()
                .map(|e| {
                    (
                        e.id().clone(),
                        e.current_commit(),
                        e.geometry(scale.into()),
                        e.src(),
                        e.alpha().to_bits(),
                    )
                })
                .collect(),
            bounds,
            canvas,
            size,
            scale,
            visual_scale,
            style: style.clone(),
        };
        let cache_key = (output.to_owned(), id);
        if self
            .snapshots
            .get(&cache_key)
            .is_none_or(|snapshot| snapshot.key != key)
        {
            // Include the canvas offset used by the rounded-surface shaders in
            // nested multi-output rendering. Sample bounds exclude that padding.
            let target_size = (size.w + canvas.x, size.h + canvas.y);
            self.offscreen_rendered = true;
            let mut texture = renderer.create_buffer(Fourcc::Abgr8888, target_size.into())?;
            {
                let elements: Vec<_> = scene
                    .iter()
                    .map(|e| {
                        RelocateRenderElement::from_element(
                            RescaleRenderElement::from_element(*e, (0, 0).into(), scale),
                            canvas,
                            Relocate::Relative,
                        )
                    })
                    .collect();
                let mut target = renderer.bind(&mut texture)?;
                OutputDamageTracker::new(target_size, 1.0, Transform::Flipped180).render_output(
                    renderer,
                    &mut target,
                    0,
                    &elements,
                    [0.035, 0.035, 0.055, 1.0],
                )?;
            }
            self.snapshots.insert(
                cache_key.clone(),
                Snapshot {
                    key,
                    texture,
                    id: Id::new(),
                },
            );
        }
        let snapshot = &self.snapshots[&cache_key];
        let (tw, th) = ((size.w + canvas.x) as f32, (size.h + canvas.y) as f32);
        let center = bounds.loc.to_f64()
            + Point::from((bounds.size.w as f64 / 2.0, bounds.size.h as f64 / 2.0));
        let source = Rectangle::new(
            (center + (bounds.loc.to_f64() - center).upscale(visual_scale)).upscale(scale)
                + canvas.to_f64().to_logical(1.0),
            bounds.size.to_f64() * (scale * visual_scale),
        );
        let uniforms = vec![
            Uniform::new(
                "source_rect",
                (
                    source.loc.x as f32 / tw,
                    source.loc.y as f32 / th,
                    source.size.w as f32 / tw,
                    source.size.h as f32 / th,
                ),
            ),
            Uniform::new(
                "sample_bounds",
                (
                    (canvas.x as f32 + 0.5) / tw,
                    (canvas.y as f32 + 0.5) / th,
                    (canvas.x as f32 + size.w as f32 - 0.5) / tw,
                    (canvas.y as f32 + size.h as f32 - 0.5) / th,
                ),
            ),
            Uniform::new("texture_size", (tw, th)),
            Uniform::new("frame_size", (bounds.size.w as f32, bounds.size.h as f32)),
            Uniform::new("radius", style.outer_corner_radius as f32),
            Uniform::new("inner_radius", style.inner_corner_radius as f32),
            Uniform::new("thickness", style.width as f32),
            Uniform::new("titlebar_height", style.titlebar_height as f32),
            Uniform::new("blur_radius", style.glass.blur_radius as f32),
            Uniform::new("opacity", style.glass.opacity),
            Uniform::new("noise_strength", style.glass.noise),
            Uniform::new("frame_color", style.active_color),
            Uniform::new("density", scale as f32),
        ];
        let texture = TextureRenderElement::from_static_texture(
            snapshot.id.clone(),
            renderer.context_id(),
            bounds.loc.to_f64().to_physical(1.0),
            snapshot.texture.clone(),
            1,
            Transform::Normal,
            Some(1.0),
            Some(source),
            Some(bounds.size),
            Some(vec![]),
            Kind::Unspecified,
        );
        Ok(ElementType {
            inner: TextureShaderElement::new(texture, self.program.clone(), uniforms),
            id: snapshot.id.clone(),
        })
    }
}

#[derive(Debug)]
pub struct ElementType {
    inner: TextureShaderElement,
    id: Id,
}
impl Element for ElementType {
    fn id(&self) -> &Id {
        &self.id
    }
    fn current_commit(&self) -> CommitCounter {
        self.inner.current_commit()
    }
    fn src(&self) -> Rectangle<f64, Buffer> {
        self.inner.src()
    }
    fn geometry(&self, scale: Scale<f64>) -> Rectangle<i32, Physical> {
        self.inner.geometry(scale)
    }
    fn transform(&self) -> Transform {
        self.inner.transform()
    }
    fn damage_since(
        &self,
        scale: Scale<f64>,
        commit: Option<CommitCounter>,
    ) -> DamageSet<i32, Physical> {
        self.inner.damage_since(scale, commit)
    }
    fn opaque_regions(&self, _scale: Scale<f64>) -> OpaqueRegions<i32, Physical> {
        OpaqueRegions::default()
    }
}
impl RenderElement<GlesRenderer> for ElementType {
    fn draw(
        &self,
        frame: &mut GlesFrame<'_, '_>,
        src: Rectangle<f64, Buffer>,
        dst: Rectangle<i32, Physical>,
        damage: &[Rectangle<i32, Physical>],
        opaque: &[Rectangle<i32, Physical>],
    ) -> Result<(), GlesError> {
        self.inner.draw(frame, src, dst, damage, opaque)
    }
}
