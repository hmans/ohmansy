use crate::Smallvil;
use smithay::{
    desktop::{layer_map_for_output, LayerSurface, WindowSurfaceType},
    output::Output,
    reexports::wayland_server::protocol::{wl_output::WlOutput, wl_surface::WlSurface},
    utils::{Logical, Point},
    wayland::{
        compositor::with_states,
        shell::wlr_layer::{
            KeyboardInteractivity, Layer, LayerSurface as ProtocolSurface, LayerSurfaceData,
            WlrLayerShellHandler, WlrLayerShellState,
        },
    },
};

impl WlrLayerShellHandler for Smallvil {
    fn shell_state(&mut self) -> &mut WlrLayerShellState {
        &mut self.layer_shell_state
    }

    fn new_layer_surface(
        &mut self,
        surface: ProtocolSurface,
        output: Option<WlOutput>,
        _layer: Layer,
        namespace: String,
    ) {
        let output = output.as_ref().and_then(Output::from_resource).or_else(|| {
            self.space
                .outputs()
                .find(|o| o.name() == self.layout.current().name)
                .cloned()
        });
        if let Some(output) = output {
            let _ = layer_map_for_output(&output).map_layer(&LayerSurface::new(surface, namespace));
            self.update_client_scales();
        } else {
            surface.send_close();
        }
    }

    fn layer_destroyed(&mut self, surface: ProtocolSurface) {
        let had_focus = self.seat.get_keyboard().unwrap().current_focus().as_ref()
            == Some(surface.wl_surface());
        for output in self.space.outputs() {
            let mut map = layer_map_for_output(output);
            let layer = map
                .layers()
                .find(|l| l.wl_surface() == surface.wl_surface())
                .cloned();
            if let Some(layer) = layer {
                map.unmap_layer(&layer);
            }
        }
        self.arrange_layers();
        self.apply_positions();
        if had_focus {
            self.sync_keyboard_focus();
        }
    }
}
smithay::delegate_layer_shell!(Smallvil);

impl Smallvil {
    pub fn commit_layer(&mut self, surface: &WlSurface) {
        let is_layer = with_states(surface, |states| {
            states.data_map.get::<LayerSurfaceData>().is_some()
        });
        if !is_layer {
            return;
        }
        self.arrange_layers();
        let initial = with_states(surface, |states| {
            states
                .data_map
                .get::<LayerSurfaceData>()
                .unwrap()
                .lock()
                .unwrap()
                .initial_configure_sent
        });
        if !initial {
            if let Some(layer) = self
                .layer_shell_state
                .layer_surfaces()
                .find(|l| l.wl_surface() == surface)
            {
                layer.send_configure();
            }
        }
        self.apply_positions();
        // Wallpaper/bar commits must not interrupt an application's popup grab.
        let layer_focused = self
            .seat
            .get_keyboard()
            .unwrap()
            .current_focus()
            .is_some_and(|focus| {
                self.layer_shell_state
                    .layer_surfaces()
                    .any(|layer| layer.wl_surface() == &focus)
            });
        if layer_focused || self.exclusive_layer_focus().is_some() {
            self.sync_keyboard_focus();
        }
    }

    // Exclusive top/overlay surfaces receive keys only while mapped and asking
    // for them. The layout keeps its selected app, ready for dismissal.
    pub fn exclusive_layer_focus(&self) -> Option<WlSurface> {
        for kind in [Layer::Overlay, Layer::Top] {
            for output in self.space.outputs() {
                let map = layer_map_for_output(output);
                for layer in map.layers_on(kind).rev() {
                    if layer.cached_state().keyboard_interactivity
                        == KeyboardInteractivity::Exclusive
                        && layer.bbox().size.w > 0
                        && layer.bbox().size.h > 0
                    {
                        return Some(layer.wl_surface().clone());
                    }
                }
            }
        }
        None
    }

    pub fn arrange_layers(&mut self) {
        for output in self.space.outputs() {
            let mut map = layer_map_for_output(output);
            map.cleanup();
            map.arrange();
            let zone = map.non_exclusive_zone();
            if let Some(monitor) = self
                .layout
                .monitors
                .iter_mut()
                .find(|m| m.name == output.name())
            {
                monitor.layout.set_work_area((
                    zone.loc.x,
                    zone.loc.y,
                    zone.size.w.max(1),
                    zone.size.h.max(1),
                ));
            }
        }
        self.needs_redraw = true;
    }

    pub fn layer_under(
        &self,
        pos: Point<f64, Logical>,
        layers: &[Layer],
    ) -> Option<(WlSurface, Point<f64, Logical>)> {
        let monitor = &self.layout.monitors[self.layout.at(pos.x, pos.y)?];
        let output = self.space.outputs().find(|o| o.name() == monitor.name)?;
        let origin = Point::<i32, Logical>::from(monitor.origin);
        let map = layer_map_for_output(output);
        for kind in layers {
            if *kind == Layer::Top && monitor.layout.workspace().fullscreen.is_some() {
                continue;
            }
            for layer in map.layers_on(*kind).rev() {
                let location = map.layer_geometry(layer)?.loc;
                if let Some((surface, offset)) =
                    layer.surface_under(pos - (origin + location).to_f64(), WindowSurfaceType::ALL)
                {
                    return Some((surface, (origin + location + offset).to_f64()));
                }
            }
        }
        None
    }
}
