//! One reversible focus transition shared by rendering and pointer input.
use crate::preferences::FocusEasing;
use crate::{layout::WindowId, Smallvil};
use smithay::{
    desktop::Window,
    utils::{Logical, Point},
};
use std::collections::BTreeMap;

#[derive(Default)]
pub struct Effects(pub BTreeMap<WindowId, Transition>);
pub struct Transition {
    from: f64,
    target: f64,
    started: f64,
    duration: f64,
    easing: FocusEasing,
}
impl Transition {
    fn value(&self, now: f64) -> f64 {
        let t = if self.duration == 0.0 {
            1.0
        } else {
            ((now - self.started) / self.duration).clamp(0.0, 1.0)
        };
        self.from + (self.target - self.from) * self.easing.sample(t)
    }
}
impl Smallvil {
    fn inactive_target(&self, id: WindowId) -> f64 {
        if self.output_settings.decorations.inactive.enabled
            && self.layout.focused() != Some(id)
            && !self.layout.fullscreen_for(id)
        {
            1.0
        } else {
            0.0
        }
    }
    pub fn inactive_amount(&self, id: WindowId) -> f64 {
        // Fullscreen and disabling the effect take precedence immediately.
        if !self.output_settings.decorations.inactive.enabled || self.layout.fullscreen_for(id) {
            return 0.0;
        }
        self.inactive.0.get(&id).map_or_else(
            || self.inactive_target(id),
            |t| t.value(self.start_time.elapsed().as_secs_f64()),
        )
    }
    pub fn update_inactive(&mut self) -> bool {
        let now = self.start_time.elapsed().as_secs_f64();
        let easing = self.output_settings.decorations.inactive.easing;
        let duration = if self.output_settings.animations.enabled {
            self.output_settings.decorations.inactive.duration_ms as f64 / 1000.0
        } else {
            0.0
        };
        let mut changed = false;
        for id in self.windows.keys().copied() {
            let target = self.inactive_target(id);
            let t = self.inactive.0.entry(id).or_insert(Transition {
                from: target,
                target,
                started: now,
                duration,
                easing,
            });
            if t.target != target || t.duration != duration || t.easing != easing {
                *t = Transition {
                    from: t.value(now),
                    target,
                    started: now,
                    duration,
                    easing,
                };
                changed = true;
            }
            if t.from != t.target {
                changed = true;
                if now >= t.started + t.duration {
                    // Repaint the exact endpoint once, then stop scheduling frames.
                    t.from = t.target;
                }
            }
        }
        self.inactive
            .0
            .retain(|id, _| self.windows.contains_key(id));
        self.needs_redraw |= changed;
        changed
    }
    pub fn window_visual_scale(&self, id: WindowId) -> f64 {
        1.0 + (self.output_settings.decorations.inactive.scale - 1.0) * self.inactive_amount(id)
    }
    pub fn window_input_point(
        &self,
        window: &Window,
        point: Point<f64, Logical>,
    ) -> Point<f64, Logical> {
        let Some(id) = window
            .toplevel()
            .and_then(|t| self.window_id(t.wl_surface()))
        else {
            return point;
        };
        let bounds = self
            .output_settings
            .decorations
            .frame
            .bounds(window.geometry(), self.layout.fullscreen_for(id))
            .to_f64();
        let center = bounds.loc + Point::from((bounds.size.w / 2.0, bounds.size.h / 2.0));
        center + (point - center).downscale(self.window_visual_scale(id))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn configurable_curves_have_distinct_timing_and_fixed_endpoints() {
        for (easing, quarter) in [
            (FocusEasing::Linear, 0.25),
            (FocusEasing::EaseIn, 0.015625),
            (FocusEasing::EaseOut, 0.578125),
            (FocusEasing::EaseInOut, 0.0625),
        ] {
            assert_eq!(easing.sample(0.0), 0.0);
            assert_eq!(easing.sample(0.25), quarter);
            assert_eq!(easing.sample(1.0), 1.0);
        }
    }

    #[test]
    fn focus_transitions_ease_out_in_both_directions() {
        for (from, target) in [(0.0, 1.0), (1.0, 0.0)] {
            let t = Transition {
                from,
                target,
                started: 0.0,
                duration: 1.0,
                easing: FocusEasing::EaseOut,
            };
            assert_eq!(t.value(0.0), from);
            assert_eq!(t.value(0.5), from + (target - from) * 0.875);
            assert_eq!(t.value(1.0), target);
            assert!((t.value(0.25) - from).abs() > (target - t.value(0.75)).abs());
        }
    }

    #[test]
    fn interrupted_transition_keeps_its_visible_value() {
        let t = Transition {
            from: 0.0,
            target: 1.0,
            started: 0.0,
            duration: 1.0,
            easing: FocusEasing::EaseOut,
        };
        let reverse = Transition {
            from: t.value(0.4),
            target: 0.0,
            started: 0.4,
            duration: 1.0,
            easing: FocusEasing::EaseOut,
        };
        assert_eq!(reverse.value(0.4), t.value(0.4));
        assert_eq!(reverse.value(1.4), 0.0);
        assert_eq!(t.value(2.0), 1.0);
    }
}
