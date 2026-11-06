//! Shared lighting uniforms for solid and frosted frames.
use crate::preferences::Frame;
use smithay::backend::renderer::gles::{Uniform, UniformName, UniformType};

pub fn names() -> [UniformName<'static>; 5] {
    [
        UniformName::new("bevel_widths", UniformType::_2f),
        UniformName::new("bevel_strength", UniformType::_2f),
        UniformName::new("light_direction", UniformType::_2f),
        UniformName::new("light_highlight", UniformType::_3f),
        UniformName::new("light_shadow", UniformType::_3f),
    ]
}
pub fn uniforms(frame: &Frame) -> Vec<Uniform<'static>> {
    let bevel = &frame.bevel;
    let mut light = frame.lighting.clone().unwrap_or_default();
    if frame.lighting.is_none() {
        let [x, y] = bevel.light_direction;
        let length = x.hypot(y);
        light.direction = [x / length, y / length];
    }
    vec![
        Uniform::new(
            "bevel_widths",
            if bevel.enabled {
                (bevel.width, bevel.inner_width)
            } else {
                (0.0, 0.0)
            },
        ),
        Uniform::new(
            "bevel_strength",
            (
                bevel.highlight * light.strength,
                bevel.shadow * light.strength,
            ),
        ),
        Uniform::new("light_direction", light.direction),
        Uniform::new("light_highlight", light.highlight_color),
        Uniform::new("light_shadow", light.shadow_color),
    ]
}
