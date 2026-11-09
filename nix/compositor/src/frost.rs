//! Shared scene-color sources and a separate transparency pass. The common
//! background source samples the wallpaper's imported GPU texture directly.
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
            Bind, Frame as _, Offscreen, Renderer as _, Texture as _,
        },
    },
    utils::{Buffer, Logical, Physical, Point, Rectangle, Scale, Size, Transform},
};
use std::collections::{HashMap, HashSet};

pub struct Layer {
    pub id: WindowId,
    pub bounds: Rectangle<i32, Logical>,
    pub elements: Vec<SceneElement>,
}
pub struct DirectSource {
    pub texture: GlesTexture,
    pub source: Rectangle<f64, Buffer>,
}
#[derive(Clone, Default, serde::Serialize)]
pub struct Stats {
    pub wallpaper_imports: u64,
    pub scene_captures: u64,
    pub blur_builds: u64,
    pub background_blur_builds: u64,
    pub scene_blur_builds: u64,
    pub filter_passes: u64,
    pub cache_hits: u64,
    pub sources: usize,
}
type SourceKey = (String, Vec<WindowId>);

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
    canvas: Point<i32, Physical>,
    size: Size<i32, Physical>,
    scale: f64,
}
#[derive(PartialEq)]
struct Appearance {
    bounds: Rectangle<i32, Logical>,
    visual_scale: f64,
    style: Frame,
}
struct Snapshot {
    key: Key,
    texture: GlesTexture,
    source: Rectangle<f64, Buffer>,
    blurred: HashMap<u32, GlesTexture>,
    appearance: HashMap<(WindowId, bool), (Appearance, Id)>,
}
pub struct Renderer {
    program: GlesTexProgram,
    blur_program: GlesTexProgram,
    snapshots: HashMap<SourceKey, Snapshot>,
    used: HashSet<SourceKey>,
    stats: Stats,
    pub offscreen_rendered: bool,
}
impl Renderer {
    pub fn new(
        renderer: &mut GlesRenderer,
        source: &str,
        coverage: &str,
        lighting: &str,
    ) -> Result<Self, GlesError> {
        let program = renderer.compile_custom_texture_shader(
            source
                .replace("//_COVERAGE_", coverage)
                .replace("//_LIGHTING_", lighting),
            &[
                UniformName::new("source_rect", UniformType::_4f),
                UniformName::new("sample_bounds", UniformType::_4f),
                UniformName::new("frame_size", UniformType::_2f),
                UniformName::new("radius", UniformType::_1f),
                UniformName::new("inner_radius", UniformType::_1f),
                UniformName::new("thickness", UniformType::_1f),
                UniformName::new("titlebar_height", UniformType::_1f),
                UniformName::new("opacity", UniformType::_1f),
                UniformName::new("noise_strength", UniformType::_1f),
                UniformName::new("frame_color", UniformType::_4f),
                UniformName::new("density", UniformType::_1f),
                UniformName::new("content_blur", UniformType::_1f),
            ]
            .into_iter()
            .chain(crate::frame_lighting::names())
            .collect::<Vec<_>>(),
        )?;
        let blur_program = renderer.compile_custom_texture_shader(
            include_str!("blur.frag"),
            &[
                UniformName::new("axis", UniformType::_2f),
                UniformName::new("pixel_size", UniformType::_2f),
                UniformName::new("reduction", UniformType::_1f),
                UniformName::new("sample_bounds", UniformType::_4f),
            ],
        )?;
        Ok(Self {
            program,
            blur_program,
            snapshots: HashMap::new(),
            used: HashSet::new(),
            stats: Stats::default(),
            offscreen_rendered: false,
        })
    }
    pub fn retain(&mut self, live: &HashSet<WindowId>) {
        self.snapshots
            .retain(|(_, ids), _| ids.iter().all(|id| live.contains(id)));
        for snapshot in self.snapshots.values_mut() {
            snapshot.appearance.retain(|(id, _), _| live.contains(id));
        }
    }
    pub fn begin_output(&mut self) {
        self.used.clear();
    }
    pub fn finish_output(&mut self, output: &str) {
        self.snapshots
            .retain(|key, _| key.0 != output || self.used.contains(key));
    }
    pub fn remove_output(&mut self, output: &str) {
        self.snapshots.retain(|key, _| key.0 != output);
    }
    pub fn stats(&self) -> Stats {
        Stats {
            sources: self.snapshots.len(),
            ..self.stats.clone()
        }
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
        windows: &[Layer],
        background: &[SceneElement],
        direct: Option<&DirectSource>,
        content: bool,
    ) -> anyhow::Result<ElementType> {
        // Terminals intentionally use the background, irrespective of other
        // app buffers. Frames only need an additional scene layer when an app
        // actually overlaps their footprint. Non-overlapping tiled windows all
        // share the background source, without capturing neighbouring apps.
        let lower: Vec<_> = windows
            .iter()
            .filter(|layer| !content && !layer.elements.is_empty() && layer.bounds.overlaps(bounds))
            .collect();
        let scene: Vec<_> = lower
            .iter()
            .flat_map(|layer| &layer.elements)
            .chain(background)
            .collect();
        let canvas = if lower.is_empty() {
            (0, 0).into()
        } else {
            canvas
        };
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
            canvas,
            size,
            scale,
        };
        let cache_key = (
            output.to_owned(),
            lower.iter().map(|layer| layer.id).collect(),
        );
        self.used.insert(cache_key.clone());
        if self
            .snapshots
            .get(&cache_key)
            .is_none_or(|snapshot| snapshot.key != key)
        {
            let (texture, source) = if let Some(direct) = direct.filter(|_| lower.is_empty()) {
                self.stats.wallpaper_imports += 1;
                (direct.texture.clone(), direct.source)
            } else {
                // A scene layer is needed only for overlapping windows or a
                // background assembled from multiple surfaces. Render it once
                // per shared stack, never once per transparency consumer.
                let target_size = (size.w + canvas.x, size.h + canvas.y);
                self.offscreen_rendered = true;
                self.stats.scene_captures += 1;
                let mut texture = renderer.create_buffer(Fourcc::Abgr8888, target_size.into())?;
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
                {
                    let mut target = renderer.bind(&mut texture)?;
                    // A sampled texture uses Normal orientation. The PNG
                    // readback path's Flipped180 would invert this source.
                    OutputDamageTracker::new(target_size, 1.0, Transform::Normal).render_output(
                        renderer,
                        &mut target,
                        0,
                        &elements,
                        [0.035, 0.035, 0.055, 1.0],
                    )?;
                }
                (
                    texture,
                    Rectangle::new(
                        (canvas.x as f64, canvas.y as f64).into(),
                        (size.w as f64, size.h as f64).into(),
                    ),
                )
            };
            self.snapshots.insert(
                cache_key.clone(),
                Snapshot {
                    key,
                    texture,
                    source,
                    blurred: HashMap::new(),
                    appearance: HashMap::new(),
                },
            );
        }
        let snapshot = self.snapshots.get_mut(&cache_key).unwrap();
        let radius = style.glass.blur_radius;
        if !snapshot.blurred.contains_key(&radius) {
            // At most the independently configured frame and content radii.
            if snapshot.blurred.len() >= 2 {
                snapshot.blurred.clear();
            }
            self.offscreen_rendered = true;
            self.stats.blur_builds += 1;
            if cache_key.1.is_empty() {
                self.stats.background_blur_builds += 1;
            } else {
                self.stats.scene_blur_builds += 1;
            }
            let reduction = if radius >= 16 {
                4
            } else if radius >= 8 {
                2
            } else {
                1
            };
            let reduced = (
                (size.w + reduction - 1) / reduction,
                (size.h + reduction - 1) / reduction,
            );
            let tw = snapshot.texture.size().w as f32;
            let th = snapshot.texture.size().h as f32;
            let src = snapshot.source;
            let bounds = (
                (src.loc.x as f32 + 0.5) / tw,
                (src.loc.y as f32 + 0.5) / th,
                ((src.loc.x + src.size.w) as f32 - 0.5) / tw,
                ((src.loc.y + src.size.h) as f32 - 0.5) / th,
            );
            let down = filter(
                renderer,
                &self.blur_program,
                &snapshot.texture,
                src,
                reduced,
                &[
                    Uniform::new("axis", (0.0f32, 0.0f32)),
                    Uniform::new(
                        "pixel_size",
                        (
                            src.size.w as f32 / size.w as f32 / tw,
                            src.size.h as f32 / size.h as f32 / th,
                        ),
                    ),
                    Uniform::new("reduction", reduction as f32),
                    Uniform::new("sample_bounds", bounds),
                ],
            )?;
            self.stats.filter_passes += 1;
            let filtered = if radius == 0 {
                down
            } else {
                let bounds = (
                    0.5 / reduced.0 as f32,
                    0.5 / reduced.1 as f32,
                    1.0 - 0.5 / reduced.0 as f32,
                    1.0 - 0.5 / reduced.1 as f32,
                );
                let uniforms = |axis| {
                    vec![
                        Uniform::new("axis", axis),
                        Uniform::new("pixel_size", (0.0f32, 0.0f32)),
                        Uniform::new("reduction", 1.0f32),
                        Uniform::new("sample_bounds", bounds),
                    ]
                };
                let distance = radius as f32 * scale as f32 / 16.0;
                let src = Rectangle::from_size(down.size()).to_f64();
                let horizontal = filter(
                    renderer,
                    &self.blur_program,
                    &down,
                    src,
                    reduced,
                    &uniforms((distance / size.w as f32, 0.0f32)),
                )?;
                let vertical = filter(
                    renderer,
                    &self.blur_program,
                    &horizontal,
                    src,
                    reduced,
                    &uniforms((0.0f32, distance / size.h as f32)),
                )?;
                self.stats.filter_passes += 2;
                vertical
            };
            snapshot.blurred.insert(radius, filtered);
        } else {
            self.stats.cache_hits += 1;
        }
        let blurred = &snapshot.blurred[&radius];
        let appearance = Appearance {
            bounds,
            visual_scale,
            style: style.clone(),
        };
        if snapshot
            .appearance
            .get(&(id, content))
            .is_none_or(|(old, _)| *old != appearance)
        {
            snapshot
                .appearance
                .insert((id, content), (appearance, Id::new()));
        }
        let id = &snapshot.appearance.get(&(id, content)).unwrap().1;
        let (tw, th) = (size.w as f32, size.h as f32);
        let center = bounds.loc.to_f64()
            + Point::from((bounds.size.w as f64 / 2.0, bounds.size.h as f64 / 2.0));
        let source = Rectangle::new(
            (center + (bounds.loc.to_f64() - center).upscale(visual_scale)).upscale(scale),
            bounds.size.to_f64() * (scale * visual_scale),
        );
        let mut uniforms = vec![
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
                    0.5 / blurred.size().w as f32,
                    0.5 / blurred.size().h as f32,
                    1.0 - 0.5 / blurred.size().w as f32,
                    1.0 - 0.5 / blurred.size().h as f32,
                ),
            ),
            Uniform::new("frame_size", (bounds.size.w as f32, bounds.size.h as f32)),
            Uniform::new("radius", style.outer_corner_radius as f32),
            Uniform::new("inner_radius", style.inner_corner_radius as f32),
            Uniform::new("thickness", style.width as f32),
            Uniform::new("titlebar_height", style.titlebar_height as f32),
            Uniform::new("opacity", style.glass.opacity),
            Uniform::new("noise_strength", style.glass.noise),
            Uniform::new("frame_color", style.active_color),
            Uniform::new("density", scale as f32),
            Uniform::new("content_blur", if content { 1.0f32 } else { 0.0 }),
        ];
        uniforms.extend(crate::frame_lighting::uniforms(style));
        let texture = TextureRenderElement::from_static_texture(
            id.clone(),
            renderer.context_id(),
            bounds.loc.to_f64().to_physical(1.0),
            blurred.clone(),
            1,
            Transform::Normal,
            Some(1.0),
            Some(Rectangle::new(
                (
                    source.loc.x * blurred.size().w as f64 / tw as f64,
                    source.loc.y * blurred.size().h as f64 / th as f64,
                )
                    .into(),
                (
                    source.size.w * blurred.size().w as f64 / tw as f64,
                    source.size.h * blurred.size().h as f64 / th as f64,
                )
                    .into(),
            )),
            Some(bounds.size),
            Some(vec![]),
            Kind::Unspecified,
        );
        Ok(ElementType {
            inner: TextureShaderElement::new(texture, self.program.clone(), uniforms),
            id: id.clone(),
        })
    }
}

fn filter(
    renderer: &mut GlesRenderer,
    program: &GlesTexProgram,
    source: &GlesTexture,
    source_rect: Rectangle<f64, Buffer>,
    size: (i32, i32),
    uniforms: &[Uniform<'_>],
) -> Result<GlesTexture, GlesError> {
    let mut texture = renderer.create_buffer(Fourcc::Abgr8888, size.into())?;
    {
        let mut target = renderer.bind(&mut texture)?;
        // These buffers will be sampled again, rather than read back as PNGs.
        let mut frame = renderer.render(&mut target, size.into(), Transform::Normal)?;
        let destination = Rectangle::from_size(size.into());
        frame.clear([0.0; 4].into(), &[destination])?;
        frame.render_texture_from_to(
            source,
            source_rect,
            destination,
            &[destination],
            &[],
            Transform::Normal,
            1.0,
            Some(program),
            uniforms,
        )?;
        let _ = frame.finish()?;
    }
    Ok(texture)
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
