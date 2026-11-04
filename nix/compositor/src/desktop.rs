//! Independent scrolling workspaces on each monitor.
use crate::layout::{Layout, WindowId};
use std::ops::{Deref, DerefMut};

pub struct Monitor {
    pub name: String,
    pub origin: (i32, i32),
    pub physical_size: (i32, i32),
    pub scale: f64,
    pub layout: Layout,
}

pub struct Desktop {
    pub monitors: Vec<Monitor>,
    pub active_monitor: usize,
}

impl Default for Desktop {
    fn default() -> Self {
        Self {
            monitors: vec![Monitor {
                name: "pending".into(),
                origin: (0, 0),
                physical_size: (1250, 875),
                scale: 1.25,
                layout: Layout::default(),
            }],
            active_monitor: 0,
        }
    }
}

impl Deref for Desktop {
    type Target = Layout;
    fn deref(&self) -> &Layout {
        &self.monitors[self.active_monitor].layout
    }
}
impl DerefMut for Desktop {
    fn deref_mut(&mut self) -> &mut Layout {
        &mut self.monitors[self.active_monitor].layout
    }
}

impl Desktop {
    pub fn current(&self) -> &Monitor {
        &self.monitors[self.active_monitor]
    }

    #[cfg(test)]
    pub fn sync(&mut self, mut specs: Vec<(String, (i32, i32), f64)>) {
        self.sync_primary(std::mem::take(&mut specs), None);
    }

    pub fn sync_primary(
        &mut self,
        mut specs: Vec<(String, (i32, i32), f64)>,
        primary: Option<&str>,
    ) {
        if specs.is_empty() {
            return;
        }
        specs.sort_by(|a, b| a.0.cmp(&b.0));
        let active_name = self.current().name.clone();
        let active_window = self.focused();
        let mut old = std::mem::take(&mut self.monitors);
        let mut x = 0;
        for (name, physical_size, scale) in specs {
            let mut monitor = if let Some(index) = old.iter().position(|m| m.name == name) {
                old.remove(index)
            } else {
                Monitor {
                    name,
                    origin: (0, 0),
                    physical_size,
                    scale,
                    layout: Layout::default(),
                }
            };
            monitor.origin = (x, 0);
            monitor.physical_size = physical_size;
            monitor.scale = scale;
            monitor.layout.set_size((
                (physical_size.0 as f64 / scale).round() as i32,
                (physical_size.1 as f64 / scale).round() as i32,
            ));
            x += monitor.layout.size.0;
            self.monitors.push(monitor);
        }
        self.active_monitor = self
            .monitors
            .iter()
            .position(|m| m.name == active_name)
            .or_else(|| {
                self.monitors
                    .iter()
                    .position(|m| Some(m.name.as_str()) == primary)
            })
            .unwrap_or(0);
        // Unplugging a display never destroys its windows or column widths.
        for removed in old {
            for (index, workspace) in removed.layout.workspaces.into_iter().enumerate() {
                let target = &mut self.monitors[self.active_monitor].layout.workspaces[index];
                target.columns.extend(workspace.columns);
                if target.focused.is_none() {
                    target.focused = workspace.focused;
                }
            }
        }
        if let Some(id) = active_window {
            self.focus(id);
        }
    }

    pub fn owner(&self, id: WindowId) -> Option<usize> {
        self.monitors.iter().position(|m| {
            m.layout
                .workspaces
                .iter()
                .any(|w| w.columns.iter().any(|c| c.id == id))
        })
    }
    pub fn focus(&mut self, id: WindowId) {
        if let Some(index) = self.owner(id) {
            self.active_monitor = index;
            self.monitors[index].layout.focus(id);
        }
    }
    pub fn focus_monitor(&mut self, index: usize) {
        if index < self.monitors.len() {
            self.active_monitor = index;
        }
    }
    pub fn monitor_delta(&mut self, delta: i32, move_window: bool) {
        let index =
            (self.active_monitor as i32 + delta).rem_euclid(self.monitors.len() as i32) as usize;
        if move_window {
            self.move_to_monitor(index);
        } else {
            self.focus_monitor(index);
        }
    }
    pub fn move_to_monitor(&mut self, index: usize) {
        if index >= self.monitors.len() || index == self.active_monitor {
            return;
        }
        let Some(id) = self.focused() else {
            self.active_monitor = index;
            return;
        };
        let column = self
            .workspace()
            .columns
            .iter()
            .find(|c| c.id == id)
            .unwrap()
            .clone();
        self.monitors[self.active_monitor].layout.remove(id);
        self.active_monitor = index;
        let target = &mut self.monitors[index].layout;
        target.insert(id);
        target.set_width(id, column.width);
        if let Some(restore) = column.restore_width {
            target.maximize(id, true);
            target.workspaces[target.active]
                .columns
                .iter_mut()
                .find(|c| c.id == id)
                .unwrap()
                .restore_width = Some(restore);
        }
    }
    pub fn remove(&mut self, id: WindowId) {
        for m in &mut self.monitors {
            m.layout.remove(id);
        }
    }
    pub fn constrain_width(&mut self, id: WindowId, min: i32, max: i32) {
        if let Some(index) = self.owner(id) {
            self.monitors[index].layout.constrain_width(id, min, max);
        }
    }
    pub fn set_width(&mut self, id: WindowId, width: i32) {
        if let Some(index) = self.owner(id) {
            self.monitors[index].layout.set_width(id, width);
        }
    }
    pub fn maximize(&mut self, id: WindowId, enabled: bool) {
        if let Some(index) = self.owner(id) {
            self.monitors[index].layout.maximize(id, enabled);
        }
    }
    pub fn fullscreen_for(&self, id: WindowId) -> bool {
        self.owner(id)
            .is_some_and(|i| self.monitors[i].layout.workspace().fullscreen == Some(id))
    }
    pub fn maximized_for(&self, id: WindowId) -> bool {
        self.owner(id).is_some_and(|i| {
            self.monitors[i]
                .layout
                .workspace()
                .columns
                .iter()
                .any(|c| c.id == id && c.restore_width.is_some())
        })
    }
    pub fn geometries(&self) -> Vec<(WindowId, i32, i32, i32, i32)> {
        self.monitors
            .iter()
            .flat_map(|m| {
                m.layout
                    .geometries()
                    .into_iter()
                    .map(|(id, x, y, w, h)| (id, x + m.origin.0, y + m.origin.1, w, h))
            })
            .collect()
    }
    pub fn tick(&mut self, seconds: f64) -> bool {
        let mut changed = false;
        for m in &mut self.monitors {
            changed |= m.layout.tick(seconds);
        }
        changed
    }
    pub fn at(&self, x: f64, y: f64) -> Option<usize> {
        self.monitors.iter().position(|m| {
            x >= m.origin.0 as f64
                && y >= m.origin.1 as f64
                && x < (m.origin.0 + m.layout.size.0) as f64
                && y < (m.origin.1 + m.layout.size.1) as f64
        })
    }
    pub fn clamp(&self, x: f64, y: f64) -> (f64, f64) {
        self.monitors
            .iter()
            .map(|m| {
                let px = x.clamp(m.origin.0 as f64, (m.origin.0 + m.layout.size.0 - 1) as f64);
                let py = y.clamp(m.origin.1 as f64, (m.origin.1 + m.layout.size.1 - 1) as f64);
                ((px - x).powi(2) + (py - y).powi(2), (px, py))
            })
            .min_by(|a, b| a.0.total_cmp(&b.0))
            .unwrap()
            .1
    }
    pub fn canvas_point(&self, x: f64, y: f64) -> (f64, f64) {
        let mut left = 0;
        for m in &self.monitors {
            if x < (left + m.physical_size.0) as f64 {
                return self.clamp(
                    m.origin.0 as f64 + (x - left as f64) / m.scale,
                    m.origin.1 as f64 + y / m.scale,
                );
            }
            left += m.physical_size.0;
        }
        let last = self.monitors.last().unwrap();
        self.clamp((last.origin.0 + last.layout.size.0 - 1) as f64, y)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    fn two() -> Desktop {
        let mut d = Desktop::default();
        d.sync(vec![
            ("DP-1".into(), (3440, 1440), 1.25),
            ("DP-2".into(), (2560, 1440), 2.0),
        ]);
        d
    }
    #[test]
    fn monitors_keep_workspaces_widths_and_fullscreen_independent() {
        let mut d = two();
        d.insert(1);
        let width = d.workspace().columns[0].width;
        d.toggle_fullscreen();
        d.focus_monitor(1);
        d.insert(2);
        d.switch_workspace(1);
        d.insert(3);
        assert_eq!(d.monitors[0].layout.workspace().fullscreen, Some(1));
        d.focus(1);
        assert_eq!(d.active_monitor, 0);
        assert_eq!(d.workspace().columns[0].width, width);
        assert!(d.geometries().iter().any(|g| g.0 == 3 && g.1 >= 2752));
    }
    #[test]
    fn moving_between_monitors_preserves_column_width() {
        let mut d = two();
        d.insert(1);
        d.resize(50);
        let width = d.workspace().columns[0].width;
        d.move_to_monitor(1);
        assert_eq!(d.owner(1), Some(1));
        assert_eq!(d.workspace().columns[0].width, width);
        assert!(d.monitors[0].layout.workspace().columns.is_empty());
    }
    #[test]
    fn unplug_preserves_windows_and_active_focus() {
        let mut d = two();
        d.insert(1);
        d.focus_monitor(1);
        d.insert(2);
        d.sync(vec![("DP-1".into(), (3440, 1440), 1.25)]);
        assert_eq!(d.focused(), Some(2));
        assert_eq!(d.owner(1), Some(0));
        assert_eq!(d.owner(2), Some(0));
    }
    #[test]
    fn mixed_scale_pointer_mapping_and_short_monitor_edges() {
        let d = two();
        assert_eq!(d.canvas_point(3640.0, 200.0), (2852.0, 100.0));
        assert_eq!(d.at(2800.0, 900.0), None);
        assert_eq!(d.clamp(2800.0, 900.0), (2751.0, 900.0));
    }
}
