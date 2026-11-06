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
pub struct Decorations {
    pub corner_radius: u32,
    pub focus_ring_width: u32,
    pub focus_ring_color: [f32; 4],
    pub inactive_ring_width: u32,
    pub inactive_ring_color: [f32; 4],
    pub shadow: Shadow,
    pub inactive: Inactive,
}
impl Default for Decorations {
    fn default() -> Self {
        Self {
            corner_radius: 14,
            focus_ring_width: 2,
            focus_ring_color: [0.55, 0.50, 0.62, 0.75],
            inactive_ring_width: 1,
            inactive_ring_color: [0.55, 0.55, 0.60, 0.55],
            shadow: Shadow::default(),
            inactive: Inactive::default(),
        }
    }
}
impl Decorations {
    pub fn validate(&self) -> Result<(), String> {
        if self.corner_radius > 128 || self.focus_ring_width > 16 || self.inactive_ring_width > 16 {
            return Err("Corner radius must be 0–128 and ring widths 0–16 logical pixels".into());
        }
        if self
            .focus_ring_color
            .iter()
            .chain(self.inactive_ring_color.iter())
            .any(|v| !v.is_finite() || !(0.0..=1.0).contains(v))
        {
            return Err("Ring colors need four RGBA values from 0 to 1".into());
        }
        self.inactive.validate()?;
        self.shadow.validate()
    }
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(default, deny_unknown_fields)]
pub struct Inactive {
    pub enabled: bool,
    pub scale: f64,
    pub saturation: f32,
    pub fog: f32,
    pub fog_color: [f32; 3],
    #[serde(deserialize_with = "inactive_duration")]
    pub duration_ms: u32,
    pub easing: FocusEasing,
}
#[derive(Clone, Copy, Debug, Default, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum FocusEasing {
    Linear,
    EaseIn,
    #[default]
    EaseOut,
    EaseInOut,
}
impl FocusEasing {
    pub fn sample(self, t: f64) -> f64 {
        match self {
            Self::Linear => t,
            Self::EaseIn => t.powi(3),
            Self::EaseOut => 1.0 - (1.0 - t).powi(3),
            Self::EaseInOut => {
                if t < 0.5 {
                    4.0 * t.powi(3)
                } else {
                    1.0 - (-2.0 * t + 2.0).powi(3) / 2.0
                }
            }
        }
    }
}
impl Default for Inactive {
    fn default() -> Self {
        Self {
            enabled: true,
            scale: 0.99,
            saturation: 0.85,
            fog: 0.08,
            fog_color: [0.5, 0.5, 0.55],
            duration_ms: 160,
            easing: FocusEasing::default(),
        }
    }
}
impl Inactive {
    pub fn clamp(&mut self) {
        let defaults = Self::default();
        self.scale = if self.scale.is_nan() {
            defaults.scale
        } else {
            self.scale.clamp(0.8, 1.0)
        };
        for (value, fallback) in std::iter::once((&mut self.saturation, defaults.saturation))
            .chain(std::iter::once((&mut self.fog, defaults.fog)))
            .chain(self.fog_color.iter_mut().zip(defaults.fog_color))
        {
            *value = if value.is_nan() {
                fallback
            } else {
                value.clamp(0.0, 1.0)
            };
        }
        self.duration_ms = self.duration_ms.min(5000);
    }
    fn validate(&self) -> Result<(), String> {
        if !self.scale.is_finite()
            || !(0.8..=1.0).contains(&self.scale)
            || self.duration_ms > 5000
            || [self.saturation, self.fog]
                .iter()
                .chain(self.fog_color.iter())
                .any(|v| !v.is_finite() || !(0.0..=1.0).contains(v))
        {
            return Err(
                "Inactive scale must be 0.8–1, colors and strength 0–1, duration 0–5000 ms".into(),
            );
        }
        Ok(())
    }
}

fn inactive_duration<'de, D: serde::Deserializer<'de>>(deserializer: D) -> Result<u32, D::Error> {
    let duration = i64::deserialize(deserializer)?;
    Ok(duration.clamp(0, 5000) as u32)
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(default, deny_unknown_fields)]
pub struct Shadow {
    pub enabled: bool,
    pub softness: u32,
    pub spread: u32,
    pub offset: [i32; 2],
    pub color: [f32; 4],
}
impl Default for Shadow {
    fn default() -> Self {
        Self {
            enabled: true,
            softness: 12,
            spread: 2,
            offset: [0, 6],
            color: [0.0, 0.0, 0.0, 0.35],
        }
    }
}
impl Shadow {
    fn validate(&self) -> Result<(), String> {
        if !(1..=64).contains(&self.softness)
            || self.spread > 64
            || self.offset.iter().any(|v| !(-128..=128).contains(v))
        {
            return Err(
                "Shadow softness must be 1–64, spread 0–64, and offsets −128–128 logical pixels"
                    .into(),
            );
        }
        if self
            .color
            .iter()
            .any(|v| !v.is_finite() || !(0.0..=1.0).contains(v))
        {
            return Err("Shadow color needs four RGBA values from 0 to 1".into());
        }
        Ok(())
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
    Copy,
    Paste,
    FocusPrev,
    FocusNext,
    FocusNextWrap,
    MovePrev,
    MoveNext,
    Fullscreen,
    Maximize,
    ToggleFloating,
    Terminal,
    Launcher,
    Logout,
    Screenshot {
        #[serde(default)]
        annotate: bool,
    },
    Close,
    FocusOutputPrev,
    FocusOutputNext,
    MoveOutputPrev,
    MoveOutputNext,
    WorkspacePrev,
    WorkspaceNext,
    MoveWorkspacePrev,
    MoveWorkspaceNext,
    Resize {
        value: i64,
    },
    CycleWidth {
        #[serde(default)]
        reverse: bool,
    },
    Workspace {
        value: u8,
    },
    Task {
        id: String,
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
    ScaleAdjust {
        value: i64,
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
            Self::Task { id } if !crate::tasks::valid_id(id) => {
                Err("Task bindings need a workspace ID containing letters, digits, - or _".into())
            }
            Self::Workspace { value } | Self::MoveWorkspace { value } if *value == 0 => {
                Err("Binding workspace must be 1-based".into())
            }
            Self::Output { value } if *value == 0 => Err("Binding output is 1-based".into()),
            Self::Resize { value } if !(-2000..=2000).contains(value) => {
                Err("Binding resize must be -2000 to 2000".into())
            }
            Self::Scale { value: Some(v) } if !(50..=200).contains(v) => {
                Err("Binding scale must be 50 to 200 percent".into())
            }
            Self::ScaleAdjust { value } if *value == 0 || !(-150..=150).contains(value) => Err(
                "Binding scale-adjust must be a nonzero percentage point delta from -150 to 150"
                    .into(),
            ),
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
            Task { id } => return state.focus_task(id),
            Copy => return state.send_clipboard_shortcut(true),
            Paste => return state.send_clipboard_shortcut(false),
            Screenshot { annotate } => return state.request_screenshot(Option::None, *annotate),
            Launch { program, args } => {
                return crate::spawn_application(&state.socket_name, program, args)
                    .map_err(|e| e.to_string())
            }
            ReloadConfig => return state.output_request("reload-config", &serde_json::Value::Null),
            SaveConfig => return state.output_request("save-config", &serde_json::Value::Null),
            Resize { value } => ("resize", Some(*value)),
            CycleWidth { reverse } => ("cycle-width", Some(if *reverse { -1 } else { 1 })),
            Workspace { value } => ("workspace", Some(*value as i64)),
            MoveWorkspace { value } => ("move-workspace", Some(*value as i64)),
            Output { value } => ("output", Some(*value as i64)),
            Scale { value } => ("scale", *value),
            ScaleAdjust { value } => ("scale-adjust", Some(*value)),
            action => (
                match action {
                    FocusPrev => "focus-prev",
                    FocusNext => "focus-next",
                    FocusNextWrap => "focus-next-wrap",
                    MovePrev => "move-prev",
                    MoveNext => "move-next",
                    Fullscreen => "fullscreen",
                    Maximize => "maximize",
                    ToggleFloating => "toggle-floating",
                    Terminal => "terminal",
                    Launcher => "launcher",
                    Logout => "logout",
                    Close => "close",
                    FocusOutputPrev => "focus-output-prev",
                    FocusOutputNext => "focus-output-next",
                    MoveOutputPrev => "move-output-prev",
                    MoveOutputNext => "move-output-next",
                    WorkspacePrev => "workspace-prev",
                    WorkspaceNext => "workspace-next",
                    MoveWorkspacePrev => "move-workspace-prev",
                    MoveWorkspaceNext => "move-workspace-next",
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
    pub(crate) fn parse(text: &str, profile: ShortcutModifier) -> Result<Self, String> {
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

    pub(crate) fn resolve(
        &self,
        keymap: &xkb::Keymap,
        layout: u32,
    ) -> Option<(u32, ModifiersState)> {
        // Prefer the active layout, then a layout containing the requested symbol.
        // Only level zero is used: Shift is explicit in the configured chord.
        for group in std::iter::once(layout).chain(0..keymap.num_layouts()) {
            for code in keymap.min_keycode().raw()..=keymap.max_keycode().raw() {
                if keymap
                    .key_get_syms_by_level(code.into(), group, 0)
                    .iter()
                    .any(|symbol| lowercase(symbol.raw()) == self.key)
                {
                    let mut mods = ModifiersState {
                        logo: self.modifiers & 1 != 0,
                        alt: self.modifiers & 2 != 0,
                        ctrl: self.modifiers & 4 != 0,
                        shift: self.modifiers & 8 != 0,
                        ..Default::default()
                    };
                    let mut state = xkb::State::new(keymap);
                    let mask = mods.serialize_back(&state);
                    state.update_mask(mask.depressed, 0, 0, 0, 0, group);
                    mods.update_with(&state);
                    return Some((code - 8, mods));
                }
            }
        }
        None
    }
}

pub fn bindings(
    overrides: &BTreeMap<String, Action>,
    profile: ShortcutModifier,
) -> Result<Vec<(Chord, Action)>, String> {
    use Action::*;
    let mut defaults = vec![
        ("Mod+C".into(), Copy),
        ("Mod+V".into(), Paste),
        ("Print".into(), Screenshot { annotate: false }),
        ("Mod+Shift+4".into(), Screenshot { annotate: false }),
        ("Ctrl+Print".into(), Screenshot { annotate: false }),
        ("Shift+Print".into(), Screenshot { annotate: true }),
        ("Mod+Return".to_owned(), Terminal),
        ("Mod+Space".into(), Launcher),
        ("Mod+Shift+Space".into(), ToggleFloating),
        (
            "Mod+E".into(),
            Launch {
                program: "nautilus".into(),
                args: Vec::new(),
            },
        ),
        ("Mod+R".into(), CycleWidth { reverse: false }),
        ("Mod+Shift+R".into(), CycleWidth { reverse: true }),
        ("Mod+Shift+E".into(), Logout),
        ("Mod+H".into(), FocusPrev),
        ("Mod+Left".into(), FocusPrev),
        ("Mod+L".into(), FocusNext),
        ("Mod+Right".into(), FocusNext),
        ("Mod+Tab".into(), FocusNextWrap),
        ("Mod+Up".into(), WorkspacePrev),
        ("Mod+Down".into(), WorkspaceNext),
        ("Mod+Shift+Up".into(), MoveWorkspacePrev),
        ("Mod+Shift+Down".into(), MoveWorkspaceNext),
        ("Mod+Shift+H".into(), MovePrev),
        ("Mod+Shift+Left".into(), MovePrev),
        ("Mod+Shift+L".into(), MoveNext),
        ("Mod+Shift+Right".into(), MoveNext),
        ("Mod+minus".into(), ScaleAdjust { value: -5 }),
        ("Mod+0".into(), Scale { value: Some(100) }),
        ("Mod+equal".into(), ScaleAdjust { value: 5 }),
        ("Mod+plus".into(), ScaleAdjust { value: 5 }),
        ("Mod+Shift+plus".into(), ScaleAdjust { value: 5 }),
        ("Mod+Shift+equal".into(), ScaleAdjust { value: 5 }),
        ("Mod+Ctrl+minus".into(), Resize { value: -80 }),
        ("Mod+Ctrl+equal".into(), Resize { value: 80 }),
        ("Mod+F".into(), Maximize),
        ("Mod+Shift+F".into(), Fullscreen),
        ("Mod+W".into(), Close),
        ("Mod+comma".into(), FocusOutputPrev),
        ("Mod+period".into(), FocusOutputNext),
        ("Mod+Shift+comma".into(), MoveOutputPrev),
        ("Mod+Shift+period".into(), MoveOutputNext),
    ];
    for n in 1..=4 {
        defaults.push((format!("Mod+{n}"), Workspace { value: n }));
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
        let ids = if self.task_settings.workspaces.is_empty() {
            (1..=4).map(|n| n.to_string()).collect()
        } else {
            self.task_settings
                .workspaces
                .iter()
                .map(|task| task.id.clone())
                .collect()
        };
        self.layout.configure_workspaces(ids);
        for monitor in &mut self.layout.monitors {
            let layout = &mut monitor.layout;
            layout.gap = self.output_settings.layout.gap;
            layout.default_width = self.output_settings.layout.default_column_width.clone();
            if layout.animations_enabled != self.output_settings.animations.enabled
                || layout.animation_duration
                    != self.output_settings.animations.duration_ms as f64 / 1000.0
            {
                layout.finish_movements();
            }
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
                            .resolve(layout.work_area.2 - 2 * layout.gap),
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
    fn launcher_and_width_shortcuts_follow_both_modifier_profiles() {
        for profile in [ShortcutModifier::Super, ShortcutModifier::SuperAlt] {
            let defaults = bindings(&BTreeMap::new(), profile).unwrap();
            let action = |key| {
                defaults
                    .iter()
                    .find(|(c, _)| *c == Chord::parse(key, profile).unwrap())
                    .map(|(_, a)| a)
            };
            assert!(matches!(action("Mod+Space"), Some(Action::Launcher)));
            assert!(matches!(action("Mod+C"), Some(Action::Copy)));
            assert!(matches!(action("Mod+V"), Some(Action::Paste)));
            assert!(matches!(action("Mod+Tab"), Some(Action::FocusNextWrap)));
            assert!(matches!(action("Mod+Right"), Some(Action::FocusNext)));
            assert!(matches!(
                action("Mod+E"),
                Some(Action::Launch { program, args }) if program == "nautilus" && args.is_empty()
            ));
            assert!(action("Mod+D").is_none());
            assert!(action("Mod+Q").is_none());
            assert!(matches!(action("Mod+W"), Some(Action::Close)));
            assert!(matches!(action("Mod+Up"), Some(Action::WorkspacePrev)));
            assert!(matches!(action("Mod+Down"), Some(Action::WorkspaceNext)));
            assert!(matches!(
                action("Mod+Shift+Up"),
                Some(Action::MoveWorkspacePrev)
            ));
            assert!(matches!(
                action("Mod+Shift+Down"),
                Some(Action::MoveWorkspaceNext)
            ));
            assert!(matches!(action("Mod+F"), Some(Action::Maximize)));
            assert!(matches!(action("Mod+Shift+F"), Some(Action::Fullscreen)));
            assert!(matches!(
                action("Mod+R"),
                Some(Action::CycleWidth { reverse: false })
            ));
            assert!(matches!(
                action("Mod+Shift+R"),
                Some(Action::CycleWidth { reverse: true })
            ));
        }
    }
    #[test]
    fn custom_bindings_replace_defaults_and_keep_nested_modifiers_separate() {
        let overrides = BTreeMap::from([
            ("Mod+W".into(), Action::None),
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
            .any(|(c, _)| *c == Chord::parse("Mod+W", ShortcutModifier::Super).unwrap()));
        assert!(Chord::parse("Ctrl+Alt+F2", ShortcutModifier::Super).is_err());
    }
}
