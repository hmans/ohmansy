//! Shared lighting uniforms for solid and frosted frames.
use crate::preferences::Frame;
use smithay::backend::renderer::gles::{Uniform, UniformName, UniformType};

pub fn names() -> [UniformName<'static>; 3] {
    [
        UniformName::new("bevel_widths", UniformType::_2f),
        UniformName::new("bevel_strength", UniformType::_2f),
        UniformName::new("light_direction", UniformType::_2f),
    ]
}
pub fn uniforms(frame: &Frame) -> Vec<Uniform<'static>> {
    let bevel = &frame.bevel;
    vec![
        Uniform::new(
            "bevel_widths",
            if bevel.enabled {
                (bevel.width, bevel.inner_width)
            } else {
                (0.0, 0.0)
            },
        ),
        Uniform::new("bevel_strength", (bevel.highlight, bevel.shadow)),
        Uniform::new("light_direction", bevel.light_direction),
    ]
}
