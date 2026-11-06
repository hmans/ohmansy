use crate::Smallvil;
use smithay::{
    desktop::Window,
    input::pointer::{
        AxisFrame, ButtonEvent, GestureHoldBeginEvent, GestureHoldEndEvent, GesturePinchBeginEvent,
        GesturePinchEndEvent, GesturePinchUpdateEvent, GestureSwipeBeginEvent,
        GestureSwipeEndEvent, GestureSwipeUpdateEvent, GrabStartData as PointerGrabStartData,
        MotionEvent, PointerGrab, PointerInnerHandle, RelativeMotionEvent,
    },
    reexports::wayland_server::protocol::wl_surface::WlSurface,
    utils::{Logical, Point},
};

pub struct ScaledClickGrab {
    pub start_data: PointerGrabStartData<Smallvil>,
    pub window: Window,
    pub surface_offset: Point<f64, Logical>,
}

impl PointerGrab<Smallvil> for ScaledClickGrab {
    fn motion(
        &mut self,
        data: &mut Smallvil,
        handle: &mut PointerInnerHandle<'_, Smallvil>,
        _focus: Option<(WlSurface, Point<f64, Logical>)>,
        event: &MotionEvent,
    ) {
        // Preserve the grabbed surface, including outside its input region,
        // while focus animation changes its position beneath the pointer.
        let focus = self.start_data.focus.as_ref().and_then(|(surface, _)| {
            let location = data.space.element_location(&self.window)? - self.window.geometry().loc;
            let local = data.window_input_point(&self.window, event.location - location.to_f64());
            Some((
                surface.clone(),
                event.location - (local - self.surface_offset),
            ))
        });
        handle.motion(data, focus, event);
    }

    fn relative_motion(
        &mut self,
        data: &mut Smallvil,
        handle: &mut PointerInnerHandle<'_, Smallvil>,
        focus: Option<(WlSurface, Point<f64, Logical>)>,
        event: &RelativeMotionEvent,
    ) {
        handle.relative_motion(data, focus, event);
    }

    fn button(
        &mut self,
        data: &mut Smallvil,
        handle: &mut PointerInnerHandle<'_, Smallvil>,
        event: &ButtonEvent,
    ) {
        handle.button(data, event);

        if handle.current_pressed().is_empty() {
            handle.unset_grab(self, data, event.serial, event.time, false);
        }
    }

    fn axis(
        &mut self,
        data: &mut Smallvil,
        handle: &mut PointerInnerHandle<'_, Smallvil>,
        details: AxisFrame,
    ) {
        handle.axis(data, details)
    }

    fn frame(&mut self, data: &mut Smallvil, handle: &mut PointerInnerHandle<'_, Smallvil>) {
        handle.frame(data);
    }

    fn gesture_swipe_begin(
        &mut self,
        data: &mut Smallvil,
        handle: &mut PointerInnerHandle<'_, Smallvil>,
        event: &GestureSwipeBeginEvent,
    ) {
        handle.gesture_swipe_begin(data, event)
    }

    fn gesture_swipe_update(
        &mut self,
        data: &mut Smallvil,
        handle: &mut PointerInnerHandle<'_, Smallvil>,
        event: &GestureSwipeUpdateEvent,
    ) {
        handle.gesture_swipe_update(data, event)
    }

    fn gesture_swipe_end(
        &mut self,
        data: &mut Smallvil,
        handle: &mut PointerInnerHandle<'_, Smallvil>,
        event: &GestureSwipeEndEvent,
    ) {
        handle.gesture_swipe_end(data, event)
    }

    fn gesture_pinch_begin(
        &mut self,
        data: &mut Smallvil,
        handle: &mut PointerInnerHandle<'_, Smallvil>,
        event: &GesturePinchBeginEvent,
    ) {
        handle.gesture_pinch_begin(data, event)
    }

    fn gesture_pinch_update(
        &mut self,
        data: &mut Smallvil,
        handle: &mut PointerInnerHandle<'_, Smallvil>,
        event: &GesturePinchUpdateEvent,
    ) {
        handle.gesture_pinch_update(data, event)
    }

    fn gesture_pinch_end(
        &mut self,
        data: &mut Smallvil,
        handle: &mut PointerInnerHandle<'_, Smallvil>,
        event: &GesturePinchEndEvent,
    ) {
        handle.gesture_pinch_end(data, event)
    }

    fn gesture_hold_begin(
        &mut self,
        data: &mut Smallvil,
        handle: &mut PointerInnerHandle<'_, Smallvil>,
        event: &GestureHoldBeginEvent,
    ) {
        handle.gesture_hold_begin(data, event)
    }

    fn gesture_hold_end(
        &mut self,
        data: &mut Smallvil,
        handle: &mut PointerInnerHandle<'_, Smallvil>,
        event: &GestureHoldEndEvent,
    ) {
        handle.gesture_hold_end(data, event)
    }

    fn start_data(&self) -> &PointerGrabStartData<Smallvil> {
        &self.start_data
    }

    fn unset(&mut self, _data: &mut Smallvil) {}
}
