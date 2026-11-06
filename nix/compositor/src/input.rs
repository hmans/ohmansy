use smithay::{
    backend::input::{
        AbsolutePositionEvent, Axis, AxisSource, ButtonState, Event, InputBackend, InputEvent,
        KeyboardKeyEvent, PointerAxisEvent, PointerButtonEvent, PointerMotionEvent,
    },
    input::{
        keyboard::FilterResult,
        pointer::{AxisFrame, ButtonEvent, MotionEvent},
    },
    utils::SERIAL_COUNTER,
};

use crate::state::Smallvil;

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum ShortcutModifier {
    Super,
    #[default]
    SuperAlt,
    CtrlAlt,
}

impl ShortcutModifier {
    pub fn parse(value: &str) -> Result<Self, String> {
        match value {
            "super" => Ok(Self::Super),
            "super-alt" => Ok(Self::SuperAlt),
            "ctrl-alt" => Ok(Self::CtrlAlt),
            _ => Err("--mod-key must be super, super-alt, or ctrl-alt".into()),
        }
    }

    pub fn name(self) -> &'static str {
        match self {
            Self::Super => "super",
            Self::SuperAlt => "super-alt",
            Self::CtrlAlt => "ctrl-alt",
        }
    }

    pub fn label(self) -> &'static str {
        match self {
            Self::Super => "Super",
            Self::SuperAlt => "Super+Alt",
            Self::CtrlAlt => "Ctrl+Alt",
        }
    }

    #[cfg(test)]
    fn matches(self, modifiers: &smithay::input::keyboard::ModifiersState) -> bool {
        !modifiers.iso_level3_shift
            && !modifiers.iso_level5_shift
            && match self {
                Self::Super => modifiers.logo && !modifiers.ctrl && !modifiers.alt,
                Self::SuperAlt => modifiers.logo && !modifiers.ctrl && modifiers.alt,
                Self::CtrlAlt => !modifiers.logo && modifiers.ctrl && modifiers.alt,
            }
    }
}

impl Smallvil {
    pub fn process_motion(
        &mut self,
        pos: smithay::utils::Point<f64, smithay::utils::Logical>,
        time: u32,
    ) {
        self.needs_redraw = true;
        let pointer = self.seat.get_pointer().unwrap();
        let under = self.surface_under(pos);
        pointer.motion(
            self,
            under,
            &MotionEvent {
                location: pos,
                serial: SERIAL_COUNTER.next_serial(),
                time,
            },
        );
        pointer.frame(self);
        self.update_pointer_scales();
    }

    pub fn process_button(&mut self, button: u32, button_state: ButtonState, time: u32) {
        self.needs_redraw = true;
        let pointer = self.seat.get_pointer().unwrap();
        let keyboard = self.seat.get_keyboard().unwrap();

        let serial = SERIAL_COUNTER.next_serial();
        let title_drag =
            if button == 0x110 && button_state == ButtonState::Pressed && !pointer.is_grabbed() {
                use smithay::wayland::shell::wlr_layer::Layer;
                if self
                    .layer_under(pointer.current_location(), &[Layer::Overlay, Layer::Top])
                    .is_some()
                {
                    None
                } else {
                    self.window_under(pointer.current_location())
                        .and_then(|(window, location)| {
                            let id = self.window_id(window.toplevel()?.wl_surface())?;
                            let frame = &self.output_settings.decorations.frame;
                            if !frame.enabled || self.layout.fullscreen_for(id) {
                                return None;
                            }
                            let point = self.window_input_point(
                                window,
                                pointer.current_location() - location.to_f64(),
                            );
                            let bounds = frame.bounds(window.geometry(), false);
                            (self.surface_under(pointer.current_location()).is_none()
                                && point.y < window.geometry().loc.y as f64
                                && crate::decoration::contains(
                                    bounds,
                                    self.output_settings.decorations.outer_radius(),
                                    point,
                                ))
                            .then(|| (window.clone(), self.space.element_location(window).unwrap()))
                        })
                }
            } else {
                None
            };
        let scaled_click = if ButtonState::Pressed == button_state && !pointer.is_grabbed() {
            self.window_under(pointer.current_location())
                .and_then(|(window, location)| {
                    use smithay::wayland::shell::wlr_layer::Layer;
                    if self
                        .layer_under(pointer.current_location(), &[Layer::Overlay, Layer::Top])
                        .is_some()
                    {
                        return None;
                    }
                    let (_, origin) = self.surface_under(pointer.current_location())?;
                    let local = self
                        .window_input_point(window, pointer.current_location() - location.to_f64());
                    Some((
                        window.clone(),
                        local - (pointer.current_location() - origin),
                    ))
                })
        } else {
            None
        };

        if ButtonState::Pressed == button_state && !pointer.is_grabbed() {
            use smithay::wayland::shell::wlr_layer::Layer;
            if self
                .layer_under(pointer.current_location(), &[Layer::Overlay, Layer::Top])
                .is_some()
            {
                // A panel with keyboardFocus=None must preserve the application's focus.
            } else if let Some((window, _loc)) = self
                .window_under(pointer.current_location())
                .map(|(w, l)| (w.clone(), l))
            {
                if let Some(id) = self.window_id(window.toplevel().unwrap().wl_surface()) {
                    self.layout.focus(id);
                    self.sync_focus();
                }
            } else {
                if let Some(index) = self
                    .layout
                    .at(pointer.current_location().x, pointer.current_location().y)
                {
                    self.layout.focus_monitor(index);
                    self.ui_scale = self.layout.current().scale;
                }
                self.space.elements().for_each(|window| {
                    window.set_activated(false);
                    window.toplevel().unwrap().send_pending_configure();
                });
                let focus = self.exclusive_layer_focus();
                keyboard.set_focus(self, focus, serial);
            }
        };

        self.record_activation_input(serial, pointer.current_focus());
        pointer.button(
            self,
            &ButtonEvent {
                button,
                state: button_state,
                serial,
                time,
            },
        );
        if let Some((window, initial_window_location)) = title_drag {
            pointer.set_grab(
                self,
                crate::grabs::MoveSurfaceGrab {
                    start_data: smithay::input::pointer::GrabStartData {
                        focus: None,
                        button,
                        location: pointer.current_location(),
                    },
                    window,
                    initial_window_location,
                },
                serial,
                smithay::input::pointer::Focus::Clear,
            );
        } else if let Some((window, surface_offset)) = scaled_click {
            if let Some(start_data) = pointer.grab_start_data() {
                // Replace only the implicit click grab; clients may have installed
                // their own popup or drag grab before this button arrived.
                pointer.set_grab(
                    self,
                    crate::grabs::scaled_click::ScaledClickGrab {
                        start_data,
                        window,
                        surface_offset,
                    },
                    serial,
                    smithay::input::pointer::Focus::Keep,
                );
            }
        }
        pointer.frame(self);
    }

    pub fn process_key(
        &mut self,
        keycode: smithay::input::keyboard::Keycode,
        key_state: smithay::backend::input::KeyState,
        time: u32,
    ) {
        enum KeyAction {
            Binding(crate::preferences::Action),
            Vt(i32),
            Consumed,
        }
        self.needs_redraw = true;
        let serial = SERIAL_COUNTER.next_serial();
        let pressed = key_state == smithay::backend::input::KeyState::Pressed;
        let code = keycode.raw();
        let action = self.seat.get_keyboard().unwrap().input::<KeyAction, _>(
            self,
            keycode,
            key_state,
            serial,
            time,
            |state, modifiers, key| {
                if !pressed {
                    return if state.shortcut_keys.remove(&code) {
                        FilterResult::Intercept(KeyAction::Consumed)
                    } else {
                        FilterResult::Forward
                    };
                }
                if state.native_mode && modifiers.ctrl && modifiers.alt {
                    let vt = match code {
                        67..=76 => Some(code - 66),
                        95 => Some(11),
                        96 => Some(12),
                        _ => None,
                    };
                    if let Some(vt) = vt {
                        state.shortcut_keys.insert(code);
                        return FilterResult::Intercept(KeyAction::Vt(vt as i32));
                    }
                }
                let modified = [key.modified_sym().raw()];
                let mut raw: Vec<_> = key.raw_syms().iter().map(|s| s.raw()).collect();
                if let Some(latin) = key.raw_latin_sym_or_raw_current_sym() {
                    raw.push(latin.raw());
                }
                let binding = state
                    .configured_bindings
                    .iter()
                    .find(|(c, _)| c.matches(modifiers, &modified))
                    .or_else(|| {
                        state
                            .configured_bindings
                            .iter()
                            .find(|(c, _)| c.matches(modifiers, &raw))
                    });
                if let Some((_, action)) = binding {
                    let action = action.clone();
                    state.shortcut_keys.insert(code);
                    FilterResult::Intercept(KeyAction::Binding(action))
                } else {
                    FilterResult::Forward
                }
            },
        );
        match action {
            Some(KeyAction::Binding(action)) => {
                if let Err(error) = action.execute(self) {
                    eprintln!("Binding action: {error}");
                }
            }
            Some(KeyAction::Vt(vt)) => self.vt_request = Some(vt),
            None if pressed => {
                self.forwarded_keys += 1;
                self.record_activation_input(
                    serial,
                    self.seat.get_keyboard().unwrap().current_focus(),
                );
            }
            _ => (),
        }
    }

    pub fn process_input_event<I: InputBackend>(&mut self, event: InputEvent<I>) {
        if self.test_input {
            return;
        }
        self.needs_redraw = true;
        match event {
            InputEvent::Keyboard { event, .. } => {
                self.process_key(event.key_code(), event.state(), event.time_msec())
            }
            InputEvent::PointerMotion { event, .. } => {
                let position = self.seat.get_pointer().unwrap().current_location() + event.delta();
                let position = self.layout.clamp(position.x, position.y);
                self.process_motion(position.into(), event.time_msec());
            }
            InputEvent::PointerMotionAbsolute { event, .. } => {
                if let Some((width, height)) = self.nested_canvas_size {
                    let position = self
                        .layout
                        .canvas_point(event.x_transformed(width), event.y_transformed(height));
                    self.process_motion(position.into(), event.time_msec());
                    return;
                }
                let left = self
                    .layout
                    .monitors
                    .iter()
                    .map(|m| m.origin.0)
                    .min()
                    .unwrap_or(0);
                let top = self
                    .layout
                    .monitors
                    .iter()
                    .map(|m| m.origin.1)
                    .min()
                    .unwrap_or(0);
                let width = self
                    .layout
                    .monitors
                    .iter()
                    .map(|m| m.origin.0 + m.layout.size.0)
                    .max()
                    .unwrap_or(1);
                let height = self
                    .layout
                    .monitors
                    .iter()
                    .map(|m| m.origin.1 + m.layout.size.1)
                    .max()
                    .unwrap_or(1);
                let position = event.position_transformed((width - left, height - top).into())
                    + smithay::utils::Point::from((left, top)).to_f64();
                let position = self.layout.clamp(position.x, position.y);
                self.process_motion(position.into(), event.time_msec());
            }
            InputEvent::PointerButton { event, .. } => {
                self.process_button(event.button_code(), event.state(), event.time_msec())
            }
            InputEvent::PointerAxis { event, .. } => {
                let source = event.source();

                let horizontal_amount = event.amount(Axis::Horizontal).unwrap_or_else(|| {
                    event.amount_v120(Axis::Horizontal).unwrap_or(0.0) * 15.0 / 120.
                });
                let vertical_amount = event.amount(Axis::Vertical).unwrap_or_else(|| {
                    event.amount_v120(Axis::Vertical).unwrap_or(0.0) * 15.0 / 120.
                });
                let horizontal_amount_discrete = event.amount_v120(Axis::Horizontal);
                let vertical_amount_discrete = event.amount_v120(Axis::Vertical);

                let mut frame = AxisFrame::new(event.time_msec()).source(source);
                if horizontal_amount != 0.0 {
                    frame = frame.value(Axis::Horizontal, horizontal_amount);
                    if let Some(discrete) = horizontal_amount_discrete {
                        frame = frame.v120(Axis::Horizontal, discrete as i32);
                    }
                }
                if vertical_amount != 0.0 {
                    frame = frame.value(Axis::Vertical, vertical_amount);
                    if let Some(discrete) = vertical_amount_discrete {
                        frame = frame.v120(Axis::Vertical, discrete as i32);
                    }
                }

                if source == AxisSource::Finger {
                    if event.amount(Axis::Horizontal) == Some(0.0) {
                        frame = frame.stop(Axis::Horizontal);
                    }
                    if event.amount(Axis::Vertical) == Some(0.0) {
                        frame = frame.stop(Axis::Vertical);
                    }
                }

                let pointer = self.seat.get_pointer().unwrap();
                pointer.axis(self, frame);
                pointer.frame(self);
            }
            _ => {}
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use smithay::input::keyboard::ModifiersState;

    #[test]
    fn parent_and_child_shortcuts_are_disjoint_and_allow_shift() {
        for logo in [false, true] {
            for alt in [false, true] {
                for ctrl in [false, true] {
                    for shift in [false, true] {
                        let modifiers = ModifiersState {
                            logo,
                            alt,
                            ctrl,
                            shift,
                            ..Default::default()
                        };
                        assert_eq!(
                            ShortcutModifier::Super.matches(&modifiers),
                            logo && !alt && !ctrl
                        );
                        assert_eq!(
                            ShortcutModifier::SuperAlt.matches(&modifiers),
                            logo && alt && !ctrl
                        );
                    }
                }
            }
        }
    }

    #[test]
    fn modifier_options_reject_unknown_profiles() {
        assert_eq!(
            ShortcutModifier::parse("super"),
            Ok(ShortcutModifier::Super)
        );
        assert_eq!(
            ShortcutModifier::parse("super-alt"),
            Ok(ShortcutModifier::SuperAlt)
        );
        assert_eq!(
            ShortcutModifier::parse("ctrl-alt"),
            Ok(ShortcutModifier::CtrlAlt)
        );
        assert!(ShortcutModifier::parse("invalid").is_err());
    }
}
