//! Window policy independent of Wayland, rendering, and input devices.
use std::collections::BTreeMap;

pub type WindowId = u64;

#[derive(Clone, Copy, Debug)]
struct Movement {
    from: f64,
    elapsed: f64,
}
impl Movement {
    fn offset(self, duration: f64) -> f64 {
        self.from * (1.0 - self.elapsed / duration).clamp(0.0, 1.0).powi(3)
    }
}

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
    movements: BTreeMap<WindowId, Movement>,
}

pub struct Layout {
    pub workspaces: Vec<Workspace>,
    pub active: usize,
    pub size: (i32, i32),
    pub work_area: (i32, i32, i32, i32),
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
            work_area: (0, 0, 1000, 700),
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
        self.finish_movements();
        let width = self.default_width.resolve(self.work_area.2 - 2 * self.gap);
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
        self.finish_movements();
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
            if self.active != index {
                self.finish_movements();
            }
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
        self.finish_movements();
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
        let workspace = self.workspace();
        if let Some(index) = workspace
            .columns
            .iter()
            .position(|c| Some(c.id) == workspace.focused)
        {
            let next = (index as i32 + delta).clamp(0, workspace.columns.len() as i32 - 1) as usize;
            if index == next {
                return;
            }
            let animate = self.animations_enabled
                && self.animation_duration > 0.0
                && workspace.fullscreen.is_none();
            let affected = [workspace.columns[index].id, workspace.columns[next].id];
            let mut x = self.gap as f64;
            let before: BTreeMap<_, _> = workspace
                .columns
                .iter()
                .map(|column| {
                    let offset = if animate {
                        workspace
                            .movements
                            .get(&column.id)
                            .map_or(0.0, |m| m.offset(self.animation_duration))
                    } else {
                        0.0
                    };
                    let position = x + offset;
                    x += (column.width + self.gap) as f64;
                    (column.id, position)
                })
                .collect();
            let workspace = &mut self.workspaces[self.active];
            workspace.columns.swap(index, next);
            if animate {
                let mut x = self.gap as f64;
                for column in &workspace.columns {
                    if affected.contains(&column.id) {
                        let from = before[&column.id] - x;
                        if from.abs() < 1e-6 {
                            workspace.movements.remove(&column.id);
                        } else {
                            workspace
                                .movements
                                .insert(column.id, Movement { from, elapsed: 0.0 });
                        }
                    }
                    x += (column.width + self.gap) as f64;
                }
            } else {
                workspace.movements.clear();
            }
            self.reveal();
            // The viewport and the reordered columns start from the same frame.
            let workspace = &mut self.workspaces[self.active];
            workspace.animation_from = workspace.scroll;
            workspace.animation_target = workspace.target;
            workspace.animation_elapsed = 0.0;
        }
    }

    pub fn finish_movements(&mut self) {
        for workspace in &mut self.workspaces {
            workspace.movements.clear();
        }
    }

    pub fn is_moving(&self, id: WindowId) -> bool {
        self.animations_enabled
            && self.animation_duration > 0.0
            && self.workspace().fullscreen.is_none()
            && self.workspace().movements.contains_key(&id)
    }

    pub fn cycle_width(&mut self, reverse: bool, minimum: i32, maximum: i32) {
        let Some(id) = self.focused() else {
            return;
        };
        let minimum = minimum.max(200);
        let maximum = if maximum <= 0 {
            i32::MAX
        } else {
            maximum.max(minimum)
        };
        let available = (self.work_area.2 - 2 * self.gap).max(1);
        let mut presets: Vec<_> = [1.0 / 3.0, 0.5, 2.0 / 3.0]
            .into_iter()
            .map(|fraction| ((available as f64 * fraction).round() as i32).clamp(minimum, maximum))
            .collect();
        presets.dedup();
        let current = self
            .workspace()
            .columns
            .iter()
            .find(|c| c.id == id)
            .unwrap()
            .width;
        let width = if reverse {
            presets
                .iter()
                .rev()
                .copied()
                .find(|width| *width < current)
                .unwrap_or(*presets.last().unwrap())
        } else {
            presets
                .iter()
                .copied()
                .find(|width| *width > current)
                .unwrap_or(presets[0])
        };
        self.set_width(id, width);
    }

    pub fn toggle_maximize(&mut self) {
        let Some(column) = self
            .workspace()
            .columns
            .iter()
            .find(|c| Some(c.id) == self.focused())
        else {
            return;
        };
        self.maximize(column.id, column.restore_width.is_none());
    }

    pub fn maximize(&mut self, id: WindowId, enabled: bool) {
        self.finish_movements();
        for workspace in &mut self.workspaces {
            if let Some(column) = workspace.columns.iter_mut().find(|column| column.id == id) {
                if enabled {
                    column.restore_width.get_or_insert(column.width);
                    column.width = (self.work_area.2 - 2 * self.gap).max(200);
                } else if let Some(width) = column.restore_width.take() {
                    column.width = width;
                }
            }
        }
        self.reveal();
    }

    pub fn cycle_workspace(&mut self, reverse: bool) {
        let count = self.workspaces.len();
        let next = if reverse {
            (self.active + count - 1) % count
        } else {
            (self.active + 1) % count
        };
        self.switch_workspace(next);
    }

    pub fn switch_workspace(&mut self, index: usize) {
        if index < self.workspaces.len() {
            if index != self.active {
                self.finish_movements();
            }
            self.active = index;
            self.reveal();
        }
    }

    pub fn move_to_adjacent_workspace(&mut self, reverse: bool) {
        let count = self.workspaces.len();
        let next = if reverse {
            (self.active + count - 1) % count
        } else {
            (self.active + 1) % count
        };
        self.move_to_workspace(next);
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
        self.finish_movements();
        let workspace = &mut self.workspaces[self.active];
        workspace.fullscreen = if workspace.fullscreen.is_some() {
            None
        } else {
            workspace.focused
        };
    }

    pub fn set_size(&mut self, size: (i32, i32)) {
        self.size = (size.0.max(1), size.1.max(1));
        self.set_work_area((0, 0, self.size.0, self.size.1));
    }

    pub fn set_work_area(&mut self, area: (i32, i32, i32, i32)) {
        if self.work_area != area {
            self.finish_movements();
        }
        self.work_area = area;
        for workspace in &mut self.workspaces {
            for column in &mut workspace.columns {
                if column.restore_width.is_some() {
                    column.width = (self.work_area.2 - 2 * self.gap).max(200);
                }
            }
        }
        self.reveal();
    }

    pub fn set_width(&mut self, id: WindowId, width: i32) {
        self.finish_movements();
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
            self.finish_movements();
            self.reveal();
        }
        changed
    }

    pub fn geometries(&self) -> Vec<(WindowId, i32, i32, i32, i32)> {
        self.geometries_at(true)
    }

    pub fn target_geometries(&self) -> Vec<(WindowId, i32, i32, i32, i32)> {
        self.geometries_at(false)
    }

    fn geometries_at(&self, visual: bool) -> Vec<(WindowId, i32, i32, i32, i32)> {
        let workspace = self.workspace();
        if let Some(id) = workspace.fullscreen {
            return vec![(id, 0, 0, self.size.0, self.size.1)];
        }
        let mut x = self.gap;
        let animated = visual && self.animations_enabled && self.animation_duration > 0.0;
        let scroll = if animated {
            workspace.scroll
        } else {
            workspace.target
        };
        workspace
            .columns
            .iter()
            .map(|column| {
                let offset = if animated {
                    workspace
                        .movements
                        .get(&column.id)
                        .map_or(0.0, |m| m.offset(self.animation_duration))
                } else {
                    0.0
                };
                let geometry = (
                    column.id,
                    self.work_area.0 + x + offset.round() as i32 - scroll.round() as i32,
                    self.work_area.1 + self.gap,
                    column.width,
                    (self.work_area.3 - 2 * self.gap).max(1),
                );
                x += column.width + self.gap;
                geometry
            })
            .collect()
    }

    pub fn tick(&mut self, seconds: f64) -> bool {
        let workspace = &mut self.workspaces[self.active];
        let moving = !workspace.movements.is_empty();
        if !self.animations_enabled || self.animation_duration == 0.0 {
            workspace.movements.clear();
        } else {
            workspace.movements.retain(|_, movement| {
                movement.elapsed += seconds.max(0.0);
                movement.elapsed < self.animation_duration
            });
        }
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
        workspace.scroll != previous || moving
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
        let max_scroll = (left - self.work_area.2 as f64).max(0.0);
        if let Some((left, right)) = focused_bounds {
            if right - left >= (self.work_area.2 - 2 * self.gap) as f64
                || left < workspace.target + self.gap as f64
            {
                workspace.target = left - self.gap as f64;
            } else if right > workspace.target + (self.work_area.2 - self.gap) as f64 {
                workspace.target = right - (self.work_area.2 - self.gap) as f64;
            }
        }
        workspace.target = workspace.target.clamp(0.0, max_scroll);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn movement_layout(width: i32) -> Layout {
        let mut layout = Layout {
            animation_duration: 1.0,
            ..Default::default()
        };
        layout.set_size((width, 700));
        for id in 1..=3 {
            layout.insert(id);
            layout.set_width(id, 300);
        }
        layout.focus(1);
        layout.tick(1.0);
        layout
    }

    #[test]
    fn reordering_animates_both_columns_without_changing_widths_or_focus() {
        let mut layout = movement_layout(1100);
        let before = layout.geometries();
        layout.reorder(1);
        assert_eq!(layout.focused(), Some(1));
        assert_eq!(
            layout.geometries().into_iter().find(|g| g.0 == 1),
            before.iter().copied().find(|g| g.0 == 1)
        );
        assert!(layout.is_moving(1) && layout.is_moving(2));
        assert!(!layout.is_moving(3));
        assert_eq!(
            layout
                .workspace()
                .columns
                .iter()
                .map(|c| c.id)
                .collect::<Vec<_>>(),
            vec![2, 1, 3]
        );
        let target = layout.target_geometries();
        assert!(layout.tick(0.5));
        for id in [1, 2] {
            let start = before.iter().find(|g| g.0 == id).unwrap();
            let end = target.iter().find(|g| g.0 == id).unwrap();
            let current = layout.geometries().into_iter().find(|g| g.0 == id).unwrap();
            assert!(current.1 > start.1.min(end.1) && current.1 < start.1.max(end.1));
            assert_eq!((current.3, current.4), (start.3, start.4));
        }
        assert!(layout.tick(0.5));
        assert_eq!(layout.geometries(), target);
        assert!(!layout.is_moving(1) && !layout.tick(0.1));
    }

    #[test]
    fn interrupted_moves_preserve_visible_positions_and_finish_at_the_new_order() {
        let mut layout = movement_layout(1100);
        layout.reorder(1);
        layout.tick(0.2);
        let before = layout.geometries();
        layout.reorder(-1);
        for old in before {
            assert_eq!(
                layout
                    .geometries()
                    .into_iter()
                    .find(|g| g.0 == old.0)
                    .unwrap(),
                old
            );
        }
        layout.tick(0.2);
        let before = layout.geometries();
        layout.reorder(1);
        for old in before {
            assert_eq!(
                layout
                    .geometries()
                    .into_iter()
                    .find(|g| g.0 == old.0)
                    .unwrap(),
                old
            );
        }
        layout.tick(1.0);
        assert_eq!(layout.geometries(), layout.target_geometries());
        assert_eq!(layout.focused(), Some(1));
    }

    #[test]
    fn reorder_and_viewport_scroll_share_progress() {
        let mut layout = movement_layout(500);
        let before = layout.geometries();
        layout.reorder(1);
        let target = layout.target_geometries();
        assert!(layout.workspace().target > 0.0);
        layout.tick(0.5);
        for current in layout.geometries() {
            let start = before.iter().find(|g| g.0 == current.0).unwrap().1;
            let end = target.iter().find(|g| g.0 == current.0).unwrap().1;
            assert!(
                (current.1 as f64 - (start as f64 + (end - start) as f64 * 0.875)).abs() <= 1.0
            );
        }
        layout.tick(0.5);
        assert_eq!(layout.geometries(), target);
    }

    #[test]
    fn moves_snap_when_disabled_and_clear_on_other_layout_changes() {
        let mut layout = movement_layout(1100);
        layout.reorder(1);
        layout.animations_enabled = false;
        assert_eq!(layout.geometries(), layout.target_geometries());
        layout.tick(0.0);
        assert!(layout.workspace().movements.is_empty());
        layout.animations_enabled = true;
        layout.animation_duration = 0.0;
        layout.reorder(-1);
        assert_eq!(layout.geometries(), layout.target_geometries());
        assert!(layout.workspace().movements.is_empty());
        layout.animation_duration = 1.0;
        layout.reorder(1);
        layout.resize(20);
        assert!(layout.workspace().movements.is_empty());
        layout.reorder(-1);
        layout.toggle_fullscreen();
        assert!(layout.workspace().movements.is_empty());
        assert_eq!(layout.geometries(), vec![(1, 0, 0, 1100, 700)]);
        layout.toggle_fullscreen();
        layout.reorder(1);
        layout.switch_workspace(1);
        layout.switch_workspace(0);
        assert!(layout.workspace().movements.is_empty());
        layout.reorder(-1);
        layout.remove(2);
        assert!(layout.workspace().movements.is_empty());
    }

    #[test]
    fn width_cycle_wraps_in_both_directions_and_uses_the_work_area() {
        let mut layout = Layout::default();
        layout.set_size((1000, 700));
        layout.insert(1);
        layout.set_width(1, 300);
        for width in [325, 488, 651, 325] {
            layout.cycle_width(false, 0, 0);
            assert_eq!(layout.geometries()[0].3, width);
        }
        for width in [651, 488, 325] {
            layout.cycle_width(true, 0, 0);
            assert_eq!(layout.geometries()[0].3, width);
        }
        layout.set_work_area((40, 44, 800, 600));
        layout.cycle_width(false, 0, 0);
        assert_eq!(layout.geometries()[0].3, 388);
        layout.maximize(1, true);
        layout.cycle_width(false, 0, 0);
        assert_eq!(layout.geometries()[0].3, 259);
        assert!(layout.workspace().columns[0].restore_width.is_none());
    }

    #[test]
    fn full_width_toggle_restores_each_windows_width_and_preserves_panels() {
        let mut layout = Layout::default();
        layout.toggle_maximize(); // Empty workspace.
        layout.set_size((1000, 700));
        layout.set_work_area((0, 40, 1000, 660));
        layout.insert(1);
        layout.set_width(1, 420);
        layout.insert(2);
        layout.set_width(2, 600);
        layout.toggle_maximize();
        assert_eq!(
            layout.geometries().iter().find(|c| c.0 == 2).unwrap().3,
            976
        );
        assert_eq!(layout.geometries().iter().find(|c| c.0 == 2).unwrap().2, 52);
        assert_eq!(layout.workspace().fullscreen, None);
        layout.focus(1);
        layout.toggle_maximize();
        layout.toggle_maximize();
        assert_eq!(layout.workspace().columns[0].width, 420);
        layout.focus(2);
        layout.toggle_fullscreen();
        assert_eq!(layout.geometries(), vec![(2, 0, 0, 1000, 700)]);
        layout.toggle_fullscreen();
        layout.toggle_maximize();
        assert_eq!(layout.workspace().columns[1].width, 600);
        layout.toggle_maximize();
        layout.resize(-80);
        layout.toggle_maximize();
        layout.toggle_maximize();
        assert_eq!(layout.workspace().columns[1].width, 896);
    }

    #[test]
    fn width_cycle_skips_unreachable_client_sizes_and_duplicate_presets() {
        let mut layout = Layout::default();
        layout.cycle_width(false, 0, 0); // Empty workspace.
        layout.set_size((1000, 700));
        layout.insert(1);
        layout.set_width(1, 500);
        for width in [400, 488, 500, 400] {
            layout.cycle_width(false, 400, 500);
            assert_eq!(layout.geometries()[0].3, width);
        }
        layout.cycle_width(true, 400, 500);
        assert_eq!(layout.geometries()[0].3, 500);
        layout.set_work_area((0, 0, 240, 600));
        for reverse in [false, true] {
            layout.cycle_width(reverse, 0, 0);
            assert_eq!(layout.geometries()[0].3, 200);
        }
    }

    #[test]
    fn panels_reserve_space_but_fullscreen_uses_the_output() {
        let mut layout = Layout::default();
        layout.set_size((1000, 700));
        layout.set_work_area((20, 44, 980, 656));
        layout.insert(1);
        assert_eq!(layout.geometries()[0].1, 32);
        assert_eq!(layout.geometries()[0].2, 56);
        assert_eq!(layout.geometries()[0].4, 632);
        layout.maximize(1, true);
        assert_eq!(layout.geometries()[0].3, 956);
        layout.toggle_fullscreen();
        assert_eq!(layout.geometries(), vec![(1, 0, 0, 1000, 700)]);
        layout.toggle_fullscreen();
        layout.set_work_area((0, 0, 1000, 700));
        assert_eq!(layout.geometries()[0].2, 12);
        assert_eq!(layout.geometries()[0].4, 676);
    }
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

    #[test]
    fn adjacent_workspace_moves_wrap_and_keep_the_current_workspace() {
        let mut layout = Layout::default();
        layout.insert(1);
        layout.insert(2);
        let width = layout.workspace().columns[1].width;
        layout.move_to_adjacent_workspace(true);
        assert_eq!(layout.active, 0);
        assert_eq!(layout.focused(), Some(1));
        layout.switch_workspace(3);
        assert_eq!(layout.focused(), Some(2));
        assert_eq!(layout.workspace().columns[0].width, width);
        layout.move_to_adjacent_workspace(false);
        assert_eq!(layout.active, 3);
        assert!(layout.workspace().columns.is_empty());
        layout.move_to_adjacent_workspace(false); // Empty workspace is a no-op.
        layout.switch_workspace(0);
        assert_eq!(layout.focused(), Some(2));
        layout.move_to_adjacent_workspace(false);
        layout.switch_workspace(1);
        assert_eq!(layout.focused(), Some(2));
        layout.move_to_adjacent_workspace(true);
        layout.switch_workspace(0);
        assert_eq!(layout.focused(), Some(2));
        assert_eq!(layout.workspace().columns[1].width, width);
    }
}
