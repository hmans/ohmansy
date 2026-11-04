//! User preferences shared by file validation, bindings and desktop policy.
use crate::{input::ShortcutModifier, Smallvil};
use serde::{Deserialize, Serialize};
use smithay::input::keyboard::{xkb, ModifiersState, XkbConfig};
use std::collections::BTreeMap;

pub fn is_default<T: Default + PartialEq>(value: &T) -> bool {
    value == &T::default()
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Width {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub proportion: Option<f64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub pixels: Option<i32>,
}
impl Default for Width {
    fn default() -> Self {
        Self {
            proportion: Some(0.62),
            pixels: None,
        }
    }
}
impl Width {
    pub fn validate(&self) -> Result<(), String> {
        match (self.proportion, self.pixels) {
            (Some(r), None) if r.is_finite() && r > 0.0 && r <= 1.0 => Ok(()),
            (None, Some(p)) if (200..=32768).contains(&p) => Ok(()),
            _ => Err(
                "A width needs either proportion (greater than 0, up to 1) or pixels (200–32768)"
                    .into(),
            ),
        }
    }
    pub fn resolve(&self, available: i32) -> i32 {
        self.pixels
            .unwrap_or_else(|| (available.max(1) as f64 * self.proportion.unwrap()).round() as i32)
            .max(200)
    }
}

#[derive(Clone, Debug, Default, PartialEq, Serialize, Deserialize)]
#[serde(default, deny_unknown_fields)]
pub struct Keyboard {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub layout: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub variant: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub options: Option<String>,
}
impl Keyboard {
    pub fn xkb(&self) -> XkbConfig<'_> {
        XkbConfig {
            layout: self.layout.as_deref().unwrap_or(""),
            variant: self.variant.as_deref().unwrap_or(""),
            options: self.options.clone(),
            ..Default::default()
        }
    }
    pub fn validate(&self) -> Result<(), String> {
        for value in [&self.layout, &self.variant, &self.options]
            .into_iter()
            .flatten()
        {
            if value.contains('\0') {
                return Err("Keyboard options cannot contain NUL characters".into());
            }
        }
        let c = self.xkb();
        let context = xkb::Context::new(xkb::CONTEXT_NO_FLAGS);
        xkb::Keymap::new_from_names(
            &context,
            c.rules,
            c.model,
            c.layout,
            c.variant,
            c.options,
            xkb::KEYMAP_COMPILE_NO_FLAGS,
        )
        .map(|_| ())
        .ok_or_else(|| "Could not compile the configured keyboard layout/variant/options".into())
    }
}
#[derive(Clone, Debug, Default, PartialEq, Serialize, Deserialize)]
#[serde(default, deny_unknown_fields)]
pub struct Touchpad {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub tap: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub natural_scroll: Option<bool>,
}
#[derive(Clone, Debug, Default, PartialEq, Serialize, Deserialize)]
#[serde(default, deny_unknown_fields)]
pub struct Input {
    #[serde(skip_serializing_if = "is_default")]
    pub keyboard: Keyboard,
    #[serde(skip_serializing_if = "is_default")]
    pub touchpad: Touchpad,
}
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(default, deny_unknown_fields)]
pub struct LayoutPreferences {
    pub gap: i32,
    pub default_column_width: Width,
}
impl Default for LayoutPreferences {
    fn default() -> Self {
        Self {
            gap: 12,
            default_column_width: Width::default(),
        }
    }
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(default, deny_unknown_fields)]
pub struct Animations {
    pub enabled: bool,
    pub duration_ms: u32,
}
impl Default for Animations {
    fn default() -> Self {
        Self {
            enabled: true,
            duration_ms: 180,
        }
    }
}

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct WindowMatch {
    pub app_id: String,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct WindowRule {
    #[serde(rename = "match")]
    pub matcher: WindowMatch,
    pub default_column_width: Width,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(tag = "action", rename_all = "kebab-case", deny_unknown_fields)]
pub enum Action {
    None,
    FocusPrev,
    FocusNext,
    MovePrev,
    MoveNext,
    Fullscreen,
    Terminal,
    Launcher,
    Logout,
    Close,
    FocusOutputPrev,
    FocusOutputNext,
    MoveOutputPrev,
    MoveOutputNext,
    Resize {
        value: i64,
    },
    Workspace {
        value: u8,
    },
    MoveWorkspace {
        value: u8,
    },
    Output {
        value: u8,
    },
    Scale {
        value: Option<i64>,
    },
    Launch {
        program: String,
        #[serde(default)]
        args: Vec<String>,
    },
    ReloadConfig,
    SaveConfig,
}
impl Action {
    fn validate(&self) -> Result<(), String> {
        match self {
            Self::Workspace { value } | Self::MoveWorkspace { value }
                if !(1..=4).contains(value) =>
            {
                Err("Binding workspace must be 1 to 4".into())
            }
            Self::Output { value } if *value == 0 => Err("Binding output is 1-based".into()),
            Self::Resize { value } if !(-2000..=2000).contains(value) => {
                Err("Binding resize must be -2000 to 2000".into())
            }
            Self::Scale { value: Some(v) } if !(50..=200).contains(v) => {
                Err("Binding scale must be 50 to 200 percent".into())
            }
            Self::Launch { program, args }
                if program.is_empty()
                    || program.contains('\0')
                    || args.iter().any(|s| s.contains('\0')) =>
            {
                Err("Launch bindings need a program and NUL-free arguments".into())
            }
            _ => Ok(()),
        }
    }
    pub fn execute(&self, state: &mut Smallvil) -> Result<(), String> {
        use Action::*;
        let (name, value) = match self {
            None => return Ok(()),
            Launch { program, args } => {
                return crate::spawn_application(&state.socket_name, program, args)
                    .map_err(|e| e.to_string())
            }
            ReloadConfig => return state.output_request("reload-config", &serde_json::Value::Null),
            SaveConfig => return state.output_request("save-config", &serde_json::Value::Null),
            Resize { value } => ("resize", Some(*value)),
            Workspace { value } => ("workspace", Some(*value as i64)),
            MoveWorkspace { value } => ("move-workspace", Some(*value as i64)),
            Output { value } => ("output", Some(*value as i64)),
            Scale { value } => ("scale", *value),
            action => (
                match action {
                    FocusPrev => "focus-prev",
                    FocusNext => "focus-next",
                    MovePrev => "move-prev",
                    MoveNext => "move-next",
                    Fullscreen => "fullscreen",
                    Terminal => "terminal",
                    Launcher => "launcher",
                    Logout => "logout",
                    Close => "close",
                    FocusOutputPrev => "focus-output-prev",
                    FocusOutputNext => "focus-output-next",
                    MoveOutputPrev => "move-output-prev",
                    MoveOutputNext => "move-output-next",
                    _ => unreachable!(),
                },
                Option::None,
            ),
        };
        state.action(name, value)
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub struct Chord {
    modifiers: u8,
    key: u32,
}
fn lowercase(key: u32) -> u32 {
    if (65..=90).contains(&key) {
        key + 32
    } else {
        key
    }
}
impl Chord {
    fn parse(text: &str, profile: ShortcutModifier) -> Result<Self, String> {
        let mut parts: Vec<_> = text.split('+').collect();
        let key = parts
            .pop()
            .filter(|s| !s.is_empty() && !s.contains('\0'))
            .ok_or("Binding needs a key name")?;
        let mut modifiers = 0;
        for modifier in parts {
            modifiers |= match modifier.to_ascii_lowercase().as_str() {
                "mod" => {
                    if profile == ShortcutModifier::SuperAlt {
                        1 | 2
                    } else {
                        1
                    }
                }
                "super" => 1,
                "alt" => 2,
                "ctrl" | "control" => 4,
                "shift" => 8,
                _ => return Err(format!("Unknown modifier {modifier} in {text}")),
            };
        }
        let symbol = xkb::keysym_from_name(key, xkb::KEYSYM_CASE_INSENSITIVE).raw();
        if symbol == 0 {
            return Err(format!("Unknown key name {key}"));
        }
        if modifiers & 6 == 6 && (0xffbe..=0xffc9).contains(&symbol) {
            return Err("Ctrl+Alt+F1–F12 are reserved for VT switching".into());
        }
        Ok(Self {
            modifiers,
            key: lowercase(symbol),
        })
    }
    pub fn matches(self, mods: &ModifiersState, symbols: &[u32]) -> bool {
        self.modifiers
            == (u8::from(mods.logo)
                | (u8::from(mods.alt) * 2)
                | (u8::from(mods.ctrl) * 4)
                | (u8::from(mods.shift) * 8))
            && symbols.iter().any(|s| lowercase(*s) == self.key)
    }
}

pub fn bindings(
    overrides: &BTreeMap<String, Action>,
    profile: ShortcutModifier,
) -> Result<Vec<(Chord, Action)>, String> {
    use Action::*;
    let mut defaults = vec![
        ("Mod+Return".to_owned(), Terminal),
        ("Mod+D".into(), Launcher),
        ("Mod+Shift+E".into(), Logout),
        ("Mod+H".into(), FocusPrev),
        ("Mod+Left".into(), FocusPrev),
        ("Mod+L".into(), FocusNext),
        ("Mod+Right".into(), FocusNext),
        ("Mod+Shift+H".into(), MovePrev),
        ("Mod+Shift+Left".into(), MovePrev),
        ("Mod+Shift+L".into(), MoveNext),
        ("Mod+Shift+Right".into(), MoveNext),
        ("Mod+minus".into(), Resize { value: -80 }),
        ("Mod+equal".into(), Resize { value: 80 }),
        ("Mod+Shift+minus".into(), Resize { value: -80 }),
        ("Mod+Shift+equal".into(), Resize { value: 80 }),
        ("Mod+F".into(), Fullscreen),
        ("Mod+Q".into(), Close),
        (
            "Mod+S".into(),
            Scale {
                value: Option::None,
            },
        ),
        ("Mod+comma".into(), FocusOutputPrev),
        ("Mod+period".into(), FocusOutputNext),
        ("Mod+Shift+comma".into(), MoveOutputPrev),
        ("Mod+Shift+period".into(), MoveOutputNext),
    ];
    for n in 1..=4 {
        defaults.push((format!("Mod+{n}"), Workspace { value: n }));
        defaults.push((format!("Mod+Shift+{n}"), MoveWorkspace { value: n }));
    }
    let mut result: BTreeMap<_, _> = defaults
        .into_iter()
        .map(|(key, action)| Ok((Chord::parse(&key, profile)?, action)))
        .collect::<Result<_, String>>()?;
    let mut custom = BTreeMap::new();
    for (key, action) in overrides {
        action.validate()?;
        let chord = Chord::parse(key, profile)?;
        if custom.insert(chord, ()).is_some() {
            return Err(format!("Duplicate binding for {key}"));
        }
        if matches!(action, None) {
            result.remove(&chord);
        } else {
            result.insert(chord, action.clone());
        }
    }
    Ok(result.into_iter().collect())
}

impl Smallvil {
    pub fn apply_preferences(
        &mut self,
        settings: &crate::output_config::Settings,
    ) -> Result<(), String> {
        let bindings = bindings(&settings.bindings, self.shortcut_modifier)?;
        if self.applied_keyboard != settings.input.keyboard {
            self.seat
                .get_keyboard()
                .unwrap()
                .set_xkb_config(self, settings.input.keyboard.xkb())
                .map_err(|e| format!("Keyboard configuration rejected: {e}"))?;
            self.applied_keyboard = settings.input.keyboard.clone();
        }
        self.configured_bindings = bindings;
        Ok(())
    }
    pub fn apply_layout_preferences(&mut self) {
        for monitor in &mut self.layout.monitors {
            let layout = &mut monitor.layout;
            layout.gap = self.output_settings.layout.gap;
            layout.default_width = self.output_settings.layout.default_column_width.clone();
            layout.animations_enabled = self.output_settings.animations.enabled;
            layout.animation_duration = self.output_settings.animations.duration_ms as f64 / 1000.0;
            layout.set_size(layout.size);
        }
    }
    pub fn apply_window_preferences(&mut self) -> bool {
        use smithay::wayland::{compositor::with_states, shell::xdg::XdgToplevelSurfaceData};
        let candidates: Vec<_> = self
            .windows
            .iter()
            .filter(|(id, _)| !self.window_preferences_applied.contains(id))
            .filter_map(|(id, window)| {
                with_states(window.toplevel().unwrap().wl_surface(), |states| {
                    let metadata = states
                        .data_map
                        .get::<XdgToplevelSurfaceData>()?
                        .lock()
                        .unwrap();
                    metadata.app_id.clone().map(|app| (*id, app))
                })
            })
            .collect();
        let mut changed = false;
        for (id, app) in candidates {
            if let Some(rule) = self
                .output_settings
                .window_rules
                .iter()
                .rev()
                .find(|r| r.matcher.app_id == app)
            {
                if let Some(owner) = self.layout.owner(id) {
                    let layout = &self.layout.monitors[owner].layout;
                    self.layout.set_width(
                        id,
                        rule.default_column_width
                            .resolve(layout.size.0 - 2 * layout.gap),
                    );
                    changed = true;
                }
            }
            self.window_preferences_applied.insert(id);
        }
        changed
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn custom_bindings_replace_defaults_and_keep_nested_modifiers_separate() {
        let overrides = BTreeMap::from([
            ("Mod+Q".into(), Action::None),
            ("Mod+Return".into(), Action::Fullscreen),
        ]);
        let host = bindings(&overrides, ShortcutModifier::Super).unwrap();
        let child = bindings(&overrides, ShortcutModifier::SuperAlt).unwrap();
        let chord = Chord::parse("Super+Return", ShortcutModifier::Super).unwrap();
        assert!(host
            .iter()
            .any(|(c, a)| *c == chord && matches!(a, Action::Fullscreen)));
        assert!(!child.iter().any(|(c, _)| *c == chord));
        assert!(!host
            .iter()
            .any(|(c, _)| *c == Chord::parse("Mod+Q", ShortcutModifier::Super).unwrap()));
        assert!(Chord::parse("Ctrl+Alt+F2", ShortcutModifier::Super).is_err());
    }
}
