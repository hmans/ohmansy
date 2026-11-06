//! Mapping policy for ordinary windows and transient dialogs.
use crate::Smallvil;
use smithay::{
    backend::renderer::utils::RendererSurfaceStateUserData,
    reexports::wayland_server::protocol::wl_surface::WlSurface,
    wayland::{compositor::with_states, shell::xdg::SurfaceCachedState},
};

impl smithay::wayland::shell::xdg::dialog::XdgDialogHandler for Smallvil {
    fn modal_changed(
        &mut self,
        _surface: smithay::wayland::shell::xdg::ToplevelSurface,
        _modal: bool,
    ) {
        self.sync_focus();
    }
}
smithay::delegate_xdg_dialog!(Smallvil);

impl Smallvil {
    pub fn activate_app(&mut self, app_ids: &[String]) -> bool {
        let names: Vec<_> = app_ids
            .iter()
            .map(|s| s.trim_end_matches(".desktop").to_lowercase())
            .collect();
        let id = self.windows.iter().rev().find_map(|(id, window)| {
            if !self.mapped_windows.contains(id) {
                return None;
            }
            with_states(window.toplevel().unwrap().wl_surface(), |states| {
                let metadata = states
                    .data_map
                    .get::<smithay::wayland::shell::xdg::XdgToplevelSurfaceData>()?
                    .lock()
                    .unwrap();
                metadata
                    .app_id
                    .as_ref()
                    .filter(|app| names.contains(&app.trim_end_matches(".desktop").to_lowercase()))
                    .map(|_| *id)
            })
        });
        if let Some(id) = id {
            self.layout.focus(id);
            self.sync_focus();
            true
        } else {
            false
        }
    }

    pub fn focus_modal_descendant(&mut self) {
        use smithay::wayland::shell::xdg::XdgToplevelSurfaceData;
        for _ in 0..self.windows.len() {
            let Some(parent) = self
                .layout
                .focused()
                .and_then(|id| self.windows.get(&id))
                .map(|w| w.toplevel().unwrap().wl_surface().clone())
            else {
                return;
            };
            let child = self.windows.iter().rev().find_map(|(id, window)| {
                if !self.mapped_windows.contains(id)
                    || window.toplevel().unwrap().parent().as_ref() != Some(&parent)
                {
                    return None;
                }
                with_states(window.toplevel().unwrap().wl_surface(), |s| {
                    s.data_map
                        .get::<XdgToplevelSurfaceData>()
                        .and_then(|m| m.lock().unwrap().modal.then_some(*id))
                })
            });
            let Some(child) = child else { return };
            self.layout.focus(child);
        }
    }
    pub fn map_window_policy(&mut self, surface: &WlSurface) {
        let Some(id) = self.window_id(surface) else {
            return;
        };
        let mapped = with_states(surface, |states| {
            states
                .data_map
                .get::<RendererSurfaceStateUserData>()
                .is_some_and(|r| r.lock().unwrap().buffer().is_some())
        });
        if self.mapped_windows.contains(&id) && mapped {
            return;
        }
        if !mapped && self.mapped_windows.remove(&id) {
            self.layout.remove(id);
            self.space.unmap_elem(&self.windows[&id]);
            self.sync_focus();
            return;
        }
        if self.layout.owner(id).is_none() {
            self.layout.insert_unfocused(id);
        }
        let window = self.windows[&id].clone();
        let parent = window
            .toplevel()
            .unwrap()
            .parent()
            .and_then(|p| self.window_id(&p));
        let (min, max) = with_states(surface, |states| {
            let mut cache = states.cached_state.get::<SurfaceCachedState>();
            let state = cache.current();
            (state.min_size, state.max_size)
        });
        let fixed = min.w > 0 && min.h > 0 && min == max;
        if (parent.is_some() || fixed)
            && self
                .layout
                .owner(id)
                .is_some_and(|i| self.layout.monitors[i].layout.floating(id).is_none())
        {
            if let Some(parent) = parent {
                if let Some(owner) = self.layout.owner(parent) {
                    let workspace = self.layout.monitors[owner]
                        .layout
                        .workspaces
                        .iter()
                        .position(|w| w.columns.iter().any(|c| c.id == parent))
                        .unwrap();
                    self.layout.place_window(id, owner, workspace);
                }
            }
            if let Some(owner) = self.layout.owner(id) {
                let width = if fixed {
                    min.w
                } else {
                    600.max(min.w).min(if max.w > 0 { max.w } else { i32::MAX })
                };
                let height = if fixed {
                    min.h
                } else {
                    400.max(min.h).min(if max.h > 0 { max.h } else { i32::MAX })
                };
                self.layout.monitors[owner]
                    .layout
                    .set_floating(id, parent, (width, height));
            }
        }
        if mapped {
            if let Some(owner) = self.layout.owner(id) {
                if self.layout.monitors[owner].layout.floating(id).is_some() {
                    let size = window.geometry().size;
                    if size.w > 0 && size.h > 0 {
                        self.layout.monitors[owner].layout.set_floating(
                            id,
                            parent,
                            (size.w, size.h),
                        );
                    }
                }
            }
        }
        if !mapped {
            self.apply_positions();
            return;
        }
        self.mapped_windows.insert(id);
        self.layout.focus(id);
        self.sync_focus();
    }
}
