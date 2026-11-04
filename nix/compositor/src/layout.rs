//! Window policy independent of Wayland, rendering, and input devices.

pub type WindowId = u64;

#[derive(Clone, Debug)]
pub struct Column {
    pub id: WindowId,
    pub width: i32,
    pub restore_width: Option<i32>,
}

#[derive(Default, Debug)]
pub struct Workspace {
    pub columns: Vec<Column>,
    pub focused: Option<WindowId>,
    pub scroll: f64,
    pub target: f64,
    pub fullscreen: Option<WindowId>,
    animation_target: f64,
    animation_from: f64,
    animation_elapsed: f64,
}

pub struct Layout {
    pub workspaces: Vec<Workspace>,
    pub active: usize,
    pub size: (i32, i32),
    pub gap: i32,
    pub default_width: crate::preferences::Width,
    pub animations_enabled: bool,
    pub animation_duration: f64,
}

impl Default for Layout {
    fn default() -> Self {
        Self {
            workspaces: (0..4).map(|_| Workspace::default()).collect(),
            active: 0,
            size: (1000, 700),
            gap: 12,
            default_width: Default::default(),
            animations_enabled: true,
            animation_duration: 0.18,
        }
    }
}

impl Layout {
    pub fn workspace(&self) -> &Workspace {
        &self.workspaces[self.active]
    }
    pub fn focused(&self) -> Option<WindowId> {
        self.workspace().focused
    }

    pub fn insert(&mut self, id: WindowId) {
        let width = self.default_width.resolve(self.size.0 - 2 * self.gap);
        let workspace = &mut self.workspaces[self.active];
        let index = workspace
            .focused
            .and_then(|id| workspace.columns.iter().position(|c| c.id == id))
            .map_or(workspace.columns.len(), |i| i + 1);
        workspace.columns.insert(
            index,
            Column {
                id,
                width: width.max(200),
                restore_width: None,
            },
        );
        workspace.focused = Some(id);
        workspace.fullscreen = None;
        self.reveal();
    }

    pub fn remove(&mut self, id: WindowId) {
        for workspace in &mut self.workspaces {
            let Some(index) = workspace.columns.iter().position(|column| column.id == id) else {
                continue;
            };
            let focused_index = workspace
                .focused
                .and_then(|focused| workspace.columns.iter().position(|c| c.id == focused));
            let removed = workspace.columns.remove(index);
            if focused_index.is_some_and(|focused| index < focused) {
                let shift = (removed.width + self.gap) as f64;
                workspace.scroll = (workspace.scroll - shift).max(0.0);
                workspace.target = (workspace.target - shift).max(0.0);
            }
            if workspace.focused == Some(id) {
                workspace.focused = workspace
                    .columns
                    .get(index.min(workspace.columns.len().saturating_sub(1)))
                    .map(|c| c.id);
            }
            if workspace.fullscreen == Some(id) {
                workspace.fullscreen = None;
            }
        }
        self.reveal();
    }

    pub fn focus(&mut self, id: WindowId) {
        if let Some(index) = self
            .workspaces
            .iter()
            .position(|w| w.columns.iter().any(|c| c.id == id))
        {
            self.active = index;
            let workspace = &mut self.workspaces[index];
            workspace.focused = Some(id);
            if workspace.fullscreen.is_some() {
                workspace.fullscreen = Some(id);
            }
            self.reveal();
        }
    }

    pub fn focus_delta(&mut self, delta: i32) {
        let workspace = self.workspace();
        if workspace.columns.is_empty() {
            return;
        }
        let current = workspace
            .focused
            .and_then(|id| workspace.columns.iter().position(|c| c.id == id))
            .unwrap_or(0);
        let index = (current as i32 + delta).clamp(0, workspace.columns.len() as i32 - 1) as usize;
        self.focus(workspace.columns[index].id);
    }

    pub fn resize(&mut self, delta: i32) {
        let focused = self.focused();
        let max_width = (self.size.0 * 2).max(200);
        if let Some(column) = self.workspaces[self.active]
            .columns
            .iter_mut()
            .find(|c| Some(c.id) == focused)
        {
            column.width = (column.width + delta).clamp(200, max_width);
            column.restore_width = None;
        }
        self.reveal();
    }

    pub fn reorder(&mut self, delta: i32) {
        let workspace = &mut self.workspaces[self.active];
        if let Some(index) = workspace
            .columns
            .iter()
            .position(|c| Some(c.id) == workspace.focused)
        {
            let next = (index as i32 + delta).clamp(0, workspace.columns.len() as i32 - 1) as usize;
            workspace.columns.swap(index, next);
        }
        self.reveal();
    }

    pub fn maximize(&mut self, id: WindowId, enabled: bool) {
        for workspace in &mut self.workspaces {
            if let Some(column) = workspace.columns.iter_mut().find(|column| column.id == id) {
                if enabled {
                    column.restore_width.get_or_insert(column.width);
                    column.width = (self.size.0 - 2 * self.gap).max(200);
                } else if let Some(width) = column.restore_width.take() {
                    column.width = width;
                }
            }
        }
        self.reveal();
    }

    pub fn switch_workspace(&mut self, index: usize) {
        if index < self.workspaces.len() {
            self.active = index;
            self.reveal();
        }
    }

    pub fn move_to_workspace(&mut self, index: usize) {
        if index >= self.workspaces.len() || index == self.active {
            return;
        }
        let Some(id) = self.focused() else {
            return;
        };
        let Some(column) = self
            .workspace()
            .columns
            .iter()
            .find(|c| c.id == id)
            .cloned()
        else {
            return;
        };
        self.remove(id);
        let destination = &mut self.workspaces[index];
        destination.columns.push(column);
        destination.focused = Some(id);
    }

    pub fn toggle_fullscreen(&mut self) {
        let workspace = &mut self.workspaces[self.active];
        workspace.fullscreen = if workspace.fullscreen.is_some() {
            None
        } else {
            workspace.focused
        };
    }

    pub fn set_size(&mut self, size: (i32, i32)) {
        self.size = (size.0.max(1), size.1.max(1));
        for workspace in &mut self.workspaces {
            for column in &mut workspace.columns {
                if column.restore_width.is_some() {
                    column.width = (self.size.0 - 2 * self.gap).max(200);
                }
            }
        }
        self.reveal();
    }

    pub fn set_width(&mut self, id: WindowId, width: i32) {
        for workspace in &mut self.workspaces {
            if let Some(column) = workspace.columns.iter_mut().find(|column| column.id == id) {
                column.width = width.max(200);
                column.restore_width = None;
            }
        }
        self.reveal();
    }

    pub fn constrain_width(&mut self, id: WindowId, minimum: i32, maximum: i32) -> bool {
        let mut changed = false;
        for workspace in &mut self.workspaces {
            if let Some(column) = workspace.columns.iter_mut().find(|column| column.id == id) {
                let minimum = minimum.max(200);
                let maximum = if maximum <= 0 {
                    i32::MAX
                } else {
                    maximum.max(minimum)
                };
                let width = column.width.clamp(minimum, maximum);
                changed |= width != column.width;
                column.width = width;
            }
        }
        if changed {
            self.reveal();
        }
        changed
    }

    pub fn geometries(&self) -> Vec<(WindowId, i32, i32, i32, i32)> {
        let workspace = self.workspace();
        if let Some(id) = workspace.fullscreen {
            return vec![(id, 0, 0, self.size.0, self.size.1)];
        }
        let mut x = self.gap;
        workspace
            .columns
            .iter()
            .map(|column| {
                let geometry = (
                    column.id,
                    x - workspace.scroll.round() as i32,
                    self.gap,
                    column.width,
                    (self.size.1 - 2 * self.gap).max(1),
                );
                x += column.width + self.gap;
                geometry
            })
            .collect()
    }

    pub fn tick(&mut self, seconds: f64) -> bool {
        let workspace = &mut self.workspaces[self.active];
        let previous = workspace.scroll;
        if workspace.animation_target != workspace.target {
            workspace.animation_target = workspace.target;
            workspace.animation_from = previous;
            workspace.animation_elapsed = 0.0;
        }
        workspace.animation_elapsed += seconds.max(0.0);
        workspace.scroll = if !self.animations_enabled
            || self.animation_duration == 0.0
            || workspace.animation_elapsed >= self.animation_duration
        {
            workspace.target
        } else {
            let progress = (workspace.animation_elapsed / self.animation_duration).clamp(0.0, 1.0);
            workspace.animation_from
                + (workspace.target - workspace.animation_from) * (1.0 - (1.0 - progress).powi(3))
        };
        workspace.scroll != previous
    }

    fn reveal(&mut self) {
        let workspace = &mut self.workspaces[self.active];
        let mut left = self.gap as f64;
        let mut focused_bounds = None;
        for column in &workspace.columns {
            if Some(column.id) == workspace.focused {
                focused_bounds = Some((left, left + column.width as f64));
            }
            left += (column.width + self.gap) as f64;
        }
        let max_scroll = (left - self.size.0 as f64).max(0.0);
        if let Some((left, right)) = focused_bounds {
            if right - left >= (self.size.0 - 2 * self.gap) as f64
                || left < workspace.target + self.gap as f64
            {
                workspace.target = left - self.gap as f64;
            } else if right > workspace.target + (self.size.0 - self.gap) as f64 {
                workspace.target = right - (self.size.0 - self.gap) as f64;
            }
        }
        workspace.target = workspace.target.clamp(0.0, max_scroll);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn animation_duration_and_disable_are_exact() {
        let mut layout = Layout {
            animation_duration: 0.1,
            ..Default::default()
        };
        for id in 1..=5 {
            layout.insert(id);
        }
        let target = layout.workspace().target;
        assert!(target > 0.0);
        layout.tick(0.05);
        assert!(layout.workspace().scroll > 0.0 && layout.workspace().scroll < target);
        layout.tick(0.05);
        assert_eq!(layout.workspace().scroll, target);
        layout.focus_delta(-4);
        layout.animations_enabled = false;
        layout.tick(0.0);
        assert_eq!(layout.workspace().scroll, layout.workspace().target);
    }

    #[test]
    fn maximize_tracks_output_size_and_restores_its_own_column() {
        let mut layout = Layout::default();
        layout.insert(1);
        layout.insert(2);
        let width = layout.workspace().columns[1].width;
        layout.maximize(2, true);
        assert_eq!(layout.workspace().columns[1].width, 976);
        assert_eq!(layout.workspace().columns[0].width, width);
        layout.set_size((800, 600));
        assert_eq!(layout.workspace().columns[1].width, 776);
        layout.maximize(2, false);
        assert_eq!(layout.workspace().columns[1].width, width);
        assert_eq!(layout.workspace().fullscreen, None);
    }

    #[test]
    fn client_constraints_do_not_resize_neighbors() {
        let mut layout = Layout::default();
        layout.insert(1);
        layout.insert(2);
        let neighbor = layout.workspace().columns[0].width;
        layout.set_width(2, 250);
        assert!(layout.constrain_width(2, 450, 0));
        assert_eq!(layout.workspace().columns[1].width, 450);
        assert_eq!(layout.workspace().columns[0].width, neighbor);
    }

    #[test]
    fn opening_ten_columns_preserves_widths_and_reveals_focus() {
        let mut layout = Layout::default();
        layout.insert(1);
        let width = layout.workspace().columns[0].width;
        for id in 2..=10 {
            layout.insert(id);
        }
        assert!(layout
            .workspace()
            .columns
            .iter()
            .all(|column| column.width == width));
        for _ in 0..120 {
            layout.tick(1.0 / 60.0);
        }
        let (_, x, _, width, _) = *layout.geometries().last().unwrap();
        assert!(x >= layout.gap && x + width <= layout.size.0 - layout.gap + 1);
        assert!(layout.workspace().scroll > 0.0);
    }

    #[test]
    fn navigation_and_stacking_do_not_reorder_columns() {
        let mut layout = Layout::default();
        for id in 1..=4 {
            layout.insert(id);
        }
        layout.focus_delta(-2);
        assert_eq!(layout.focused(), Some(2));
        assert_eq!(
            layout
                .workspace()
                .columns
                .iter()
                .map(|c| c.id)
                .collect::<Vec<_>>(),
            vec![1, 2, 3, 4]
        );
        layout.resize(80);
        assert_eq!(
            layout.workspace().columns[1].width,
            layout.workspace().columns[0].width + 80
        );
    }

    #[test]
    fn removing_a_column_on_the_left_preserves_focused_screen_position() {
        let mut layout = Layout::default();
        for id in 1..=4 {
            layout.insert(id);
        }
        for _ in 0..120 {
            layout.tick(1.0 / 60.0);
        }
        let before = layout.geometries().last().unwrap().1;
        layout.remove(1);
        assert_eq!(layout.geometries().last().unwrap().1, before);
        assert_eq!(layout.focused(), Some(4));
    }

    #[test]
    fn workspaces_keep_widths_focus_and_fullscreen_independent() {
        let mut layout = Layout::default();
        layout.insert(1);
        layout.insert(2);
        let width = layout.workspace().columns[1].width;
        layout.move_to_workspace(1);
        assert_eq!(layout.focused(), Some(1));
        layout.switch_workspace(1);
        assert_eq!(layout.focused(), Some(2));
        assert_eq!(layout.workspace().columns[0].width, width);
        layout.toggle_fullscreen();
        assert_eq!(layout.geometries(), vec![(2, 0, 0, 1000, 700)]);
        layout.switch_workspace(0);
        assert_eq!(layout.workspace().fullscreen, None);
    }
}
