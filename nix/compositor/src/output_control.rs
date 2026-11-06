use crate::{
    output_config::{ConfigFile, OutputInfo, Placement, Settings, VideoMode},
    Smallvil,
};
use serde::Deserialize;
use serde_json::Value;
use std::path::PathBuf;

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Change {
    name: String,
    position: Option<[i32; 2]>,
    scale: Option<f64>,
    primary: Option<bool>,
    mode: Option<String>,
    #[serde(default)]
    reset: bool,
}

impl Smallvil {
    pub fn init_output_config(&mut self, path: Option<PathBuf>) -> anyhow::Result<()> {
        let path = path.unwrap_or_else(|| {
            std::env::var_os("XDG_CONFIG_HOME")
                .map(PathBuf::from)
                .unwrap_or_else(|| {
                    PathBuf::from(std::env::var_os("HOME").unwrap_or_default()).join(".config")
                })
                .join("shine/config.toml")
        });
        self.config_file = Some(ConfigFile::new(path));
        self.configured_bindings =
            crate::preferences::bindings(&self.output_settings.bindings, self.shortcut_modifier)
                .map_err(anyhow::Error::msg)?;
        match self.read_output_config(false) {
            Ok(()) => (),
            Err(error) => {
                eprintln!("{error}; keeping the working output configuration");
                self.config_error = Some(error);
            }
        }
        Ok(())
    }
    pub fn connected_infos(&self) -> Vec<OutputInfo> {
        let mut infos: Vec<_> = self
            .space
            .outputs()
            .filter_map(|o| self.output_info.get(&o.name()).cloned())
            .collect();
        infos.sort_by(|a, b| a.name.cmp(&b.name));
        infos
    }
    pub fn primary_output(&self) -> Option<String> {
        let infos = self.connected_infos();
        infos
            .iter()
            .find(|i| self.output_settings.rule(i).is_some_and(|r| r.primary))
            .or_else(|| infos.first())
            .map(|i| i.name.clone())
    }
    fn read_output_config(&mut self, explicit: bool) -> Result<(), String> {
        let file = self.config_file.as_ref().ok_or("No configuration path")?;
        let text = file.read()?;
        if !explicit && text == file.observed {
            return Ok(());
        }
        self.config_file.as_mut().unwrap().observed = text.clone();
        let Some(text) = text else {
            if explicit || self.config_file.as_ref().unwrap().saved.is_some() {
                return Err("Shine configuration is missing; keeping the working layout".into());
            }
            return Ok(());
        };
        let settings = Settings::parse(&text)?;
        settings.plan(&self.connected_infos(), self.default_output_scale)?;
        self.apply_preferences(&settings)?;
        self.output_settings = settings;
        self.config_revision += 1;
        self.config_error = None;
        self.config_file.as_mut().unwrap().saved = Some(text);
        self.relayout();
        self.sync_focus();
        Ok(())
    }
    pub fn poll_output_config(&mut self) {
        if self.config_poll.elapsed() < std::time::Duration::from_millis(250) {
            return;
        }
        self.config_poll = std::time::Instant::now();
        if let Err(error) = self.read_output_config(false) {
            self.config_error = Some(error);
        }
        if let Err(error) = self.read_task_config(false) {
            self.task_config_error = Some(error);
        }
    }
    pub fn output_request(&mut self, action: &str, request: &Value) -> Result<(), String> {
        match action {
            "reload-config" => {
                let result = self.read_output_config(true);
                if let Err(e) = &result {
                    self.config_error = Some(e.clone());
                }
                // Reload both files even when one is invalid.
                let tasks = self.read_task_config(true);
                if let Err(error) = &tasks {
                    self.task_config_error = Some(error.clone());
                }
                result.and(tasks)
            }
            "save-config" => self.save_output_config(),
            "configure-outputs" => {
                let changes: Vec<Change> = serde_json::from_value(request["outputs"].clone())
                    .map_err(|e| format!("Invalid output changes: {e}"))?;
                if changes.is_empty() {
                    return Err("No output changes supplied".into());
                }
                let infos = self.connected_infos();
                let mut settings = self.output_settings.clone();
                for change in &changes {
                    let info = infos
                        .iter()
                        .find(|i| i.name == change.name || i.id == change.name)
                        .ok_or_else(|| format!("Output {} is not connected", change.name))?;
                    if change.reset {
                        settings.outputs.retain(|r| {
                            !(r.id.as_deref() == Some(&info.id)
                                || (r.id.is_none() && r.name == info.name))
                        });
                        continue;
                    }
                    if change.primary == Some(true) {
                        for r in &mut settings.outputs {
                            r.primary = false;
                        }
                    }
                    let rule = settings.edit(info);
                    if let Some(position) = change.position {
                        rule.position = Some(position);
                    }
                    if let Some(scale) = change.scale {
                        rule.scale = Some(scale);
                    }
                    if let Some(primary) = change.primary {
                        rule.primary = primary;
                    }
                    if let Some(mode) = &change.mode {
                        rule.mode = Some(mode.clone());
                    }
                }
                settings.validate()?;
                // Preserve shared edges for the common horizontal/vertical
                // resize case, rather than letting a scale change overlap its neighbour.
                if changes.len() == 1
                    && changes[0].position.is_none()
                    && (changes[0].scale.is_some() || changes[0].mode.is_some())
                {
                    let info = infos
                        .iter()
                        .find(|i| i.name == changes[0].name || i.id == changes[0].name)
                        .unwrap();
                    self.adjust_neighbours(&mut settings, info, &infos)?;
                }
                settings.plan(&infos, self.default_output_scale)?;
                self.output_settings = settings;
                self.config_revision += 1;
                self.config_error = None;
                self.relayout();
                self.sync_focus();
                Ok(())
            }
            _ => Err("Unknown output command".into()),
        }
    }
    fn adjust_neighbours(
        &self,
        settings: &mut Settings,
        info: &OutputInfo,
        infos: &[OutputInfo],
    ) -> Result<(), String> {
        if !settings.outputs.iter().any(|r| r.position.is_some()) {
            return Ok(());
        }
        let Some(m) = self.layout.monitors.iter().find(|m| m.name == info.name) else {
            return Ok(());
        };
        let scale = settings
            .rule(info)
            .and_then(|r| r.scale)
            .unwrap_or(self.default_output_scale);
        let mode = settings.selected_mode(info)?;
        let delta = (
            (mode.width as f64 / scale).round() as i32 - m.layout.size.0,
            (mode.height as f64 / scale).round() as i32 - m.layout.size.1,
        );
        for other in &self.layout.monitors {
            let Some(other_info) = infos.iter().find(|i| i.name == other.name) else {
                continue;
            };
            let mut position = other.origin;
            if other.name != m.name {
                if position.0 >= m.origin.0 + m.layout.size.0 {
                    position.0 += delta.0;
                }
                if position.1 >= m.origin.1 + m.layout.size.1 {
                    position.1 += delta.1;
                }
            }
            settings.edit(other_info).position = Some([position.0, position.1]);
        }
        Ok(())
    }
    fn save_output_config(&mut self) -> Result<(), String> {
        let mut settings = self.output_settings.clone();
        let infos = self.connected_infos();
        for info in &infos {
            let selected = self.output_settings.selected_mode(info)?;
            let actual = self
                .space
                .outputs()
                .find(|o| o.name() == info.name)
                .unwrap()
                .current_mode()
                .unwrap();
            if selected.size() != (actual.size.w, actual.size.h)
                || selected.refresh != actual.refresh
            {
                return Err(format!(
                    "{} mode change is pending or failed; wait for status before saving",
                    info.name
                ));
            }
        }
        let primary = self.primary_output();
        let has_primary = settings.outputs.iter().any(|r| r.primary);
        for monitor in &self.layout.monitors {
            let Some(info) = infos.iter().find(|i| i.name == monitor.name) else {
                continue;
            };
            let rule = settings.edit(info);
            rule.name = info.name.clone();
            rule.id = Some(info.id.clone());
            rule.position = Some([monitor.origin.0, monitor.origin.1]);
            rule.scale = Some(monitor.scale);
            if !has_primary {
                rule.primary = primary.as_deref() == Some(&monitor.name);
            }
        }
        settings.validate()?;
        self.config_file
            .as_mut()
            .ok_or("No configuration path")?
            .save(&settings)?;
        self.output_settings = settings;
        Ok(())
    }
    pub fn output_placements(&mut self, outputs: &[smithay::output::Output]) -> Vec<Placement> {
        let mut infos = self.connected_infos();
        for info in &mut infos {
            let mode = outputs
                .iter()
                .find(|o| o.name() == info.name)
                .unwrap()
                .current_mode()
                .unwrap();
            info.preferred = VideoMode {
                width: mode.size.w,
                height: mode.size.h,
                refresh: mode.refresh,
            };
        }
        let mut geometry = self.output_settings.clone();
        for rule in &mut geometry.outputs {
            rule.mode = None;
        }
        match geometry.plan(&infos, self.default_output_scale) {
            Ok(plan) => {
                self.layout_warning = None;
                plan
            }
            Err(error) => {
                self.layout_warning = Some(format!(
                    "{error}; temporarily arranging connected monitors side by side"
                ));
                // Retain the saved spatial order, including reversed connectors.
                infos.sort_by_key(|i| {
                    geometry
                        .rule(i)
                        .and_then(|r| r.position)
                        .map(|p| (p[0], p[1]))
                        .unwrap_or((i32::MAX, 0))
                });
                for rule in &mut geometry.outputs {
                    rule.position = None;
                }
                geometry
                    .plan(&infos, self.default_output_scale)
                    .unwrap_or_else(|_| {
                        Settings::default()
                            .plan(&infos, self.default_output_scale)
                            .unwrap()
                    })
            }
        }
    }
}
