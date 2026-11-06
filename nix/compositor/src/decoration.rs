//! Window masks, shadows and frames shared by native and nested rendering.
use crate::{layout::WindowId, preferences::Decorations};
use smithay::{
    backend::renderer::{
        element::{surface::WaylandSurfaceRenderElement, Element, Id, Kind, RenderElement},
        gles::{
            element::PixelShaderElement, GlesError, GlesFrame, GlesPixelProgram, GlesRenderer,
            GlesTexProgram, Uniform, UniformName, UniformType,
        },
        utils::{CommitCounter, DamageSet, OpaqueRegions},
    },
    utils::{Buffer, Logical, Physical, Point, Rectangle, Scale, Transform},
};
use std::collections::{HashMap, HashSet};

type MaskKey = (
    i32,
    i32,
    i32,
    i32,
    u32,
    u64,
    u32,
    u32,
    [u32; 3],
    (i32, i32, i32, i32, u32),
);
struct MaskId {
    window: WindowId,
    key: MaskKey,
    id: Id,
}
struct CachedBands {
    style: (Decorations, u64, i32, i32),
    elements: Vec<PixelShaderElement>,
}
pub struct Renderer {
    pub restore_draw_buffer: bool,
    pub titles: crate::frame_title::Renderer,
    pub frost: crate::frost::Renderer,
    rounded: GlesTexProgram,
    border: GlesPixelProgram,
    shadow: GlesPixelProgram,
    masks: HashMap<Id, MaskId>,
    frames: HashMap<WindowId, CachedBands>,
    shadows: HashMap<WindowId, CachedBands>,
    used: HashSet<Id>,
}
impl Renderer {
    pub fn new(renderer: &mut GlesRenderer) -> anyhow::Result<Self> {
        let sources = crate::shader_reload::Sources::configured()?;
        Ok(Self {
            restore_draw_buffer: false,
            titles: crate::frame_title::Renderer::default(),
            frost: crate::frost::Renderer::new(renderer, &sources.frost, &sources.coverage)?,
            rounded: renderer.compile_custom_texture_shader(
                sources.rounded.replace("//_COVERAGE_", &sources.coverage),
                &[
                    UniformName::new("draw_origin", UniformType::_2f),
                    UniformName::new("mask_rect", UniformType::_4f),
                    UniformName::new("radius", UniformType::_1f),
                    UniformName::new("outer_rect", UniformType::_4f),
                    UniformName::new("outer_radius", UniformType::_1f),
                    UniformName::new("saturation", UniformType::_1f),
                    UniformName::new("fog", UniformType::_1f),
                    UniformName::new("fog_color", UniformType::_3f),
                ],
            )?,
            border: renderer.compile_custom_pixel_shader(
                sources.frame.replace("//_COVERAGE_", &sources.coverage),
                &[
                    UniformName::new("radius", UniformType::_1f),
                    UniformName::new("inner_radius", UniformType::_1f),
                    UniformName::new("thickness", UniformType::_1f),
                    UniformName::new("titlebar_height", UniformType::_1f),
                    UniformName::new("feather", UniformType::_1f),
                    UniformName::new("frame_color", UniformType::_4f),
                    UniformName::new("full_size", UniformType::_2f),
                    UniformName::new("piece_offset", UniformType::_2f),
                ],
            )?,
            shadow: renderer.compile_custom_pixel_shader(
                sources.shadow,
                &[
                    UniformName::new("radius", UniformType::_1f),
                    UniformName::new("softness", UniformType::_1f),
                    UniformName::new("spread", UniformType::_1f),
                    UniformName::new("offset", UniformType::_2f),
                    UniformName::new("shadow_color", UniformType::_4f),
                    UniformName::new("window_size", UniformType::_2f),
                    UniformName::new("piece_offset", UniformType::_2f),
                    UniformName::new("feather", UniformType::_1f),
                ],
            )?,
            masks: HashMap::new(),
            frames: HashMap::new(),
            shadows: HashMap::new(),
            used: HashSet::new(),
        })
    }
    pub fn begin_output(&mut self) {
        self.used.clear();
    }
    pub fn finish_output(&mut self, live: &HashSet<WindowId>, owned: &HashSet<WindowId>) {
        self.titles.retain(live);
        self.frost.retain(live);
        self.masks.retain(|id, m| {
            live.contains(&m.window) && (!owned.contains(&m.window) || self.used.contains(id))
        });
        self.frames.retain(|id, _| live.contains(id));
        self.shadows.retain(|id, _| live.contains(id));
    }
    #[allow(clippy::too_many_arguments)]
    pub fn rounded(
        &mut self,
        window: WindowId,
        inner: WaylandSurfaceRenderElement<GlesRenderer>,
        bounds: Rectangle<i32, Logical>,
        radius: u32,
        outer: Option<(Rectangle<i32, Logical>, u32)>,
        scale: f64,
        canvas: Point<i32, Physical>,
        amount: f32,
        inactive: &crate::preferences::Inactive,
    ) -> RoundedSurface {
        let geometry = inner.geometry(1.0.into());
        let (outer_bounds, outer_radius) = outer.unwrap_or((bounds, radius));
        let saturation = 1.0 + (inactive.saturation - 1.0) * amount;
        let fog = inactive.fog * amount;
        let key = (
            bounds.loc.x - geometry.loc.x,
            bounds.loc.y - geometry.loc.y,
            bounds.size.w,
            bounds.size.h,
            radius,
            scale.to_bits(),
            saturation.to_bits(),
            fog.to_bits(),
            inactive.fog_color.map(f32::to_bits),
            (
                outer_bounds.loc.x - geometry.loc.x,
                outer_bounds.loc.y - geometry.loc.y,
                outer_bounds.size.w,
                outer_bounds.size.h,
                outer_radius,
            ),
        );
        self.used.insert(inner.id().clone());
        let cache = self
            .masks
            .entry(inner.id().clone())
            .or_insert_with(|| MaskId {
                window,
                key,
                id: Id::new(),
            });
        if cache.key != key {
            cache.key = key;
            cache.id = Id::new();
        }
        let mut physical = bounds.to_physical_precise_round(scale);
        physical.loc += canvas;
        let mut outer_physical = outer_bounds.to_physical_precise_round(scale);
        outer_physical.loc += canvas;
        RoundedSurface {
            inner,
            id: cache.id.clone(),
            program: self.rounded.clone(),
            bounds,
            physical,
            radius: radius as f32 * scale as f32,
            logical_radius: radius,
            outer_bounds,
            outer_physical,
            outer_radius: outer_radius as f32 * scale as f32,
            logical_outer_radius: outer_radius,
            saturation,
            fog,
            fog_color: inactive.fog_color,
        }
    }
    pub fn shadow(
        &mut self,
        id: WindowId,
        bounds: Rectangle<i32, Logical>,
        style: &Decorations,
        scale: f64,
    ) -> Vec<PixelShaderElement> {
        let shadow = &style.shadow;
        let padding = (shadow.softness * 3 + shadow.spread) as i32
            + shadow.offset[0].abs().max(shadow.offset[1].abs())
            + 1;
        let radius = (style.outer_radius() as i32).min(bounds.size.w.min(bounds.size.h) / 2);
        let (w, h) = (bounds.size.w, bounds.size.h);
        // The interior is deliberately absent, including for translucent clients.
        // Only rounded corners and the bands outside the window need shading.
        let pieces = [
            Rectangle::new(
                (-padding, -padding).into(),
                (w + 2 * padding, padding + radius).into(),
            ),
            Rectangle::new(
                (-padding, h - radius).into(),
                (w + 2 * padding, padding + radius).into(),
            ),
            Rectangle::new((-padding, radius).into(), (padding, h - 2 * radius).into()),
            Rectangle::new((w, radius).into(), (padding, h - 2 * radius).into()),
        ];
        let key = (style.clone(), scale.to_bits(), w, h);
        let cache = self.shadows.entry(id).or_insert_with(|| CachedBands {
            style: key.clone(),
            elements: pieces
                .iter()
                .map(|piece| {
                    PixelShaderElement::new(
                        self.shadow.clone(),
                        Rectangle::new(bounds.loc + piece.loc, piece.size),
                        None,
                        1.0,
                        shadow_uniforms(style, scale, bounds.size, piece.loc),
                        Kind::Unspecified,
                    )
                })
                .collect(),
        });
        for (element, piece) in cache.elements.iter_mut().zip(pieces) {
            element.resize(Rectangle::new(bounds.loc + piece.loc, piece.size), None);
            if cache.style != key {
                element.update_uniforms(shadow_uniforms(style, scale, bounds.size, piece.loc));
            }
        }
        cache.style = key;
        cache.elements.clone()
    }
    pub fn frame(
        &mut self,
        id: WindowId,
        bounds: Rectangle<i32, Logical>,
        style: &Decorations,
        scale: f64,
    ) -> Vec<PixelShaderElement> {
        let width = style.frame.width as i32;
        let area = bounds;
        // Leave the large transparent center out of the fragment shader.
        let band = (style
            .frame
            .outer_corner_radius
            .max(style.frame.inner_corner_radius) as i32
            + style.frame.titlebar_height as i32
            + 1)
        .min(area.size.h / 2);
        let pieces = [
            Rectangle::new((0, 0).into(), (area.size.w, band).into()),
            Rectangle::new((0, area.size.h - band).into(), (area.size.w, band).into()),
            Rectangle::new((0, band).into(), (width, area.size.h - 2 * band).into()),
            Rectangle::new(
                (area.size.w - width, band).into(),
                (width, area.size.h - 2 * band).into(),
            ),
        ];
        let key = (style.clone(), scale.to_bits(), area.size.w, area.size.h);
        let cache = self.frames.entry(id).or_insert_with(|| CachedBands {
            style: key.clone(),
            elements: pieces
                .iter()
                .map(|piece| {
                    PixelShaderElement::new(
                        self.border.clone(),
                        Rectangle::new(area.loc + piece.loc, piece.size),
                        None,
                        1.0,
                        frame_uniforms(style, scale, area.size, piece.loc),
                        Kind::Unspecified,
                    )
                })
                .collect(),
        });
        for (element, piece) in cache.elements.iter_mut().zip(pieces) {
            element.resize(Rectangle::new(area.loc + piece.loc, piece.size), None);
            if cache.style != key {
                element.update_uniforms(frame_uniforms(style, scale, area.size, piece.loc));
            }
        }
        cache.style = key;
        cache.elements.clone()
    }
}
fn shadow_uniforms(
    style: &Decorations,
    scale: f64,
    size: smithay::utils::Size<i32, Logical>,
    offset: Point<i32, Logical>,
) -> Vec<Uniform<'static>> {
    vec![
        Uniform::new("radius", style.outer_radius() as f32),
        Uniform::new("softness", style.shadow.softness as f32),
        Uniform::new("spread", style.shadow.spread as f32),
        Uniform::new(
            "offset",
            (style.shadow.offset[0] as f32, style.shadow.offset[1] as f32),
        ),
        Uniform::new("shadow_color", style.shadow.color),
        Uniform::new("window_size", (size.w as f32, size.h as f32)),
        Uniform::new("piece_offset", (offset.x as f32, offset.y as f32)),
        Uniform::new("feather", 0.5 / scale as f32),
    ]
}
fn frame_uniforms(
    style: &Decorations,
    scale: f64,
    size: smithay::utils::Size<i32, Logical>,
    offset: Point<i32, Logical>,
) -> Vec<Uniform<'static>> {
    vec![
        Uniform::new("radius", style.outer_radius() as f32),
        Uniform::new("inner_radius", style.frame.inner_corner_radius as f32),
        Uniform::new("thickness", style.frame.width as f32),
        Uniform::new("titlebar_height", style.frame.titlebar_height as f32),
        Uniform::new("feather", 0.5 / scale as f32),
        Uniform::new("frame_color", style.frame.active_color),
        Uniform::new("full_size", (size.w as f32, size.h as f32)),
        Uniform::new("piece_offset", (offset.x as f32, offset.y as f32)),
    ]
}

#[derive(Debug)]
pub struct RoundedSurface {
    inner: WaylandSurfaceRenderElement<GlesRenderer>,
    id: Id,
    program: GlesTexProgram,
    bounds: Rectangle<i32, Logical>,
    physical: Rectangle<i32, Physical>,
    radius: f32,
    logical_radius: u32,
    outer_bounds: Rectangle<i32, Logical>,
    outer_physical: Rectangle<i32, Physical>,
    outer_radius: f32,
    logical_outer_radius: u32,
    saturation: f32,
    fog: f32,
    fog_color: [f32; 3],
}
impl RoundedSurface {
    pub fn rescale(
        mut self,
        center: Point<i32, Physical>,
        factor: f64,
        scale: f64,
        canvas: Point<i32, Physical>,
    ) -> Self {
        // Match the render-element transform before output scaling and cropping.
        let bounds = self.bounds.to_physical_precise_round(1.0);
        let bounds = Rectangle::new(
            (bounds.loc - center)
                .to_f64()
                .upscale(factor)
                .to_i32_round()
                + center,
            (bounds.size.to_f64() * factor).to_i32_round(),
        );
        self.physical = Rectangle::new(bounds.loc.to_logical(1), bounds.size.to_logical(1))
            .to_physical_precise_round(scale);
        self.physical.loc += canvas;
        self.radius *= factor as f32;
        let outer = self.outer_bounds.to_physical_precise_round(1.0);
        let outer = Rectangle::new(
            (outer.loc - center).to_f64().upscale(factor).to_i32_round() + center,
            (outer.size.to_f64() * factor).to_i32_round(),
        );
        self.outer_physical = Rectangle::new(outer.loc.to_logical(1), outer.size.to_logical(1))
            .to_physical_precise_round(scale);
        self.outer_physical.loc += canvas;
        self.outer_radius *= factor as f32;
        self
    }
}
impl Element for RoundedSurface {
    fn id(&self) -> &Id {
        &self.id
    }
    fn current_commit(&self) -> CommitCounter {
        self.inner.current_commit()
    }
    fn src(&self) -> Rectangle<f64, Buffer> {
        self.inner.src()
    }
    fn transform(&self) -> Transform {
        self.inner.transform()
    }
    fn geometry(&self, scale: Scale<f64>) -> Rectangle<i32, Physical> {
        self.inner.geometry(scale)
    }
    fn damage_since(
        &self,
        scale: Scale<f64>,
        commit: Option<CommitCounter>,
    ) -> DamageSet<i32, Physical> {
        self.inner.damage_since(scale, commit)
    }
    fn opaque_regions(&self, scale: Scale<f64>) -> OpaqueRegions<i32, Physical> {
        // Only advertise the fully covered central cross; rounded pixels need blending.
        let mut regions = Vec::new();
        let bounds = self.bounds.to_physical_precise_round(scale);
        let radius =
            (self.logical_radius.max(self.logical_outer_radius) as f64 * scale.x).ceil() as i32 + 1;
        let safe = [
            Rectangle::new(
                bounds.loc + Point::from((radius, 0)),
                ((bounds.size.w - 2 * radius).max(0), bounds.size.h).into(),
            ),
            Rectangle::new(
                bounds.loc + Point::from((0, radius)),
                (bounds.size.w, (bounds.size.h - 2 * radius).max(0)).into(),
            ),
        ];
        let origin = self.inner.geometry(scale).loc;
        for region in self.inner.opaque_regions(scale) {
            let region = Rectangle::new(region.loc + origin, region.size);
            for safe in safe {
                if let Some(mut part) = region.intersection(safe) {
                    part.loc -= origin;
                    regions.push(part);
                }
            }
        }
        OpaqueRegions::from_slice(&regions)
    }
    fn alpha(&self) -> f32 {
        self.inner.alpha()
    }
    fn kind(&self) -> Kind {
        self.inner.kind()
    }
}
impl RenderElement<GlesRenderer> for RoundedSurface {
    fn draw(
        &self,
        frame: &mut GlesFrame<'_, '_>,
        src: Rectangle<f64, Buffer>,
        dst: Rectangle<i32, Physical>,
        damage: &[Rectangle<i32, Physical>],
        opaque: &[Rectangle<i32, Physical>],
    ) -> Result<(), GlesError> {
        frame.override_default_tex_program(
            self.program.clone(),
            vec![
                Uniform::new("draw_origin", (dst.loc.x as f32, dst.loc.y as f32)),
                Uniform::new(
                    "mask_rect",
                    (
                        self.physical.loc.x as f32,
                        self.physical.loc.y as f32,
                        self.physical.size.w as f32,
                        self.physical.size.h as f32,
                    ),
                ),
                Uniform::new("radius", self.radius),
                Uniform::new("outer_radius", self.outer_radius),
                Uniform::new(
                    "outer_rect",
                    (
                        self.outer_physical.loc.x as f32,
                        self.outer_physical.loc.y as f32,
                        self.outer_physical.size.w as f32,
                        self.outer_physical.size.h as f32,
                    ),
                ),
                Uniform::new("saturation", self.saturation),
                Uniform::new("fog", self.fog),
                Uniform::new("fog_color", self.fog_color),
            ],
        );
        let result = self.inner.draw(frame, src, dst, damage, opaque);
        frame.clear_tex_program_override();
        result
    }
}

pub fn contains(bounds: Rectangle<i32, Logical>, radius: u32, point: Point<f64, Logical>) -> bool {
    if !bounds.to_f64().contains(point) {
        return false;
    }
    let r = (radius as f64).min(bounds.size.w.min(bounds.size.h).max(0) as f64 / 2.0);
    let p = point - bounds.loc.to_f64();
    let x = p.x.clamp(r, bounds.size.w as f64 - r);
    let y = p.y.clamp(r, bounds.size.h as f64 - r);
    (p.x - x).powi(2) + (p.y - y).powi(2) <= r * r
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn rounded_hit_regions_match_edges_and_clamp_small_windows() {
        let bounds = Rectangle::new((100, 40).into(), (200, 100).into());
        assert!(!contains(bounds, 14, (100.5, 40.5).into()));
        assert!(contains(bounds, 14, (114.0, 40.5).into()));
        assert!(contains(bounds, 14, (104.5, 44.5).into()));
        assert!(!contains(bounds, 14, (299.5, 139.5).into()));
        assert!(contains(bounds, 0, (100.5, 40.5).into()));
        assert!(!contains(bounds, 0, (300.0, 140.0).into()));
        assert!(contains(
            Rectangle::from_size((10, 10).into()),
            128,
            (5.0, 5.0).into()
        ));
    }
}
