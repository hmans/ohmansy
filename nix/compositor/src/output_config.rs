//! Monitor preferences, validated independently of the display backend.
use serde::{Deserialize, Serialize};
use std::{
    collections::{BTreeMap, BTreeSet},
    path::{Path, PathBuf},
};

#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
pub struct VideoMode {
    pub width: i32,
    pub height: i32,
    pub refresh: i32,
}
impl VideoMode {
    pub fn parse(text: &str) -> Result<Self, String> {
        let (size, refresh) = text
            .split_once('@')
            .map_or((text, None), |(s, r)| (s, Some(r)));
        let (width, height) = size
            .split_once('x')
            .ok_or("Mode must be WIDTHxHEIGHT[@HZ]")?;
        let refresh = refresh
            .map(|r| r.parse::<f64>().map_err(|_| "Invalid refresh rate"))
            .transpose()?
            .unwrap_or(0.0)
            * 1000.0;
        let mode = Self {
            width: width.parse().map_err(|_| "Invalid mode width")?,
            height: height.parse().map_err(|_| "Invalid mode height")?,
            refresh: refresh.round() as i32,
        };
        if !(1..=32768).contains(&mode.width)
            || !(1..=32768).contains(&mode.height)
            || !refresh.is_finite()
            || !(0.0..=1_000_000.0).contains(&refresh)
        {
            return Err("Invalid mode dimensions or refresh rate".into());
        }
        Ok(mode)
    }
    pub fn name(&self) -> String {
        format!(
            "{}x{}@{}",
            self.width,
            self.height,
            self.refresh as f64 / 1000.0
        )
    }
    pub fn size(&self) -> (i32, i32) {
        (self.width, self.height)
    }
}

#[derive(Clone, Debug, Serialize)]
pub struct OutputInfo {
    pub name: String,
    pub id: String,
    pub make: String,
    pub model: String,
    pub modes: Vec<VideoMode>,
    pub preferred: VideoMode,
    pub adjustable_mode: bool,
}
impl OutputInfo {
    pub fn virtual_output(name: String, size: (i32, i32)) -> Self {
        let preferred = VideoMode {
            width: size.0,
            height: size.1,
            refresh: 60_000,
        };
        Self {
            id: format!("connector:{name}"),
            name,
            make: "ohmansy".into(),
            model: "Shine preview".into(),
            modes: vec![preferred.clone()],
            preferred,
            adjustable_mode: false,
        }
    }
}

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct OutputRule {
    /// Stable EDID id, or connector:NAME for displays without a unique serial.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub id: Option<String>,
    pub name: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub position: Option<[i32; 2]>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub scale: Option<f64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub mode: Option<String>,
    #[serde(default, skip_serializing_if = "std::ops::Not::not")]
    pub primary: bool,
}

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Settings {
    #[serde(default, skip_serializing_if = "crate::preferences::is_default")]
    pub browser: crate::preferences::Browser,
    #[serde(default, skip_serializing_if = "crate::preferences::is_default")]
    pub clipboard: crate::clipboard::Clipboard,
    #[serde(default)]
    pub outputs: Vec<OutputRule>,
    #[serde(default, skip_serializing_if = "crate::preferences::is_default")]
    pub input: crate::preferences::Input,
    #[serde(default, skip_serializing_if = "crate::preferences::is_default")]
    pub layout: crate::preferences::LayoutPreferences,
    #[serde(default, skip_serializing_if = "BTreeMap::is_empty")]
    pub bindings: std::collections::BTreeMap<String, crate::preferences::Action>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub window_rules: Vec<crate::preferences::WindowRule>,
    #[serde(default, skip_serializing_if = "crate::preferences::is_default")]
    pub animations: crate::preferences::Animations,
    #[serde(default, skip_serializing_if = "crate::preferences::is_default")]
    pub decorations: crate::preferences::Decorations,
}

#[derive(Clone, Debug)]
pub struct Placement {
    pub name: String,
    pub size: (i32, i32),
    pub origin: (i32, i32),
    pub scale: f64,
    pub primary: bool,
}

impl Settings {
    pub fn parse(text: &str) -> Result<Self, String> {
        let mut settings: Self =
            toml::from_str(text).map_err(|e| format!("Invalid Shine configuration: {e}"))?;
        settings.decorations.inactive.clamp();
        settings.validate()?;
        settings.validate_preferences()?;
        Ok(settings)
    }
    fn validate_preferences(&self) -> Result<(), String> {
        self.browser.validate()?;
        self.clipboard.validate()?;
        self.decorations.validate()?;
        if !(0..=128).contains(&self.layout.gap) {
            return Err("Layout gap must be 0 to 128 logical pixels".into());
        }
        self.layout.default_column_width.validate()?;
        if self.animations.duration_ms > 5000 {
            return Err("Animation duration must be 0 to 5000 ms".into());
        }
        for rule in &self.window_rules {
            if rule.matcher.app_id.is_empty() {
                return Err("Window rule app_id cannot be empty".into());
            }
            rule.default_column_width.validate()?;
        }
        crate::preferences::bindings(&self.bindings, crate::input::ShortcutModifier::Super)?;
        self.input.keyboard.validate()?;
        Ok(())
    }
    pub fn validate(&self) -> Result<(), String> {
        let mut identities = BTreeSet::new();
        if self.outputs.iter().filter(|o| o.primary).count() > 1 {
            return Err("Choose only one primary output".into());
        }
        for o in &self.outputs {
            if o.name.is_empty() || o.id.as_ref().is_some_and(|id| id.is_empty()) {
                return Err("Output name/id cannot be empty".into());
            }
            if !identities.insert(o.id.as_deref().unwrap_or(&o.name)) {
                return Err("Duplicate output rule".into());
            }
            if o.scale
                .is_some_and(|s| !s.is_finite() || !(0.5..=2.0).contains(&s))
            {
                return Err("Output scale must be between 0.5 and 2.0".into());
            }
            if o.position
                .is_some_and(|p| p.iter().any(|v| v.unsigned_abs() > 100_000))
            {
                return Err("Output position must be within ±100000 logical pixels".into());
            }
            if let Some(mode) = &o.mode {
                if mode != "preferred" {
                    VideoMode::parse(mode)?;
                }
            }
        }
        Ok(())
    }
    pub fn rule(&self, info: &OutputInfo) -> Option<&OutputRule> {
        self.outputs
            .iter()
            .find(|r| r.id.as_deref() == Some(&info.id))
            .or_else(|| {
                self.outputs
                    .iter()
                    .find(|r| r.id.is_none() && r.name == info.name)
            })
    }
    pub fn edit(&mut self, info: &OutputInfo) -> &mut OutputRule {
        let index = self
            .outputs
            .iter()
            .position(|r| {
                r.id.as_deref() == Some(&info.id) || (r.id.is_none() && r.name == info.name)
            })
            .unwrap_or_else(|| {
                self.outputs.push(OutputRule {
                    id: Some(info.id.clone()),
                    name: info.name.clone(),
                    ..Default::default()
                });
                self.outputs.len() - 1
            });
        &mut self.outputs[index]
    }
    pub fn selected_mode(&self, info: &OutputInfo) -> Result<VideoMode, String> {
        let Some(text) = self
            .rule(info)
            .and_then(|r| r.mode.as_deref())
            .filter(|s| *s != "preferred")
        else {
            return Ok(info.preferred.clone());
        };
        if !info.adjustable_mode {
            return Err(format!(
                "{} preview resolution follows its host window",
                info.name
            ));
        }
        let wanted = VideoMode::parse(text)?;
        info.modes
            .iter()
            .filter(|m| {
                m.width == wanted.width
                    && m.height == wanted.height
                    && (wanted.refresh == 0 || m.refresh == wanted.refresh)
            })
            .max_by_key(|m| m.refresh)
            .cloned()
            .ok_or_else(|| format!("Unsupported mode {text} on {}", info.name))
    }
    pub fn plan(&self, infos: &[OutputInfo], default_scale: f64) -> Result<Vec<Placement>, String> {
        self.validate()?;
        let mut seen = BTreeSet::new();
        let mut plan = vec![];
        for info in infos {
            if !seen.insert(&info.id)
                && self.outputs.iter().any(|r| r.id.as_ref() == Some(&info.id))
            {
                return Err(format!(
                    "Ambiguous monitor identity {}; use connector names",
                    info.id
                ));
            }
            let rule = self.rule(info);
            let mode = self.selected_mode(info)?;
            let scale = rule.and_then(|r| r.scale).unwrap_or(default_scale);
            plan.push(Placement {
                name: info.name.clone(),
                size: (
                    (mode.width as f64 / scale).round() as i32,
                    (mode.height as f64 / scale).round() as i32,
                ),
                origin: rule
                    .and_then(|r| r.position)
                    .map(|p| (p[0], p[1]))
                    .unwrap_or((0, 0)),
                scale,
                primary: rule.is_some_and(|r| r.primary),
            });
        }
        // Append unconfigured displays to the right of the configured rightmost
        // display. Its vertical origin guarantees a shared, reachable edge.
        let mut edge = plan
            .iter()
            .enumerate()
            .filter(|(i, _)| self.rule(&infos[*i]).is_some_and(|r| r.position.is_some()))
            .map(|(_, p)| (p.origin.0 + p.size.0, p.origin.1))
            .max_by_key(|p| p.0)
            .unwrap_or((0, 0));
        for (i, p) in plan.iter_mut().enumerate() {
            if self.rule(&infos[i]).is_none_or(|r| r.position.is_none()) {
                p.origin = edge;
                edge.0 += p.size.0;
            }
        }
        validate_geometry(&plan)?;
        Ok(plan)
    }
}

pub fn validate_geometry(plan: &[Placement]) -> Result<(), String> {
    if plan.is_empty() {
        return Ok(());
    }
    let overlaps = |a: &Placement, b: &Placement| {
        a.origin.0 < b.origin.0 + b.size.0
            && b.origin.0 < a.origin.0 + a.size.0
            && a.origin.1 < b.origin.1 + b.size.1
            && b.origin.1 < a.origin.1 + a.size.1
    };
    let touches = |a: &Placement, b: &Placement| {
        ((a.origin.0 + a.size.0 == b.origin.0 || b.origin.0 + b.size.0 == a.origin.0)
            && a.origin.1 < b.origin.1 + b.size.1
            && b.origin.1 < a.origin.1 + a.size.1)
            || ((a.origin.1 + a.size.1 == b.origin.1 || b.origin.1 + b.size.1 == a.origin.1)
                && a.origin.0 < b.origin.0 + b.size.0
                && b.origin.0 < a.origin.0 + a.size.0)
    };
    let mut reached = BTreeSet::from([0]);
    for _ in 0..plan.len() {
        for i in 0..plan.len() {
            for j in 0..i {
                if overlaps(&plan[i], &plan[j]) {
                    return Err(
                        "Monitor rectangles overlap; update their positions together".into(),
                    );
                }
                if touches(&plan[i], &plan[j]) && (reached.contains(&i) || reached.contains(&j)) {
                    reached.insert(i);
                    reached.insert(j);
                }
            }
        }
    }
    if reached.len() != plan.len() {
        return Err("Monitors must share edges so the pointer can reach every screen".into());
    }
    Ok(())
}

pub struct ConfigFile {
    pub path: PathBuf,
    pub observed: Option<String>,
    pub saved: Option<String>,
}
impl ConfigFile {
    pub fn new(path: PathBuf) -> Self {
        Self {
            path,
            observed: None,
            saved: None,
        }
    }
    pub fn read(&self) -> Result<Option<String>, String> {
        match std::fs::read_to_string(&self.path) {
            Ok(text) if text.len() <= 1024 * 1024 => Ok(Some(text)),
            Ok(_) => Err("Shine configuration exceeds 1 MiB".into()),
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(None),
            Err(e) => Err(format!("Read {}: {e}", self.path.display())),
        }
    }
    pub fn save(&mut self, settings: &Settings) -> Result<(), String> {
        if self.read()? != self.saved {
            return Err("Configuration changed on disk; reload it before saving".into());
        }
        let contents = match &self.saved {
            Some(previous) => merge_output_tables(previous, settings)?,
            None => toml::to_string_pretty(settings).map_err(|e| e.to_string())?,
        };
        atomic_write(&self.path, &contents)?;
        self.observed = Some(contents.clone());
        self.saved = Some(contents);
        Ok(())
    }
}
/// Live commands currently change outputs only. Keep all handwritten preference
/// sections intact and update output values without losing their comments.
fn merge_output_tables(previous: &str, settings: &Settings) -> Result<String, String> {
    use toml_edit::{ArrayOfTables, DocumentMut, Item};
    let mut document = previous.parse::<DocumentMut>().map_err(|e| e.to_string())?;
    let replacement = toml::to_string_pretty(settings)
        .map_err(|e| e.to_string())?
        .parse::<DocumentMut>()
        .map_err(|e| e.to_string())?;
    let mut old: Vec<_> = document
        .get("outputs")
        .and_then(Item::as_array_of_tables)
        .map(|a| a.iter().cloned().collect())
        .unwrap_or_default();
    let mut array = ArrayOfTables::new();
    if let Some(outputs) = replacement
        .get("outputs")
        .and_then(Item::as_array_of_tables)
    {
        for desired in outputs {
            let id = desired.get("id").and_then(Item::as_str);
            let name = desired.get("name").and_then(Item::as_str);
            let index = old
                .iter()
                .position(|t| id.is_some() && t.get("id").and_then(Item::as_str) == id)
                .or_else(|| {
                    old.iter()
                        .position(|t| t.get("name").and_then(Item::as_str) == name)
                });
            let Some(index) = index else {
                array.push(desired.clone());
                continue;
            };
            let mut table = old.remove(index);
            let old_values: toml::Value =
                toml::from_str(&table.to_string()).map_err(|e| e.to_string())?;
            let new_values: toml::Value =
                toml::from_str(&desired.to_string()).map_err(|e| e.to_string())?;
            let obsolete: Vec<_> = table
                .iter()
                .filter(|(key, _)| !desired.contains_key(key))
                .map(|(key, _)| key.to_owned())
                .collect();
            for key in obsolete {
                table.remove(&key);
            }
            for (key, value) in desired {
                if old_values.get(key) == new_values.get(key) {
                    continue;
                }
                let mut value = value.clone();
                if let (Some(old), Some(new)) = (
                    table.get(key).and_then(Item::as_value),
                    value.as_value_mut(),
                ) {
                    *new.decor_mut() = old.decor().clone();
                }
                table.insert(key, value);
            }
            array.push(table);
        }
    }
    document["outputs"] = if array.is_empty() {
        toml_edit::value(toml_edit::Array::new())
    } else {
        Item::ArrayOfTables(array)
    };
    Ok(document.to_string())
}
fn atomic_write(path: &Path, text: &str) -> Result<(), String> {
    use std::{io::Write, os::unix::fs::OpenOptionsExt};
    if path.is_symlink() {
        return Err(
            "Configuration is a symlink; edit its source and reload instead of saving over it"
                .into(),
        );
    }
    let parent = path
        .parent()
        .filter(|p| !p.as_os_str().is_empty())
        .unwrap_or(Path::new("."));
    std::fs::create_dir_all(parent).map_err(|e| e.to_string())?;
    let temp = parent.join(format!(
        ".shine-{}-{}.tmp",
        std::process::id(),
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos()
    ));
    let result = (|| -> std::io::Result<()> {
        let mut file = std::fs::OpenOptions::new()
            .write(true)
            .create_new(true)
            .mode(0o600)
            .open(&temp)?;
        file.write_all(text.as_bytes())?;
        file.sync_all()?;
        std::fs::rename(&temp, path)?;
        Ok(())
    })();
    if result.is_err() {
        let _ = std::fs::remove_file(temp);
    }
    result.map_err(|e| format!("Save {}: {e}", path.display()))
}

/// Only a real serial yields a portable identity; anonymous/invalid EDIDs use
/// the connector, so identical displays cannot silently receive each other's rule.
pub fn edid_identity(name: &str, bytes: &[u8]) -> (String, String, String) {
    let fallback = || {
        (
            format!("connector:{name}"),
            "Unknown".into(),
            name.to_owned(),
        )
    };
    if bytes.len() < 128
        || bytes[..8] != [0, 255, 255, 255, 255, 255, 255, 0]
        || bytes[..128].iter().fold(0u8, |sum, b| sum.wrapping_add(*b)) != 0
    {
        return fallback();
    }
    let manufacturer = u16::from_be_bytes([bytes[8], bytes[9]]);
    let make: String = [10, 5, 0]
        .into_iter()
        .map(|shift| {
            let n = ((manufacturer >> shift) & 31) as u8;
            if (1..=26).contains(&n) {
                (b'A' + n - 1) as char
            } else {
                '?'
            }
        })
        .collect();
    let product = u16::from_le_bytes([bytes[10], bytes[11]]);
    let descriptor = |tag| {
        bytes[54..126]
            .chunks_exact(18)
            .find(|d| d[..3] == [0, 0, 0] && d[3] == tag)
            .map(|d| {
                String::from_utf8_lossy(&d[5..18])
                    .trim_matches(|c: char| c.is_whitespace() || c == '\0')
                    .to_owned()
            })
            .filter(|s| !s.is_empty())
    };
    let model = descriptor(0xfc).unwrap_or_else(|| format!("{product:04x}"));
    let serial = descriptor(0xff).or_else(|| {
        let n = u32::from_le_bytes(bytes[12..16].try_into().unwrap());
        (n != 0 && n != u32::MAX).then(|| n.to_string())
    });
    let id = serial
        .map(|s| format!("edid:{make}:{product:04x}:{s}"))
        .unwrap_or_else(|| format!("connector:{name}"));
    (id, make, model)
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn full_example_and_preference_validation() {
        let settings = Settings::parse(include_str!("../config.example.toml")).unwrap();
        assert_eq!(settings.window_rules.len(), 2);
        assert_eq!(settings.input.keyboard.layout.as_deref(), Some("us"));
        assert_eq!(settings.clipboard.terminal_copy, "Ctrl+Shift+C");
        for invalid in [
            "[browser]\nprogram=''",
            "[browser]\nprogram='firefox'\napp_ids=['']",
            "[browser]\nunknown=true",
            "[clipboard]\ncopy='Ctrl+NotAKeyName'",
            "[clipboard]\npaste='Mod+V'",
            "[clipboard]\nterminal_app_ids=['']",
            "[clipboard]\nunknown=true",
            "[bindings]\n'Mod+N'={action='unknown'}",
            "[bindings]\n'Mod+NotAKeyName'={action='terminal'}",
            "[bindings]\n'Mod+1'={action='workspace',value=0}",
            "[layout]\ndefault_column_width={pixels=900,proportion=0.5}",
            "[animations]\nduration_ms=5001",
            "[decorations]\ncorner_radius=129",
            "[decorations]\nfocus_ring_width=17",
            "[decorations]\ninactive_ring_width=17",
            "[decorations]\ninactive_ring_color=[0.0,nan,0.0,1.0]",
            "[decorations]\nfocus_ring_color=[1.1,0.5,0.5,1.0]",
            "[decorations]\nfocus_ring_color=[0.5,0.5,0.5,nan]",
            "[decorations.shadow]\nsoftness=0",
            "[decorations.shadow]\nsoftness=65",
            "[decorations.shadow]\nspread=65",
            "[decorations.shadow]\noffset=[-129,0]",
            "[decorations.shadow]\noffset=[0,129]",
            "[decorations.shadow]\ncolor=[0.0,0.0,0.0,1.1]",
            "[decorations.shadow]\ncolor=[0.0,nan,0.0,0.5]",
            "[decorations.shadow]\nunknown=true",
            "[decorations.inactive]\neasing='unknown'",
            "[decorations.inactive]\nscale='small'",
        ] {
            assert!(Settings::parse(invalid).is_err(), "{invalid}");
        }
    }
    #[test]
    fn inactive_numbers_clamp_without_rejecting_other_preferences() {
        let settings = Settings::parse(
            "[layout]\ngap=24\n[decorations.inactive]\nscale=0.1\nsaturation=2.0\nfog=-0.1\nfog_color=[-1.0,0.4,2.0]\nduration_ms=9000",
        ).unwrap();
        let inactive = settings.decorations.inactive;
        assert_eq!(settings.layout.gap, 24);
        assert_eq!(inactive.scale, 0.8);
        assert_eq!(inactive.saturation, 1.0);
        assert_eq!(inactive.fog, 0.0);
        assert_eq!(inactive.fog_color, [0.0, 0.4, 1.0]);
        assert_eq!(inactive.duration_ms, 5000);
        let settings = Settings::parse(
            "[decorations.inactive]\nscale=2.0\nsaturation=-1.0\nfog=2.0\nduration_ms=-20",
        )
        .unwrap();
        let inactive = settings.decorations.inactive;
        assert_eq!(inactive.scale, 1.0);
        assert_eq!(inactive.saturation, 0.0);
        assert_eq!(inactive.fog, 1.0);
        assert_eq!(inactive.duration_ms, 0);
        let settings = Settings::parse(
            "[decorations.inactive]\nscale=nan\nsaturation=nan\nfog=nan\nfog_color=[nan,inf,-inf]",
        )
        .unwrap();
        let inactive = settings.decorations.inactive;
        let defaults = crate::preferences::Inactive::default();
        assert_eq!(inactive.scale, defaults.scale);
        assert_eq!(inactive.saturation, defaults.saturation);
        assert_eq!(inactive.fog, defaults.fog);
        assert_eq!(inactive.fog_color, [defaults.fog_color[0], 1.0, 0.0]);
    }
    #[test]
    fn output_saves_preserve_handwritten_preferences_and_comments() {
        let text="# My desktop\n[[outputs]]\nname = 'DP-1' # connector\nposition = [0, 0] # placement\n\n[layout]\ngap = 24 # personal\n[bindings]\n'Mod+N' = { action = 'terminal' } # shortcut\n";
        let mut settings = Settings::parse(text).unwrap();
        settings.outputs[0].position = Some([2048, 0]);
        let saved = merge_output_tables(text, &settings).unwrap();
        for comment in [
            "# My desktop",
            "# connector",
            "# placement",
            "# personal",
            "# shortcut",
        ] {
            assert!(saved.contains(comment), "{saved}");
        }
        assert!(saved.contains("name = 'DP-1'"));
        assert_eq!(
            Settings::parse(&saved).unwrap().outputs[0].position,
            Some([2048, 0])
        );
        assert_eq!(Settings::parse(&saved).unwrap().layout.gap, 24);
    }
    fn infos() -> Vec<OutputInfo> {
        vec![
            OutputInfo::virtual_output("DP-1".into(), (2000, 1000)),
            OutputInfo::virtual_output("DP-2".into(), (1000, 1000)),
        ]
    }
    #[test]
    fn stable_identity_wins_over_an_old_connector() {
        let mut info = infos().remove(0);
        info.id = "edid:ABC:1234:serial".into();
        info.name = "DP-9".into();
        let s = Settings::parse("[[outputs]]\nname='DP-1'\nid='edid:ABC:1234:serial'\nscale=1.75")
            .unwrap();
        assert_eq!(s.rule(&info).unwrap().scale, Some(1.75));
    }
    #[test]
    fn invalid_geometry_and_unknown_keys_are_rejected() {
        for text in [
            "[[outputs]]\nname='DP-1'\nscale=0.0",
            "[[outputs]]\nname='DP-1'\nscle=1.5",
            "[[outputs]]\nname='A'\nprimary=true\n[[outputs]]\nname='B'\nprimary=true",
        ] {
            assert!(Settings::parse(text).is_err());
        }
        let s = Settings::parse(
            "[[outputs]]\nname='DP-1'\nposition=[0,0]\n[[outputs]]\nname='DP-2'\nposition=[100,0]",
        )
        .unwrap();
        assert!(s.plan(&infos(), 1.0).is_err());
    }
    #[test]
    fn negative_vertical_layouts_use_logical_sizes_and_reject_gaps() {
        let s=Settings::parse("[[outputs]]\nname='DP-1'\nposition=[-1000,-500]\nscale=2.0\n[[outputs]]\nname='DP-2'\nposition=[-1000,0]\nprimary=true").unwrap();
        let plan = s.plan(&infos(), 1.0).unwrap();
        assert_eq!(plan[0].size, (1000, 500));
        assert!(plan[1].primary);
        let mut gap = s;
        gap.outputs[1].position = Some([-1000, 1]);
        assert!(gap.plan(&infos(), 1.0).is_err());
    }
    #[test]
    fn anonymous_or_invalid_edid_does_not_guess_a_stable_id() {
        assert_eq!(edid_identity("DP-1", &[]).0, "connector:DP-1");
        let mut bytes = [0u8; 128];
        bytes[..8].copy_from_slice(&[0, 255, 255, 255, 255, 255, 255, 0]);
        bytes[127] = 0u8.wrapping_sub(bytes[..127].iter().fold(0u8, |s, b| s.wrapping_add(*b)));
        assert_eq!(edid_identity("DP-1", &bytes).0, "connector:DP-1");
        bytes[12] = 42;
        bytes[127] = 0u8.wrapping_sub(bytes[..127].iter().fold(0u8, |s, b| s.wrapping_add(*b)));
        assert_eq!(
            edid_identity("DP-1", &bytes).0,
            edid_identity("DP-9", &bytes).0
        );
    }
    #[test]
    fn saving_is_atomic_and_does_not_clobber_external_edits_or_symlinks() {
        let dir = std::env::temp_dir().join(format!(
            "shine-config-test-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        let path = dir.join("config.toml");
        let mut file = ConfigFile::new(path.clone());
        file.save(&Settings::default()).unwrap();
        let saved = file.read().unwrap().unwrap();
        assert!(Settings::parse(&saved).is_ok());
        std::fs::write(&path, "# external edit\n").unwrap();
        assert!(file.save(&Settings::default()).is_err());
        assert_eq!(std::fs::read_to_string(&path).unwrap(), "# external edit\n");
        let link = dir.join("managed.toml");
        std::os::unix::fs::symlink(&path, &link).unwrap();
        let mut file = ConfigFile::new(link.clone());
        file.saved = file.read().unwrap();
        assert!(file.save(&Settings::default()).is_err());
        assert!(link.is_symlink());
        std::fs::remove_dir_all(dir).unwrap();
    }
}
