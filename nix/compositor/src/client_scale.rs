//! Client buffer preferences follow surface ownership, independently of focus.
use smithay::{
    desktop::{find_popup_root_surface, layer_map_for_output},
    input::pointer::CursorImageStatus,
    reexports::wayland_server::protocol::wl_surface::WlSurface,
    utils::{IsAlive, Transform},
    wayland::{
        compositor::{get_parent, send_surface_state, with_states},
        fractional_scale::with_fractional_scale,
    },
};

use crate::Smallvil;

impl Smallvil {
    pub fn client_scale(&self, surface: &WlSurface) -> f64 {
        let mut root = surface.clone();
        while let Some(parent) = get_parent(&root) {
            root = parent;
        }
        // Cursor and drag surfaces follow the pointer rather than keyboard focus.
        if matches!(&self.cursor_image, CursorImageStatus::Surface(cursor) if cursor == &root)
            || self.drag_icon.as_ref() == Some(&root)
        {
            let pos = self.seat.get_pointer().unwrap().current_location();
            if let Some(index) = self.layout.at(pos.x, pos.y) {
                return self.layout.monitors[index].scale;
            }
        }
        if let Some(popup) = self.popups.find_popup(&root) {
            if let Ok(parent) = find_popup_root_surface(&popup) {
                root = parent;
            }
        }
        for (id, window) in &self.windows {
            if window.toplevel().unwrap().wl_surface() == &root {
                if let Some(index) = self.layout.owner(*id) {
                    return self.layout.monitors[index].scale;
                }
            }
        }
        for output in self.space.outputs() {
            if layer_map_for_output(output)
                .layers()
                .any(|layer| layer.wl_surface() == &root)
            {
                return output.current_scale().fractional_scale();
            }
        }
        // Before a role/output is assigned, use the current monitor.
        self.layout.current().scale
    }

    pub fn update_client_scale(&self, surface: &WlSurface) {
        // Resolve ownership before taking the surface state lock: popup lookup
        // and subsurface ancestry also access surface state.
        let scale = self.client_scale(surface);
        with_states(surface, |states| {
            send_surface_state(surface, states, scale.ceil() as i32, Transform::Normal);
            with_fractional_scale(states, |fractional| fractional.set_preferred_scale(scale));
        });
    }

    pub fn update_client_scales(&mut self) {
        self.client_surfaces.retain(|surface| surface.alive());
        for surface in &self.client_surfaces {
            self.update_client_scale(surface);
        }
    }

    pub fn update_pointer_scales(&self) {
        if let CursorImageStatus::Surface(surface) = &self.cursor_image {
            self.update_client_scale(surface);
        }
        if let Some(surface) = &self.drag_icon {
            self.update_client_scale(surface);
        }
    }
}
