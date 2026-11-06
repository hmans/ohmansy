//! Named task workspaces and one-time startup applications.
use serde::{Deserialize, Serialize};
use std::collections::BTreeSet;
use std::path::PathBuf;

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Settings {
    #[serde(default)]
    pub workspaces: Vec<Task>,
}

impl Settings {
    pub fn parse(text: &str) -> Result<Self, String> {
        let settings: Self = toml::from_str(text)
            .map_err(|error| format!("Invalid workspace configuration: {error}"))?;
        validate(&settings.workspaces)?;
        Ok(settings)
    }
}

pub fn valid_id(id: &str) -> bool {
    !id.is_empty()
        && id
            .bytes()
            .all(|c| c.is_ascii_alphanumeric() || b"-_".contains(&c))
}

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Task {
    pub id: String,
    pub name: String,
    #[serde(default)]
    pub apps: Vec<App>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct App {
    /// Arguments are passed directly, without a shell or tilde expansion.
    pub command: Vec<String>,
    #[serde(rename = "match")]
    pub matcher: Matcher,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Matcher {
    pub app_id: String,
    #[serde(default)]
    pub title_contains: Option<String>,
}

impl Matcher {
    pub fn matches(&self, app_id: &str, title: &str) -> bool {
        self.app_id == app_id
            && self
                .title_contains
                .as_ref()
                .is_none_or(|part| title.contains(part))
    }
}

pub fn validate(tasks: &[Task]) -> Result<(), String> {
    let mut ids = BTreeSet::new();
    for task in tasks {
        if !valid_id(&task.id) || !ids.insert(&task.id) {
            return Err(
                "Workspace IDs must be unique and contain only letters, digits, - or _".into(),
            );
        }
        if task.name.trim().is_empty() || task.name.chars().any(char::is_control) {
            return Err("Workspace names must be nonempty single-line text".into());
        }
        for app in &task.apps {
            if app.command.first().is_none_or(|s| s.is_empty())
                || app.command.iter().any(|s| s.contains('\0'))
                || app.matcher.app_id.is_empty()
                || app.matcher.app_id.contains('\0')
                || app
                    .matcher
                    .title_contains
                    .as_ref()
                    .is_some_and(|s| s.is_empty() || s.contains('\0'))
            {
                return Err("Workspace apps need a command and a nonempty app_id match, without NUL characters".into());
            }
        }
    }
    Ok(())
}

impl crate::Smallvil {
    pub fn init_task_config(&mut self, path: Option<PathBuf>) {
        let path = path.unwrap_or_else(|| {
            self.config_file
                .as_ref()
                .expect("Initialize compositor config first")
                .path
                .with_file_name("workspaces.toml")
        });
        self.task_config_file = Some(crate::output_config::ConfigFile::new(path));
        if let Err(error) = self.read_task_config(false) {
            eprintln!("{error}; keeping the working workspace configuration");
            self.task_config_error = Some(error);
        }
    }

    pub fn read_task_config(&mut self, explicit: bool) -> Result<(), String> {
        let file = self
            .task_config_file
            .as_ref()
            .ok_or("No workspace configuration path")?;
        let text = file.read()?;
        if !explicit && text == file.observed {
            return Ok(());
        }
        self.task_config_file.as_mut().unwrap().observed = text.clone();
        // A missing or empty file disables configured tasks. Existing windows
        // are retained when the desktop returns to the default workspaces.
        let settings = Settings::parse(text.as_deref().unwrap_or(""))?;
        self.task_settings = settings;
        self.task_config_error = None;
        self.task_config_revision += 1;
        self.relayout();
        self.sync_focus();
        Ok(())
    }

    pub fn focus_task(&mut self, id: &str) -> Result<(), String> {
        let index = self
            .task_settings
            .workspaces
            .iter()
            .position(|task| task.id == id)
            .ok_or_else(|| format!("Unknown workspace: {id}"))?;
        self.action("workspace", Some(index as i64 + 1))
    }

    pub fn launch_task_apps(&mut self) {
        // Called only at session startup, never by config reload or shell restart.
        for task in &self.task_settings.workspaces {
            for app in &task.apps {
                if let Err(error) =
                    crate::spawn_application(&self.socket_name, &app.command[0], &app.command[1..])
                {
                    let message = format!("{}: {error:#}", task.name);
                    eprintln!("Workspace startup: {message}");
                    self.task_startup_errors.push(message);
                }
            }
        }
    }

    pub fn apply_task_placement(
        &mut self,
        surface: &smithay::reexports::wayland_server::protocol::wl_surface::WlSurface,
    ) {
        use smithay::{
            backend::renderer::utils::RendererSurfaceStateUserData,
            wayland::{compositor::with_states, shell::xdg::XdgToplevelSurfaceData},
        };
        let Some(id) = self.window_id(surface) else {
            return;
        };
        if self.task_placement_applied.contains(&id) {
            return;
        }
        let (app_id, title, mapped) = with_states(surface, |states| {
            let metadata = states
                .data_map
                .get::<XdgToplevelSurfaceData>()
                .unwrap()
                .lock()
                .unwrap();
            let mapped = states
                .data_map
                .get::<RendererSurfaceStateUserData>()
                .is_some_and(|data| data.lock().unwrap().buffer().is_some());
            (
                metadata.app_id.clone().unwrap_or_default(),
                metadata.title.clone().unwrap_or_default(),
                mapped,
            )
        });
        // Metadata is complete by the first buffer commit. Never route an existing
        // window again when its title changes, the user moves it, or config reloads.
        if !mapped {
            return;
        }
        self.task_placement_applied.insert(id);
        let target = self.task_settings.workspaces.iter().position(|task| {
            task.apps
                .iter()
                .any(|app| app.matcher.matches(&app_id, &title))
        });
        if let Some(target) = target {
            let primary = self.primary_output();
            let monitor = self
                .layout
                .monitors
                .iter()
                .position(|m| Some(m.name.as_str()) == primary.as_deref())
                .unwrap_or(self.layout.active_monitor);
            self.layout.place_window(id, monitor, target);
            self.apply_positions();
            self.sync_focus();
        }
    }
}

#[cfg(test)]
mod tests {
    use super::Settings;

    #[test]
    fn shipped_task_example_is_valid() {
        let settings = Settings::parse(include_str!("../tasks.example.toml")).unwrap();
        assert_eq!(settings.workspaces.len(), 2);
        assert_eq!(settings.workspaces[0].apps.len(), 3);
        assert_eq!(settings.workspaces[1].apps.len(), 3);
    }

    #[test]
    fn rejects_invalid_tasks_and_accepts_empty_lists() {
        assert!(Settings::parse("").is_ok());
        assert!(Settings::parse("workspaces=[]").is_ok());
        assert!(Settings::parse("[outputs]\nname='DP-1'").is_err());
        for text in [
            "[[workspaces]]\nid='dev'\nname=''",
            "[[workspaces]]\nid='dev'\nname='Dev'\n[[workspaces]]\nid='dev'\nname='Other'",
            "[[workspaces]]\nid='../dev'\nname='Dev'",
            "[[workspaces]]\nid='dev'\nname='Dev'\n[[workspaces.apps]]\ncommand=[]\nmatch={app_id='foot'}",
            "[[workspaces]]\nid='dev'\nname='Dev'\n[[workspaces.apps]]\ncommand=['foot']\nmatch={app_id=''}",
            "[[workspaces]]\nid='dev'\nname='Dev'\n[[workspaces.apps]]\ncommand=['foot']\nmatch={app_id='foot',title_contains=''}",
        ] {
            assert!(Settings::parse(text).is_err(), "{text}");
        }
    }

    #[test]
    fn compositor_config_and_workspaces_are_separate() {
        assert!(
            crate::output_config::Settings::parse("[[workspaces]]\nid='dev'\nname='Dev'").is_err()
        );
        // Bindings remain valid while the independently loaded task file is
        // missing, invalid, or being edited. Unknown IDs fail when invoked.
        assert!(crate::output_config::Settings::parse(
            "[bindings]\n'Mod+D'={action='task',id='dev'}"
        )
        .is_ok());
        assert!(crate::output_config::Settings::parse(
            "[bindings]\n'Mod+D'={action='task',id='../dev'}"
        )
        .is_err());
    }

    #[test]
    fn matches_exact_ids_with_optional_title_filter() {
        let settings = Settings::parse("[[workspaces]]\nid='dev'\nname='Dev'\n[[workspaces.apps]]\ncommand=['foot','--title=project']\nmatch={app_id='foot',title_contains='project'}").unwrap();
        let matcher = &settings.workspaces[0].apps[0].matcher;
        assert!(matcher.matches("foot", "my project"));
        assert!(!matcher.matches("foot", "other"));
        assert!(!matcher.matches("footclient", "my project"));
    }
}
