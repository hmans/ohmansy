use crate::Smallvil;
use smithay::{
    backend::allocator::dmabuf::Dmabuf,
    delegate_dmabuf, delegate_fractional_scale, delegate_viewporter, delegate_xdg_decoration,
    reexports::{
        wayland_protocols::xdg::decoration::zv1::server::zxdg_toplevel_decoration_v1::Mode,
        wayland_server::protocol::wl_surface::WlSurface,
    },
    wayland::{
        dmabuf::{DmabufGlobal, DmabufHandler, DmabufState, ImportNotifier},
        fractional_scale::FractionalScaleHandler,
        shell::xdg::{decoration::XdgDecorationHandler, ToplevelSurface},
    },
};

impl DmabufHandler for Smallvil {
    fn dmabuf_state(&mut self) -> &mut DmabufState {
        &mut self.dmabuf_state
    }
    fn dmabuf_imported(
        &mut self,
        _global: &DmabufGlobal,
        buffer: Dmabuf,
        notifier: ImportNotifier,
    ) {
        // Validate on the rendering thread when its GL context can be bound.
        self.pending_imports.push((buffer, notifier));
        self.needs_redraw = true;
    }
}
delegate_dmabuf!(Smallvil);

impl FractionalScaleHandler for Smallvil {
    fn new_fractional_scale(&mut self, surface: WlSurface) {
        self.update_client_scale(&surface);
    }
}
delegate_fractional_scale!(Smallvil);
delegate_viewporter!(Smallvil);

impl XdgDecorationHandler for Smallvil {
    fn new_decoration(&mut self, surface: ToplevelSurface) {
        let mode = if self.output_settings.decorations.frame.enabled {
            Mode::ServerSide
        } else {
            Mode::ClientSide
        };
        surface.with_pending_state(|state| state.decoration_mode = Some(mode));
    }
    fn request_mode(&mut self, surface: ToplevelSurface, _mode: Mode) {
        self.new_decoration(surface.clone());
        if surface.is_initial_configure_sent() {
            surface.send_pending_configure();
        }
    }
    fn unset_mode(&mut self, surface: ToplevelSurface) {
        self.request_mode(surface, Mode::ClientSide);
    }
}
delegate_xdg_decoration!(Smallvil);

impl smithay::wayland::selection::primary_selection::PrimarySelectionHandler for Smallvil {
    fn primary_selection_state(
        &self,
    ) -> &smithay::wayland::selection::primary_selection::PrimarySelectionState {
        &self.primary_selection_state
    }
}
smithay::delegate_primary_selection!(Smallvil);
smithay::delegate_cursor_shape!(Smallvil);
impl smithay::wayland::tablet_manager::TabletSeatHandler for Smallvil {}
