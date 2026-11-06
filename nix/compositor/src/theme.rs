//! One screen-space light for desktop materials. Positive y points down.
use serde::{Deserialize, Serialize};

#[derive(Clone, Debug, Default, PartialEq, Serialize, Deserialize)]
#[serde(default, deny_unknown_fields)]
pub struct Theme {
    pub lighting: Lighting,
}
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(default, deny_unknown_fields)]
pub struct Lighting {
    pub direction: [f32; 2],
    pub strength: f32,
    pub highlight_color: [f32; 3],
    pub shadow_color: [f32; 3],
}
impl Default for Lighting {
    fn default() -> Self {
        Self {
            direction: [-std::f32::consts::FRAC_1_SQRT_2; 2],
            strength: 1.0,
            highlight_color: [1.0; 3],
            shadow_color: [0.0; 3],
        }
    }
}
impl Lighting {
    pub fn validate(&self) -> Result<(), String> {
        if !self.strength.is_finite()
            || !(0.0..=3.0).contains(&self.strength)
            || self.direction.iter().any(|v| !v.is_finite())
            || self.direction.iter().map(|v| v * v).sum::<f32>() > 1.00001
            || self
                .highlight_color
                .iter()
                .chain(&self.shadow_color)
                .any(|v| !v.is_finite() || !(0.0..=1.0).contains(v))
        {
            return Err(
                "Lighting needs a direction inside the unit disk, strength 0–3 and RGB colors 0–1"
                    .into(),
            );
        }
        Ok(())
    }
}
