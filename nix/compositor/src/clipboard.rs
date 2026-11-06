//! Translate clipboard shortcuts at the focused Wayland surface, without
//! injecting into (or changing) the seat's physical XKB/pressed-key state.
use crate::{input::ShortcutModifier, preferences::Chord, Smallvil};
use serde::{Deserialize, Serialize};
use smithay::{
    reexports::wayland_server::{protocol::wl_keyboard::KeyState, Resource},
    utils::{Clock, Monotonic, SERIAL_COUNTER},
    wayland::{
        compositor::{get_parent, with_states},
        shell::xdg::XdgToplevelSurfaceData,
    },
};

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(default, deny_unknown_fields)]
pub struct Clipboard {
    pub copy: String,
    pub paste: String,
    pub terminal_copy: String,
    pub terminal_paste: String,
    pub terminal_app_ids: Vec<String>,
}

impl Default for Clipboard {
    fn default() -> Self {
        Self {
            copy: "Ctrl+C".into(),
            paste: "Ctrl+V".into(),
            terminal_copy: "Ctrl+Shift+C".into(),
            terminal_paste: "Ctrl+Shift+V".into(),
            terminal_app_ids: [
                "foot",
                "footclient",
                "org.codeberg.dnkl.foot",
                "Alacritty",
                "kitty",
                "com.mitchellh.ghostty",
                "org.wezfurlong.wezterm",
                "wezterm",
                "org.gnome.Terminal",
                "org.gnome.Console",
                "ohmansy-nested-client",
            ]
            .into_iter()
            .map(String::from)
            .collect(),
        }
    }
}

impl Clipboard {
    pub fn validate(&self) -> Result<(), String> {
        for key in [
            &self.copy,
            &self.paste,
            &self.terminal_copy,
            &self.terminal_paste,
        ] {
            Chord::parse(key, ShortcutModifier::Super)?;
            if key.split('+').any(|part| part.eq_ignore_ascii_case("mod")) {
                return Err("Clipboard target shortcuts need explicit modifiers, not Mod".into());
            }
        }
        if self
            .terminal_app_ids
            .iter()
            .any(|id| id.is_empty() || id.contains('\0'))
        {
            return Err("Terminal app IDs must be nonempty and NUL-free".into());
        }
        Ok(())
    }

    fn target(&self, copy: bool, app_id: Option<&str>) -> &str {
        let terminal = app_id.is_some_and(|id| self.terminal_app_ids.iter().any(|app| app == id));
        match (copy, terminal) {
            (true, false) => &self.copy,
            (false, false) => &self.paste,
            (true, true) => &self.terminal_copy,
            (false, true) => &self.terminal_paste,
        }
    }
}

impl Smallvil {
    pub fn send_clipboard_shortcut(&mut self, copy: bool) -> Result<(), String> {
        let keyboard = self.seat.get_keyboard().unwrap();
        let Some(focus) = keyboard.current_focus() else {
            return Ok(());
        };
        let Some(client) = focus.client() else {
            return Ok(());
        };
        // Classify the actual keyboard focus, not the layout's last active app.
        // Subsurfaces inherit the root app; a focused layer panel is ordinary.
        let mut root = focus;
        while let Some(parent) = get_parent(&root) {
            root = parent;
        }
        let app_id = with_states(&root, |states| {
            states
                .data_map
                .get::<XdgToplevelSurfaceData>()
                .and_then(|data| data.lock().unwrap().app_id.clone())
        });
        let text = self
            .output_settings
            .clipboard
            .target(copy, app_id.as_deref());
        let chord = Chord::parse(text, ShortcutModifier::Super)?;
        let physical = keyboard.modifier_state().serialized;
        let resolved = keyboard.with_xkb_state(self, |context| {
            let xkb = context.xkb().lock().unwrap();
            // SAFETY: Neither reference nor a clone escapes the locked Xkb.
            let keymap = unsafe { xkb.keymap() };
            chord.resolve(keymap, physical.layout_effective)
        });
        let (code, modifiers) =
            resolved.ok_or("Clipboard target key is absent from the keyboard layout")?;
        // Never synthesize a release for a key the client is already holding.
        // The triggering shortcut key itself was intercepted, so is safe.
        if keyboard
            .pressed_keys()
            .iter()
            .any(|key| key.raw() == code + 8 && !self.shortcut_keys.contains(&key.raw()))
        {
            return Ok(());
        }
        let mods = modifiers.serialized;
        let time = Clock::<Monotonic>::new().now().as_millis();
        for target in keyboard.client_keyboards(&client) {
            target.modifiers(
                SERIAL_COUNTER.next_serial().into(),
                mods.depressed,
                mods.latched,
                mods.locked,
                mods.layout_effective,
            );
            target.key(
                SERIAL_COUNTER.next_serial().into(),
                time,
                code,
                KeyState::Pressed,
            );
            target.key(
                SERIAL_COUNTER.next_serial().into(),
                time,
                code,
                KeyState::Released,
            );
            target.modifiers(
                SERIAL_COUNTER.next_serial().into(),
                physical.depressed,
                physical.latched,
                physical.locked,
                physical.layout_effective,
            );
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use smithay::input::keyboard::xkb;

    #[test]
    fn terminal_matching_and_target_overrides() {
        let mut config = Clipboard::default();
        assert_eq!(config.target(true, Some("foot")), "Ctrl+Shift+C");
        assert_eq!(config.target(false, Some("firefox")), "Ctrl+V");
        assert_eq!(config.target(true, None), "Ctrl+C");
        config.terminal_app_ids = vec!["my-terminal".into()];
        config.terminal_paste = "Shift+Insert".into();
        assert_eq!(config.target(false, Some("my-terminal")), "Shift+Insert");
        assert_eq!(config.target(false, Some("foot")), "Ctrl+V");
        config.validate().unwrap();
        config.copy = "Mod+C".into();
        assert!(config.validate().is_err());
        config.copy = "Ctrl+MissingKey".into();
        assert!(config.validate().is_err());
    }

    #[test]
    fn targets_follow_layout_and_have_only_explicit_modifiers() {
        let context = xkb::Context::new(xkb::CONTEXT_NO_FLAGS);
        for (layout, code) in [("us", 47), ("de", 47), ("us,ru", 47)] {
            let keymap = xkb::Keymap::new_from_names(
                &context,
                "",
                "",
                layout,
                "",
                None,
                xkb::KEYMAP_COMPILE_NO_FLAGS,
            )
            .unwrap();
            let chord = Chord::parse("Ctrl+Shift+V", ShortcutModifier::Super).unwrap();
            let (resolved, mods) = chord.resolve(&keymap, keymap.num_layouts() - 1).unwrap();
            assert_eq!(resolved, code);
            assert!(mods.ctrl && mods.shift);
            assert!(!mods.logo && !mods.alt);
        }
        // Resolve a target symbol through the configured layout, not a fixed
        // US hardware code (Y is on the physical Z key in German).
        let keymap = xkb::Keymap::new_from_names(
            &context,
            "",
            "",
            "de",
            "",
            None,
            xkb::KEYMAP_COMPILE_NO_FLAGS,
        )
        .unwrap();
        let chord = Chord::parse("Ctrl+Y", ShortcutModifier::Super).unwrap();
        assert_eq!(chord.resolve(&keymap, 0).unwrap().0, 44);
    }
}
