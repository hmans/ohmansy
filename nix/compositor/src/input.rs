use smithay::{
    backend::input::{
        AbsolutePositionEvent, Axis, AxisSource, ButtonState, Event, InputBackend, InputEvent,
        KeyboardKeyEvent, PointerAxisEvent, PointerButtonEvent,
    },
    input::{
        keyboard::FilterResult,
        pointer::{AxisFrame, ButtonEvent, MotionEvent},
    },
    reexports::wayland_server::protocol::wl_surface::WlSurface,
    utils::SERIAL_COUNTER,
};

use crate::state::Smallvil;

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
    }

    pub fn process_button(&mut self, button: u32, button_state: ButtonState, time: u32) {
        self.needs_redraw = true;
        let pointer = self.seat.get_pointer().unwrap();
        let keyboard = self.seat.get_keyboard().unwrap();

        let serial = SERIAL_COUNTER.next_serial();

        if ButtonState::Pressed == button_state && !pointer.is_grabbed() {
            if let Some((window, _loc)) = self
                .space
                .element_under(pointer.current_location())
                .map(|(w, l)| (w.clone(), l))
            {
                if let Some(id) = self.window_id(window.toplevel().unwrap().wl_surface()) {
                    self.layout.focus(id);
                    self.sync_focus();
                }
            } else {
                self.space.elements().for_each(|window| {
                    window.set_activated(false);
                    window.toplevel().unwrap().send_pending_configure();
                });
                keyboard.set_focus(self, Option::<WlSurface>::None, serial);
            }
        };

        pointer.button(
            self,
            &ButtonEvent {
                button,
                state: button_state,
                serial,
                time,
            },
        );
        pointer.frame(self);
    }

    pub fn process_key(
        &mut self,
        keycode: smithay::input::keyboard::Keycode,
        key_state: smithay::backend::input::KeyState,
        time: u32,
    ) {
        self.needs_redraw = true;
        let serial = SERIAL_COUNTER.next_serial();

        let pressed = key_state == smithay::backend::input::KeyState::Pressed;
        let code = keycode.raw();
        let action = self
            .seat
            .get_keyboard()
            .unwrap()
            .input::<(&str, Option<i64>), _>(
                self,
                keycode,
                key_state,
                serial,
                time,
                |state, modifiers, key| {
                    if !pressed && state.shortcut_keys.remove(&code) {
                        return FilterResult::Intercept(("none", None));
                    }
                    if !(modifiers.ctrl && modifiers.alt) {
                        return FilterResult::Forward;
                    }
                    let sym = key.modified_sym().raw();
                    let action = if (10..=13).contains(&code) {
                        Some((
                            if modifiers.shift {
                                "move-workspace"
                            } else {
                                "workspace"
                            },
                            Some((code - 9) as i64),
                        ))
                    } else {
                        match sym {
                            0x68 | 0x48 | 0xff51 => Some((
                                if modifiers.shift {
                                    "move-prev"
                                } else {
                                    "focus-prev"
                                },
                                None,
                            )),
                            0x6c | 0x4c | 0xff53 => Some((
                                if modifiers.shift {
                                    "move-next"
                                } else {
                                    "focus-next"
                                },
                                None,
                            )),
                            0x2d | 0x5f => Some(("resize", Some(-80))),
                            0x3d | 0x2b => Some(("resize", Some(80))),
                            0x66 | 0x46 => Some(("fullscreen", None)),
                            0x71 | 0x51 => Some(("close", None)),
                            0x64 | 0x44 => Some(("launcher", None)),
                            0x45 if modifiers.shift => Some(("logout", None)),
                            0xff0d => Some(("terminal", None)),
                            0x73 | 0x53 => Some(("scale", None)),
                            _ => None,
                        }
                    };
                    if let Some(action) = action {
                        if pressed {
                            state.shortcut_keys.insert(code);
                        }
                        FilterResult::Intercept(action)
                    } else {
                        FilterResult::Forward
                    }
                },
            );
        if pressed {
            if let Some((action, value)) = action {
                if action != "none" {
                    if let Err(error) = self.action(action, value) {
                        eprintln!("Window action: {error}");
                    }
                }
            } else {
                self.forwarded_keys += 1;
            }
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
            InputEvent::PointerMotion { .. } => {}
            InputEvent::PointerMotionAbsolute { event, .. } => {
                let geometry = self
                    .space
                    .outputs()
                    .next()
                    .cloned()
                    .and_then(|output| self.space.output_geometry(&output));
                if let Some(geometry) = geometry {
                    let position =
                        event.position_transformed(geometry.size) + geometry.loc.to_f64();
                    self.process_motion(position, event.time_msec());
                }
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
