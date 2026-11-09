//! One screen-space light for desktop materials. Positive y points down.
use serde::{Deserialize, Serialize};

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(default, deny_unknown_fields)]
pub struct Theme {
    pub transition_duration_ms: u32,
    pub color_intensity: f32,
    pub lighting: Lighting,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub palette: Option<Palette>,
}
impl Default for Theme {
    fn default() -> Self {
        Self {
            transition_duration_ms: 1000,
            color_intensity: 0.65,
            lighting: Lighting::default(),
            palette: None,
        }
    }
}

#[derive(Default)]
pub struct TintTransition(Option<Tint>);
struct Tint {
    from: [f32; 3],
    target: [f32; 3],
    started: f64,
    duration: f64,
}
impl Tint {
    fn value(&self, now: f64) -> [f32; 3] {
        let t = if self.duration == 0.0 {
            1.0
        } else {
            ((now - self.started) / self.duration).clamp(0.0, 1.0)
        };
        let t = crate::preferences::FocusEasing::EaseInOut.sample(t) as f32;
        std::array::from_fn(|i| self.from[i] + (self.target[i] - self.from[i]) * t)
    }
}
impl TintTransition {
    pub fn value(&self, now: f64) -> Option<[f32; 3]> {
        self.0.as_ref().map(|t| t.value(now))
    }
    pub fn update(&mut self, target: [f32; 3], now: f64, duration: f64) -> bool {
        let t = self.0.get_or_insert(Tint {
            from: target,
            target,
            started: now,
            duration,
        });
        let mut changed = false;
        if t.target != target || t.duration != duration {
            *t = Tint {
                from: t.value(now),
                target,
                started: now,
                duration,
            };
            changed = true;
        }
        if t.from != t.target {
            changed = true;
            if now >= t.started + t.duration {
                t.from = t.target;
            }
        }
        changed
    }
}

impl crate::Smallvil {
    pub fn update_theme_tint(&mut self) {
        let frame = &self.output_settings.decorations.frame;
        let color = self
            .output_settings
            .materials
            .get("active_frame")
            .copied()
            .unwrap_or(frame.active_color[..3].try_into().unwrap());
        let neutral = self
            .output_settings
            .materials
            .get("inactive_frame")
            .copied()
            .unwrap_or(frame.inactive_color[..3].try_into().unwrap());
        let duration = if self.output_settings.animations.enabled {
            self.output_settings
                .effective_theme()
                .transition_duration_ms as f64
                / 1000.0
        } else {
            0.0
        };
        self.needs_redraw |=
            self.theme_tint
                .update(color, self.start_time.elapsed().as_secs_f64(), duration);
        self.needs_redraw |= self.theme_neutral_tint.update(
            neutral,
            self.start_time.elapsed().as_secs_f64(),
            duration,
        );
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn roles_are_independent_and_all_presets_produce_valid_materials() {
        let base = Theme::default().materials();
        let mut theme = Theme {
            palette: Some(Palette::default()),
            ..Theme::default()
        };
        theme.palette.as_mut().unwrap().accent = [1.0, 0.0, 0.0];
        let accent = theme.materials();
        assert_ne!(base["active_frame"], accent["active_frame"]);
        assert_eq!(base["background_top"], accent["background_top"]);
        assert_eq!(base["inactive_frame"], accent["inactive_frame"]);
        assert_eq!(base["ribbon_companion"], accent["ribbon_companion"]);
        theme.palette.as_mut().unwrap().atmosphere = [0.0, 1.0, 0.0];
        let atmosphere = theme.materials();
        assert_ne!(accent["background_top"], atmosphere["background_top"]);
        assert_ne!(accent["inactive_frame"], atmosphere["inactive_frame"]);
        assert_eq!(accent["active_frame"], atmosphere["active_frame"]);
        theme.palette.as_mut().unwrap().companion = [0.0, 0.0, 1.0];
        let companion = theme.materials();
        assert_ne!(
            atmosphere["ribbon_companion"],
            companion["ribbon_companion"]
        );
        assert_eq!(atmosphere["active_frame"], companion["active_frame"]);
        assert_eq!(atmosphere["background_top"], companion["background_top"]);
        for preset in presets().as_array().unwrap() {
            let palette: Palette = serde_json::from_value(preset["palette"].clone()).unwrap();
            palette.validate().unwrap();
            for color_intensity in [0.0, 0.65, 1.0] {
                let materials = Theme {
                    palette: Some(palette.clone()),
                    color_intensity,
                    ..Theme::default()
                }
                .materials();
                assert!(materials
                    .values()
                    .flatten()
                    .all(|v| v.is_finite() && (0.0..=1.0).contains(v)));
            }
        }
    }
    #[test]
    fn roles_migrate_without_changing_their_meaning() {
        let legacy: Palette = serde_json::from_value(serde_json::json!({
            "primary":[1.0,0.0,0.0], "secondary":[0.0,1.0,0.0], "accent":[0.0,0.0,1.0]
        }))
        .unwrap();
        assert_eq!(legacy.atmosphere, [0.0, 1.0, 0.0]);
        assert_eq!(legacy.accent, [1.0, 0.0, 0.0]);
        assert_eq!(legacy.companion, [0.0, 0.0, 1.0]);
        let saved = serde_json::to_value(&legacy).unwrap();
        assert!(saved.get("primary").is_none());
        assert_eq!(serde_json::from_value::<Palette>(saved).unwrap(), legacy);
        assert!(serde_json::from_value::<Palette>(
            serde_json::json!({"primary":[1,0,0],"atmosphere":[0,1,0]})
        )
        .is_err());
    }
    #[test]
    fn perceptual_tones_are_neutral_or_preserve_seed_hue_in_gamut() {
        let gray = tone([0.5; 3], 0.5, 0.2);
        assert!(gray.iter().all(|v| (*v - 0.388573).abs() < 0.0001));
        for seed in [
            [1.0, 0.0, 0.0],
            [0.0, 1.0, 0.0],
            [0.0, 0.0, 1.0],
            [1.0, 1.0, 0.0],
        ] {
            for lightness in [0.18, 0.5, 0.95] {
                let result = tone(seed, lightness, 0.2);
                assert!(result
                    .iter()
                    .all(|v| v.is_finite() && (0.0..=1.0).contains(v)));
                let muted = tone(seed, lightness, 0.02);
                let spread = |rgb: [f32; 3]| {
                    rgb.iter().copied().fold(f32::NEG_INFINITY, f32::max)
                        - rgb.iter().copied().fold(f32::INFINITY, f32::min)
                };
                assert!(spread(result) >= spread(muted));
                let dominant = seed.iter().position(|v| *v == 1.0).unwrap();
                if seed.iter().sum::<f32>() == 1.0 {
                    assert!(
                        (result[dominant]
                            - result.iter().copied().fold(f32::NEG_INFINITY, f32::max))
                        .abs()
                            < 0.0001
                    );
                }
            }
        }
        for invalid in [
            "color_intensity=nan",
            "color_intensity=-0.1",
            "color_intensity=1.1",
        ] {
            assert!(crate::output_config::Settings::parse(&format!("[theme]\n{invalid}")).is_err());
        }
    }
    #[test]
    fn tint_interpolates_retargets_and_stops() {
        let mut t = TintTransition::default();
        assert!(!t.update([0.0; 3], 0.0, 1.0));
        assert!(t.update([1.0; 3], 0.0, 1.0));
        assert_eq!(t.value(0.5), Some([0.5; 3]));
        assert!(t.update([0.0; 3], 0.5, 1.0));
        assert_eq!(t.value(0.5), Some([0.5; 3]));
        assert_eq!(t.value(1.0), Some([0.25; 3]));
        assert!(t.update([0.0; 3], 1.5, 1.0));
        assert!(!t.update([0.0; 3], 1.6, 1.0));
        assert!(t.update([1.0; 3], 1.6, 0.0));
        assert_eq!(t.value(1.6), Some([1.0; 3]));
        assert!(!t.update([1.0; 3], 1.7, 0.0));
    }
}

#[derive(Clone, Debug, PartialEq, Serialize)]
pub struct Palette {
    pub atmosphere: [f32; 3],
    pub accent: [f32; 3],
    pub companion: [f32; 3],
}
impl Default for Palette {
    fn default() -> Self {
        Self {
            atmosphere: [69.0 / 255.0, 85.0 / 255.0, 108.0 / 255.0],
            accent: [166.0 / 255.0, 132.0 / 255.0, 1.0],
            companion: [1.0, 210.0 / 255.0, 48.0 / 255.0],
        }
    }
}
impl Palette {
    pub fn validate(&self) -> Result<(), String> {
        if self
            .atmosphere
            .iter()
            .chain(&self.accent)
            .chain(&self.companion)
            .any(|v| !v.is_finite() || !(0.0..=1.0).contains(v))
        {
            return Err("Theme palette colors must be RGB values from 0 to 1".into());
        }
        Ok(())
    }
}

// Old palettes used primary/secondary/accent. Keep their visual roles when
// loading, then save the explicit role names. Reject ambiguous mixed formats.
impl<'de> Deserialize<'de> for Palette {
    fn deserialize<D: serde::Deserializer<'de>>(deserializer: D) -> Result<Self, D::Error> {
        #[derive(Default, Deserialize)]
        #[serde(default, deny_unknown_fields)]
        struct Input {
            atmosphere: Option<[f32; 3]>,
            accent: Option<[f32; 3]>,
            companion: Option<[f32; 3]>,
            primary: Option<[f32; 3]>,
            secondary: Option<[f32; 3]>,
        }
        let i = Input::deserialize(deserializer)?;
        let defaults = Palette::default();
        if i.primary.is_some() || i.secondary.is_some() {
            if i.atmosphere.is_some() || i.companion.is_some() {
                return Err(serde::de::Error::custom(
                    "Use atmosphere/accent/companion or legacy primary/secondary/accent, not both",
                ));
            }
            Ok(Self {
                atmosphere: i.secondary.unwrap_or(defaults.atmosphere),
                accent: i.primary.unwrap_or(defaults.accent),
                companion: i.accent.unwrap_or(defaults.companion),
            })
        } else {
            Ok(Self {
                atmosphere: i.atmosphere.unwrap_or(defaults.atmosphere),
                accent: i.accent.unwrap_or(defaults.accent),
                companion: i.companion.unwrap_or(defaults.companion),
            })
        }
    }
}

pub type Materials = std::collections::BTreeMap<String, [f32; 3]>;
pub fn presets() -> &'static serde_json::Value {
    static PRESETS: std::sync::OnceLock<serde_json::Value> = std::sync::OnceLock::new();
    PRESETS.get_or_init(|| {
        // Official Tailwind CSS v4.3.0 theme.css, OKLCH converted to clipped
        // 8-bit sRGB. https://github.com/tailwindlabs/tailwindcss/blob/v4.3.0/packages/tailwindcss/theme.css
        // Each row: atmosphere / accent / companion. Previews use the same
        // perceptual material tones as frames and wallpaper, not raw seed hues.
        let rgb = |hex: u32| [((hex >> 16) & 255) as f32/255.0, ((hex >> 8) & 255) as f32/255.0, (hex & 255) as f32/255.0];
        let presets: Vec<_> = [
            ("Twilight", 0x45556c, 0xa684ff, 0xffd230), // slate-600 / violet-400 / amber-300
            ("Lagoon", 0x009689, 0x00b8db, 0xff8904), // teal-600 / cyan-500 / orange-400
            ("Ember", 0xff8904, 0xff8904, 0x00bcff), // orange-400 / orange-400 / sky-400
            ("Moss", 0x009689, 0x00d492, 0xff637e), // teal-600 / emerald-400 / rose-400
            ("Rose", 0xc4b4ff, 0xff2056, 0xb8e6fe), // violet-300 / rose-500 / sky-200
            ("Slate", 0x45556c, 0x90a1b9, 0xffd230), // slate-600 / slate-400 / amber-300
        ].into_iter().map(|(name, atmosphere, accent, companion)| {
            let palette = Palette { atmosphere: rgb(atmosphere), accent: rgb(accent), companion: rgb(companion) };
            let materials = Theme { palette: Some(palette.clone()), ..Theme::default() }.materials();
            serde_json::json!({"name":name,"palette":palette,"preview":[materials["inactive_frame"],materials["ribbon_accent"],materials["ribbon_companion"]]})
        }).collect();
        serde_json::json!(presets)
    })
}
impl Theme {
    pub fn materials(&self) -> Materials {
        let p = self.palette.clone().unwrap_or_default();
        let i = self.color_intensity;
        [
            ("active_frame", tone(p.accent, 0.50, 0.055 + 0.13 * i)),
            (
                "inactive_frame",
                tone(p.atmosphere, 0.29, 0.012 + 0.028 * i),
            ),
            ("surface", tone(p.atmosphere, 0.26, 0.015 + 0.035 * i)),
            ("text", tone(p.atmosphere, 0.96, 0.008)),
            ("muted_text", tone(p.atmosphere, 0.76, 0.02)),
            (
                "ribbon_atmosphere",
                tone(p.atmosphere, 0.48, 0.025 + 0.035 * i),
            ),
            ("ribbon_accent", tone(p.accent, 0.68, 0.08 + 0.15 * i)),
            ("ribbon_companion", tone(p.companion, 0.62, 0.06 + 0.14 * i)),
            (
                "ribbon_atmosphere_light",
                tone(p.atmosphere, 0.72, 0.02 + 0.026 * i),
            ),
            ("ribbon_accent_light", tone(p.accent, 0.78, 0.06 + 0.11 * i)),
            (
                "ribbon_companion_light",
                tone(p.companion, 0.74, 0.045 + 0.10 * i),
            ),
            (
                "background_top",
                tone(p.atmosphere, 0.18, 0.008 + 0.018 * i),
            ),
            (
                "background_bottom",
                tone(p.atmosphere, 0.25, 0.012 + 0.025 * i),
            ),
            (
                "background_top_light",
                tone(p.atmosphere, 0.95, 0.005 + 0.012 * i),
            ),
            (
                "background_bottom_light",
                tone(p.atmosphere, 0.88, 0.01 + 0.022 * i),
            ),
            ("sheen", tone(p.atmosphere, 0.96, 0.01)),
        ]
        .into_iter()
        .map(|(k, v)| (k.into(), v))
        .collect()
    }
}

// OKLab tones preserve a seed's hue at a chosen perceptual lightness. Reduce
// chroma into the sRGB gamut instead of clipping channels and shifting hue.
fn tone(rgb: [f32; 3], lightness: f32, chroma_limit: f32) -> [f32; 3] {
    let linear = rgb.map(|v| {
        if v <= 0.04045 {
            v / 12.92
        } else {
            ((v + 0.055) / 1.055).powf(2.4)
        }
    });
    let [r, g, b] = linear;
    let l = (0.41222146 * r + 0.53633255 * g + 0.051445995 * b).cbrt();
    let m = (0.2119035 * r + 0.6806995 * g + 0.10739696 * b).cbrt();
    let s = (0.08830246 * r + 0.28171885 * g + 0.6299787 * b).cbrt();
    let a = 1.9779985 * l - 2.4285922 * m + 0.4505937 * s;
    let b = 0.025904037 * l + 0.78277177 * m - 0.80867577 * s;
    let chroma = a.hypot(b);
    let scale = (chroma_limit / chroma.max(0.000001)).min(1.0);
    let (a, b) = (a * scale, b * scale);
    let convert = |scale: f32| {
        let l = (lightness + 0.39633778 * a * scale + 0.21580376 * b * scale).powi(3);
        let m = (lightness - 0.105561346 * a * scale - 0.06385417 * b * scale).powi(3);
        let s = (lightness - 0.08948418 * a * scale - 1.2914855 * b * scale).powi(3);
        [
            4.0767417 * l - 3.3077116 * m + 0.23096994 * s,
            -1.268438 * l + 2.6097574 * m - 0.3413194 * s,
            -0.0041960863 * l - 0.7034186 * m + 1.7076147 * s,
        ]
    };
    let mut low = 0.0;
    let mut high = 1.0;
    for _ in 0..16 {
        let middle = (low + high) * 0.5;
        if convert(middle).iter().all(|v| (0.0..=1.0).contains(v)) {
            low = middle;
        } else {
            high = middle;
        }
    }
    convert(low).map(|v| {
        if v <= 0.0031308 {
            v * 12.92
        } else {
            1.055 * v.powf(1.0 / 2.4) - 0.055
        }
    })
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
