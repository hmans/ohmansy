use std::{collections::BTreeMap, ffi::OsString, sync::Arc};

use smithay::{
    desktop::{PopupManager, Space, Window, WindowSurfaceType},
    input::{Seat, SeatState},
    reexports::{
        calloop::{generic::Generic, EventLoop, Interest, LoopSignal, Mode, PostAction},
        wayland_server::{
            backend::{ClientData, ClientId, DisconnectReason},
            protocol::wl_surface::WlSurface,
            Display, DisplayHandle,
        },
    },
    utils::{IsAlive, Logical, Point},
    wayland::{
        compositor::{CompositorClientState, CompositorState},
        dmabuf::{DmabufGlobal, DmabufState, ImportNotifier},
        fractional_scale::FractionalScaleManagerState,
        output::OutputManagerState,
        selection::data_device::DataDeviceState,
        shell::xdg::decoration::XdgDecorationState,
        shell::xdg::XdgShellState,
        shm::ShmState,
        socket::ListeningSocketSource,
        viewporter::ViewporterState,
    },
};

use crate::desktop::Desktop;
use crate::layout::WindowId;
use crate::CalloopData;

pub struct Smallvil {
    pub start_time: std::time::Instant,
    pub socket_name: OsString,
    pub ui_scale: f64,
    pub windows: BTreeMap<WindowId, Window>,
    pub layout: Desktop,
    pub output_info: BTreeMap<String, crate::output_config::OutputInfo>,
    pub output_settings: crate::output_config::Settings,
    pub config_file: Option<crate::output_config::ConfigFile>,
    pub config_error: Option<String>,
    pub layout_warning: Option<String>,
    pub config_revision: u64,
    pub config_poll: std::time::Instant,
    pub default_output_scale: f64,
    pub configured_bindings: Vec<(crate::preferences::Chord, crate::preferences::Action)>,
    pub applied_keyboard: crate::preferences::Keyboard,
    pub window_preferences_applied: std::collections::BTreeSet<WindowId>,
    pub input_devices: Vec<serde_json::Value>,
    pub nested_canvas_size: Option<(i32, i32)>,
    pub virtual_outputs: usize,
    pub native_mode: bool,
    pub vt_request: Option<i32>,
    pub next_window: WindowId,
    pub configured: BTreeMap<WindowId, (i32, i32, bool, bool)>,
    pub needs_redraw: bool,
    pub shortcut_keys: std::collections::BTreeSet<u32>,
    pub dmabuf_state: DmabufState,
    pub dmabuf_global: Option<DmabufGlobal>,
    pub pending_imports: Vec<(smithay::backend::allocator::dmabuf::Dmabuf, ImportNotifier)>,
    pub dmabuf_imports: u64,
    pub dmabuf_failures: u64,
    pub fractional_scale_state: FractionalScaleManagerState,
    pub viewporter_state: ViewporterState,
    pub decoration_state: XdgDecorationState,
    pub primary_selection_state:
        smithay::wayland::selection::primary_selection::PrimarySelectionState,
    pub cursor_shape_state: smithay::wayland::cursor_shape::CursorShapeManagerState,
    pub cursor_image: smithay::input::pointer::CursorImageStatus,
    pub cursor_rendered_elements: usize,
    pub drag_icon: Option<WlSurface>,
    pub popup_events: u64,
    pub popup_grabs: u64,
    pub test_input: bool,
    pub session_mode: bool,
    pub shortcut_modifier: crate::input::ShortcutModifier,
    pub screenshot: Option<std::path::PathBuf>,
    pub capture: crate::screenshot::State,
    pub commits: u64,
    pub rendered_frames: u64,
    pub forwarded_keys: u64,
    pub selection_updates: u64,
    pub runtime_error: Option<String>,
    pub display_handle: DisplayHandle,

    pub space: Space<Window>,
    pub loop_signal: LoopSignal,

    // Smithay State
    pub compositor_state: CompositorState,
    pub xdg_shell_state: XdgShellState,
    pub layer_shell_state: smithay::wayland::shell::wlr_layer::WlrLayerShellState,
    pub shm_state: ShmState,
    pub output_manager_state: OutputManagerState,
    pub seat_state: SeatState<Smallvil>,
    pub data_device_state: DataDeviceState,
    pub data_control_state: smithay::wayland::selection::wlr_data_control::DataControlState,
    pub popups: PopupManager,

    pub seat: Seat<Self>,
}

impl Smallvil {
    pub fn new(event_loop: &mut EventLoop<CalloopData>, display: Display<Self>) -> Self {
        let start_time = std::time::Instant::now();

        let dh = display.handle();

        let compositor_state = CompositorState::new::<Self>(&dh);
        let xdg_shell_state = XdgShellState::new::<Self>(&dh);
        let shm_state = ShmState::new::<Self>(&dh, vec![]);
        let output_manager_state = OutputManagerState::new_with_xdg_output::<Self>(&dh);
        let mut seat_state = SeatState::new();
        let data_device_state = DataDeviceState::new::<Self>(&dh);
        let popups = PopupManager::default();

        // A seat is a group of keyboards, pointer and touch devices.
        // A seat typically has a pointer and maintains a keyboard focus and a pointer focus.
        let mut seat: Seat<Self> = seat_state.new_wl_seat(&dh, "winit");

        // Notify clients that we have a keyboard, for the sake of the example we assume that keyboard is always present.
        // You may want to track keyboard hot-plug in real compositor.
        seat.add_keyboard(Default::default(), 200, 25).unwrap();

        // Notify clients that we have a pointer (mouse)
        // Here we assume that there is always pointer plugged in
        seat.add_pointer();

        // A space represents a two-dimensional plane. Windows and Outputs can be mapped onto it.
        //
        // Windows get a position and stacking order through mapping.
        // Outputs become views of a part of the Space and can be rendered via Space::render_output.
        let space = Space::default();

        let socket_name = Self::init_wayland_listener(display, event_loop);

        // Get the loop signal, used to stop the event loop
        let loop_signal = event_loop.get_signal();

        Self {
            start_time,
            display_handle: dh.clone(),
            layer_shell_state: smithay::wayland::shell::wlr_layer::WlrLayerShellState::new::<Self>(
                &dh,
            ),

            space,
            loop_signal,
            socket_name,
            ui_scale: 1.25,
            windows: BTreeMap::new(),
            layout: Desktop::default(),
            output_info: BTreeMap::new(),
            output_settings: Default::default(),
            config_file: None,
            config_error: None,
            layout_warning: None,
            config_revision: 0,
            config_poll: std::time::Instant::now(),
            default_output_scale: 1.25,
            configured_bindings: Vec::new(),
            applied_keyboard: Default::default(),
            window_preferences_applied: Default::default(),
            input_devices: Vec::new(),
            nested_canvas_size: None,
            virtual_outputs: 1,
            native_mode: false,
            vt_request: None,
            next_window: 1,
            configured: BTreeMap::new(),
            needs_redraw: true,
            shortcut_keys: Default::default(),
            dmabuf_state: DmabufState::new(),
            dmabuf_global: None,
            pending_imports: vec![],
            dmabuf_imports: 0,
            dmabuf_failures: 0,
            fractional_scale_state: FractionalScaleManagerState::new::<Self>(&dh),
            viewporter_state: ViewporterState::new::<Self>(&dh),
            decoration_state: XdgDecorationState::new::<Self>(&dh),
            primary_selection_state:
                smithay::wayland::selection::primary_selection::PrimarySelectionState::new::<Self>(
                    &dh,
                ),
            cursor_shape_state: smithay::wayland::cursor_shape::CursorShapeManagerState::new::<Self>(
                &dh,
            ),
            cursor_image: smithay::input::pointer::CursorImageStatus::Named(
                ::winit::window::CursorIcon::Default,
            ),
            drag_icon: None,
            cursor_rendered_elements: 0,
            popup_events: 0,
            popup_grabs: 0,
            test_input: false,
            session_mode: false,
            shortcut_modifier: Default::default(),
            screenshot: None,
            capture: Default::default(),
            commits: 0,
            rendered_frames: 0,
            forwarded_keys: 0,
            selection_updates: 0,
            runtime_error: None,

            compositor_state,
            xdg_shell_state,
            shm_state,
            output_manager_state,
            seat_state,
            data_device_state,
            // Clipboard helpers must not open a temporary window to acquire focus.
            data_control_state:
                smithay::wayland::selection::wlr_data_control::DataControlState::new::<Self, _>(
                    &dh,
                    None,
                    |_| true,
                ),
            popups,
            seat,
        }
    }

    fn init_wayland_listener(
        display: Display<Smallvil>,
        event_loop: &mut EventLoop<CalloopData>,
    ) -> OsString {
        // Creates a new listening socket, automatically choosing the next available `wayland` socket name.
        let listening_socket = ListeningSocketSource::new_auto().unwrap();

        // Get the name of the listening socket.
        // Clients will connect to this socket.
        let socket_name = listening_socket.socket_name().to_os_string();

        let loop_handle = event_loop.handle();

        loop_handle
            .insert_source(listening_socket, move |client_stream, _, state| {
                // Inside the callback, you should insert the client into the display.
                //
                // You may also associate some data with the client when inserting the client.
                state
                    .display_handle
                    .insert_client(client_stream, Arc::new(ClientState::default()))
                    .unwrap();
            })
            .expect("Failed to init the wayland event source.");

        // You also need to add the display itself to the event loop, so that client events will be processed by wayland-server.
        loop_handle
            .insert_source(
                Generic::new(display, Interest::READ, Mode::Level),
                |_, display, state| {
                    // Safety: we don't drop the display
                    unsafe {
                        display
                            .get_mut()
                            .dispatch_clients(&mut state.state)
                            .unwrap();
                    }
                    Ok(PostAction::Continue)
                },
            )
            .unwrap();

        socket_name
    }

    pub fn surface_under(
        &self,
        pos: Point<f64, Logical>,
    ) -> Option<(WlSurface, Point<f64, Logical>)> {
        use smithay::wayland::shell::wlr_layer::Layer;
        self.layer_under(pos, &[Layer::Overlay, Layer::Top])
            .or_else(|| {
                self.window_under(pos).and_then(|(window, location)| {
                    self.window_surface_at(window, pos - location.to_f64())
                        .map(|(s, p)| (s, (p + location).to_f64()))
                })
            })
            .or_else(|| self.layer_under(pos, &[Layer::Bottom, Layer::Background]))
    }

    pub fn window_under(&self, pos: Point<f64, Logical>) -> Option<(&Window, Point<i32, Logical>)> {
        let monitor = self.layout.at(pos.x, pos.y)?;
        self.space.elements().rev().find_map(|window| {
            let id = self.window_id(window.toplevel()?.wl_surface())?;
            if self.layout.owner(id) != Some(monitor) {
                return None;
            }
            let location = self.space.element_location(window)? - window.geometry().loc;
            self.window_surface_at(window, pos - location.to_f64())
                .map(|_| (window, location))
        })
    }

    fn window_surface_at(
        &self,
        window: &Window,
        point: Point<f64, Logical>,
    ) -> Option<(WlSurface, Point<i32, Logical>)> {
        if let Some(popup) = window.surface_under(
            point,
            WindowSurfaceType::POPUP | WindowSurfaceType::SUBSURFACE,
        ) {
            return Some(popup);
        }
        let id = self.window_id(window.toplevel()?.wl_surface())?;
        let radius = self.output_settings.decorations.corner_radius;
        if radius > 0
            && !self.layout.fullscreen_for(id)
            && !crate::decoration::contains(window.geometry(), radius, point)
        {
            return None;
        }
        window.surface_under(
            point,
            WindowSurfaceType::TOPLEVEL | WindowSurfaceType::SUBSURFACE,
        )
    }

    pub fn relayout(&mut self) {
        let pointer = self.seat.get_pointer().unwrap().current_location();
        let anchor = self.layout.at(pointer.x, pointer.y).map(|i| {
            let m = &self.layout.monitors[i];
            (
                m.name.clone(),
                (pointer.x - m.origin.0 as f64) * m.scale,
                (pointer.y - m.origin.1 as f64) * m.scale,
            )
        });
        let outputs: Vec<_> = self.space.outputs().cloned().collect();
        if outputs.is_empty() {
            return;
        }
        for output in &outputs {
            if self
                .output_info
                .get(&output.name())
                .is_none_or(|info| !info.adjustable_mode)
            {
                let mode = output.current_mode().unwrap();
                self.output_info.insert(
                    output.name(),
                    crate::output_config::OutputInfo::virtual_output(
                        output.name(),
                        (mode.size.w, mode.size.h),
                    ),
                );
            }
        }
        let placements = self.output_placements(&outputs);
        for placement in &placements {
            let output = outputs.iter().find(|o| o.name() == placement.name).unwrap();
            output.change_current_state(
                None,
                None,
                Some(smithay::output::Scale::Custom {
                    advertised_integer: 2,
                    fractional: placement.scale,
                }),
                None,
            );
        }
        let dead: Vec<_> = self
            .windows
            .iter()
            .filter_map(|(id, window)| (!window.alive()).then_some(*id))
            .collect();
        for id in dead {
            self.layout.remove(id);
            self.windows.remove(&id);
            self.configured.remove(&id);
            self.window_preferences_applied.remove(&id);
        }
        let specs = outputs
            .iter()
            .filter_map(|o| {
                o.current_mode().map(|mode| {
                    (
                        o.name(),
                        (mode.size.w, mode.size.h),
                        o.current_scale().fractional_scale(),
                    )
                })
            })
            .collect();
        let primary = self.primary_output();
        self.layout.sync_primary(specs, primary.as_deref());
        for monitor in &mut self.layout.monitors {
            monitor.origin = placements
                .iter()
                .find(|p| p.name == monitor.name)
                .unwrap()
                .origin;
        }
        self.apply_layout_preferences();
        for monitor in &self.layout.monitors {
            if let Some(output) = outputs.iter().find(|o| o.name() == monitor.name) {
                let origin = monitor.origin.into();
                output.change_current_state(None, None, None, Some(origin));
                self.space.map_output(output, origin);
            }
        }
        self.ui_scale = self.layout.current().scale;
        self.arrange_layers();
        self.apply_positions();
        let position = anchor
            .and_then(|(name, x, y)| {
                self.layout
                    .monitors
                    .iter()
                    .find(|m| m.name == name)
                    .map(|m| {
                        (
                            m.origin.0 as f64 + x / m.scale,
                            m.origin.1 as f64 + y / m.scale,
                        )
                    })
            })
            .unwrap_or((pointer.x, pointer.y));
        let position = self.layout.clamp(position.0, position.1);
        self.process_motion(
            position.into(),
            self.start_time.elapsed().as_millis() as u32,
        );
    }

    pub fn focus_next(&mut self) {
        self.layout.focus_delta(1);
        self.sync_focus();
    }

    pub fn window_id(&self, surface: &WlSurface) -> Option<WindowId> {
        self.windows.iter().find_map(|(id, window)| {
            (window.toplevel().unwrap().wl_surface() == surface).then_some(*id)
        })
    }

    pub fn focus_id(&mut self, id: i64) -> Result<(), String> {
        let id = u64::try_from(id).map_err(|_| "Window id must be positive")?;
        if !self.windows.get(&id).is_some_and(|window| window.alive()) {
            return Err("Window does not exist".into());
        }
        self.layout.focus(id);
        Ok(())
    }

    pub fn add_window(&mut self, window: Window) {
        let id = self.next_window;
        self.next_window += 1;
        self.windows.insert(id, window);
        self.layout.insert(id);
        self.relayout();
        self.sync_focus();
    }

    pub fn apply_positions(&mut self) {
        self.apply_window_preferences();
        use smithay::reexports::wayland_protocols::xdg::shell::server::xdg_toplevel::State;
        for (id, window) in &self.windows {
            let (min, max) = window_width_limits(window);
            self.layout.constrain_width(*id, min, max);
        }
        let geometries = self.layout.geometries();
        for (id, window) in &self.windows {
            if !geometries.iter().any(|geometry| geometry.0 == *id) {
                self.space.unmap_elem(window);
            }
        }
        for (id, x, y, width, height) in geometries {
            let Some(window) = self.windows.get(&id).cloned() else {
                continue;
            };
            let fullscreen = self.layout.fullscreen_for(id);
            let maximized = self.layout.maximized_for(id);
            let configuration = (width, height, fullscreen, maximized);
            if self.configured.get(&id) != Some(&configuration) {
                let toplevel = window.toplevel().unwrap();
                toplevel.with_pending_state(|state| {
                    state.size = Some((width, height).into());
                    for edge in [
                        State::TiledLeft,
                        State::TiledRight,
                        State::TiledTop,
                        State::TiledBottom,
                    ] {
                        state.states.set(edge);
                    }
                    if maximized {
                        state.states.set(State::Maximized);
                    } else {
                        state.states.unset(State::Maximized);
                    }
                    if fullscreen {
                        state.states.set(State::Fullscreen);
                    } else {
                        state.states.unset(State::Fullscreen);
                    }
                });
                if toplevel.is_initial_configure_sent() {
                    toplevel.send_pending_configure();
                }
                self.configured.insert(id, configuration);
            }
            self.space.map_element(window, (x, y), false);
        }
        if let Some(window) = self.layout.focused().and_then(|id| self.windows.get(&id)) {
            self.space.raise_element(window, false);
        }
        self.needs_redraw = true;
    }

    pub fn sync_focus(&mut self) {
        self.ui_scale = self.layout.current().scale;
        let focused = self.layout.focused();
        for (id, window) in &self.windows {
            window.set_activated(Some(*id) == focused);
            if window.toplevel().unwrap().is_initial_configure_sent() {
                window.toplevel().unwrap().send_pending_configure();
            }
        }
        self.sync_keyboard_focus();
        self.apply_positions();
    }

    pub fn sync_keyboard_focus(&mut self) {
        let surface = self.exclusive_layer_focus().or_else(|| {
            self.layout
                .focused()
                .and_then(|id| self.windows.get(&id))
                .map(|window| window.toplevel().unwrap().wl_surface().clone())
        });
        let keyboard = self.seat.get_keyboard().unwrap();
        if keyboard.current_focus() != surface {
            keyboard.set_focus(self, surface, smithay::utils::SERIAL_COUNTER.next_serial());
        }
    }

    pub fn action(&mut self, action: &str, value: Option<i64>) -> Result<(), String> {
        let roots: Vec<_> = self
            .windows
            .values()
            .map(|window| window.toplevel().unwrap().wl_surface().clone())
            .collect();
        for root in roots {
            let popups: Vec<_> = PopupManager::popups_for_surface(&root)
                .map(|(popup, _)| popup)
                .collect();
            for popup in popups {
                let _ = PopupManager::dismiss_popup(&root, &popup);
            }
        }
        let serial = smithay::utils::SERIAL_COUNTER.next_serial();
        if let Some(keyboard) = self.seat.get_keyboard() {
            if keyboard.is_grabbed() {
                keyboard.unset_grab(self);
            }
        }
        if let Some(pointer) = self.seat.get_pointer() {
            if pointer.is_grabbed() {
                pointer.unset_grab(self, serial, self.start_time.elapsed().as_millis() as u32);
            }
        }
        match action {
            "focus-next" => self.layout.focus_delta(1),
            "focus-next-wrap" => self.layout.focus_next_wrapping(),
            "focus-prev" => self.layout.focus_delta(-1),
            "focus" => self.focus_id(value.ok_or("focus needs a window id")?)?,
            "move-next" => self.layout.reorder(1),
            "move-prev" => self.layout.reorder(-1),
            "resize" => self.layout.resize(
                value
                    .ok_or("resize needs a pixel delta")?
                    .clamp(-2000, 2000) as i32,
            ),
            "cycle-width" => {
                let direction = value.unwrap_or(1);
                if ![-1, 1].contains(&direction) {
                    return Err("cycle-width direction must be 1 or -1".into());
                }
                let (min, max) = self
                    .layout
                    .focused()
                    .and_then(|id| self.windows.get(&id))
                    .map(window_width_limits)
                    .unwrap_or((0, 0));
                self.layout.cycle_width(direction < 0, min, max);
            }
            "workspace-prev" => self.layout.cycle_workspace(true),
            "workspace-next" => self.layout.cycle_workspace(false),
            "move-workspace-prev" => self.layout.move_to_adjacent_workspace(true),
            "move-workspace-next" => self.layout.move_to_adjacent_workspace(false),
            "workspace" => {
                let index = value.ok_or("workspace needs an index from 1 to 4")?;
                if !(1..=4).contains(&index) {
                    return Err("Workspace must be from 1 to 4".into());
                }
                self.layout.switch_workspace(index as usize - 1);
            }
            "move-workspace" => {
                let index = value.ok_or("move-workspace needs an index from 1 to 4")?;
                if !(1..=4).contains(&index) {
                    return Err("Workspace must be from 1 to 4".into());
                }
                self.layout.move_to_workspace(index as usize - 1);
            }
            "fullscreen" => self.layout.toggle_fullscreen(),
            "maximize" => self.layout.toggle_maximize(),
            "focus-output-next" => self.layout.monitor_delta(1, false),
            "focus-output-prev" => self.layout.monitor_delta(-1, false),
            "move-output-next" => self.layout.monitor_delta(1, true),
            "move-output-prev" => self.layout.monitor_delta(-1, true),
            "output" => {
                let index = value.ok_or("output needs a 1-based index")?;
                if index < 1 || index as usize > self.layout.monitors.len() {
                    return Err("Output does not exist".into());
                }
                self.layout.focus_monitor(index as usize - 1);
            }
            "vt" if self.native_mode => self.vt_request = value.map(|v| v as i32),
            "scale" | "scale-adjust" => {
                let value = if action == "scale-adjust" {
                    let delta = value.ok_or("scale-adjust needs a percentage point delta")?;
                    Some(
                        ((self.ui_scale * 100.0).round() as i64)
                            .saturating_add(delta)
                            .clamp(50, 200),
                    )
                } else {
                    value
                };
                let scale = match value {
                    Some(percent) if (50..=200).contains(&percent) => percent as f64 / 100.0,
                    Some(_) => return Err("Scale must be 50 to 200 percent".into()),
                    None => {
                        if self.ui_scale >= 2.0 {
                            1.0
                        } else {
                            (self.ui_scale * 4.0).floor() / 4.0 + 0.25
                        }
                    }
                };
                return self.output_request("configure-outputs",&serde_json::json!({"outputs":[{"name":self.layout.current().name,"scale":scale}]}));
            }
            "terminal" => {
                if self.session_mode {
                    crate::spawn_session_tool(&self.socket_name, "TERMINAL")
                        .map_err(|error| error.to_string())?;
                } else {
                    crate::spawn_terminal(&self.socket_name, false)
                        .map_err(|error| error.to_string())?;
                }
            }
            "launcher" => crate::spawn_session_tool(&self.socket_name, "LAUNCHER")
                .map_err(|error| error.to_string())?,
            "logout" => crate::spawn_session_tool(&self.socket_name, "LOGOUT")
                .map_err(|error| error.to_string())?,
            "close" => {
                if let Some(window) = self.layout.focused().and_then(|id| self.windows.get(&id)) {
                    window.toplevel().unwrap().send_close();
                }
            }
            _ => return Err(format!("Unknown action: {action}")),
        }
        self.sync_focus();
        Ok(())
    }

    pub fn status(&self) -> serde_json::Value {
        use smithay::{
            backend::renderer::utils::RendererSurfaceStateUserData,
            wayland::{compositor::with_states, shell::xdg::XdgToplevelSurfaceData},
        };
        let cursor = match &self.cursor_image {
            smithay::input::pointer::CursorImageStatus::Named(_) => {
                serde_json::json!({"kind":"named"})
            }
            smithay::input::pointer::CursorImageStatus::Hidden => {
                serde_json::json!({"kind":"hidden"})
            }
            smithay::input::pointer::CursorImageStatus::Surface(surface) => {
                serde_json::json!({"kind":"surface","alive":surface.alive()})
            }
        };
        let pointer = self.seat.get_pointer().unwrap().current_location();
        let windows: Vec<_> = self.windows.iter().map(|(id, window)| {
            // Popup lookup accesses surface state too; do it before taking
            // the surface-state lock used for client metadata.
            let popups = PopupManager::popups_for_surface(window.toplevel().unwrap().wl_surface()).count();
            let client_geometry = window.geometry();
            with_states(window.toplevel().unwrap().wl_surface(), |states| {
                let metadata = states.data_map.get::<XdgToplevelSurfaceData>().unwrap().lock().unwrap();
                let (scale, size, surface_size) = states.data_map.get::<RendererSurfaceStateUserData>().map(|state| {
                    let state = state.lock().unwrap();
                    (state.buffer_scale(), state.buffer_size().map(|size| (size.w, size.h)), state.surface_size().map(|size| (size.w, size.h)))
                }).unwrap_or((1, None, None));
                let owner=self.layout.owner(*id);
                let layout=owner.map(|i|&self.layout.monitors[i].layout);
                let workspace = layout.and_then(|l|l.workspaces.iter().position(|workspace| workspace.columns.iter().any(|column| column.id == *id)));
                let width = workspace.and_then(|index| layout.unwrap().workspaces[index].columns.iter().find(|column| column.id == *id)).map(|column| column.width);
                let density = size.zip(surface_size).filter(|(_, surface)| surface.0 > 0).map(|(buffer, surface)| buffer.0 as f64 * scale as f64 / surface.0 as f64);
                let geometry = self.layout.geometries().into_iter().find(|geometry| geometry.0 == *id).map(|(_, x, y, w, h)| (x,y,w,h));
                let target_geometry = self.layout.target_geometries().into_iter().find(|geometry| geometry.0 == *id).map(|(_, x, y, w, h)| (x,y,w,h));
                serde_json::json!({"id":id,"title":metadata.title,"app_id":metadata.app_id,"output":owner.map(|i|&self.layout.monitors[i].name),"workspace":workspace.map(|i| i + 1),"width":width,"buffer_scale":scale,"render_density":density,"logical_buffer_size":size,"surface_size":surface_size,"geometry":geometry,"target_geometry":target_geometry,"moving":layout.is_some_and(|l| l.is_moving(*id)),"client_geometry":[client_geometry.loc.x,client_geometry.loc.y,client_geometry.size.w,client_geometry.size.h],"popups":popups,"focused":self.layout.focused()==Some(*id)})
            })
        }).collect();
        let keyboard_focus = self
            .seat
            .get_keyboard()
            .and_then(|keyboard| keyboard.current_focus())
            .and_then(|surface| self.window_id(&surface));
        let modifiers = self
            .seat
            .get_keyboard()
            .map(|keyboard| keyboard.modifier_state());
        let outputs: Vec<_> = self.layout.monitors.iter().enumerate().filter(|(_,m)|self.space.outputs().any(|o|o.name()==m.name)).map(|(i,m)| {
            let info=self.output_info.get(&m.name);
            let mode=self.space.outputs().find(|o|o.name()==m.name).and_then(|o|o.current_mode());
            let output = self.space.outputs().find(|o| o.name() == m.name).unwrap();
            let map = smithay::desktop::layer_map_for_output(output);
            let layers: Vec<_> = map.layers().map(|layer| {
                let geometry = map.layer_geometry(layer);
                serde_json::json!({"namespace":layer.namespace(),"geometry":geometry.map(|g| (g.loc.x,g.loc.y,g.size.w,g.size.h))})
            }).collect();
            serde_json::json!({"name":m.name,"id":info.map(|i|&i.id),"make":info.map(|i|&i.make),"model":info.map(|i|&i.model),"modes":info.map(|i|&i.modes),"mode":mode.map(|m|serde_json::json!({"width":m.size.w,"height":m.size.h,"refresh":m.refresh})),"position":m.origin,"physical_size":m.physical_size,"logical_size":m.layout.size,"work_area":m.layout.work_area,"layers":layers,"scale":m.scale,"workspace":m.layout.active+1,"primary":self.primary_output().as_deref()==Some(&m.name),"focused":i==self.layout.active_monitor})
        }).collect();
        serde_json::json!({"preferences":{"clipboard":self.output_settings.clipboard,"decorations":self.output_settings.decorations,"input":self.output_settings.input,"layout":self.output_settings.layout,"bindings":self.output_settings.bindings,"window_rules":self.output_settings.window_rules,"animations":self.output_settings.animations},"input_devices":self.input_devices,"config_path":self.config_file.as_ref().map(|f|f.path.to_string_lossy()),"config_error":self.config_error,"layout_warning":self.layout_warning,"config_revision":self.config_revision,"outputs":outputs,"backend":if self.native_mode {"drm"} else {"winit"},"active_output":self.layout.current().name,"pid":std::process::id(),"wayland_display":self.socket_name.to_string_lossy(),"workspace":self.layout.active+1,"focused":self.layout.focused(),"keyboard_focus":keyboard_focus,"modifiers":modifiers.map(|modifiers| serde_json::json!({"logo":modifiers.logo,"alt":modifiers.alt,"ctrl":modifiers.ctrl,"shift":modifiers.shift})),"fullscreen":self.layout.workspace().fullscreen,"viewport_size":self.layout.size,"viewport":self.layout.workspace().scroll,"viewport_target":self.layout.workspace().target,"display_scale":self.ui_scale,"shortcut_modifier":self.shortcut_modifier.name(),"cursor":cursor,"cursor_rendered_elements":self.cursor_rendered_elements,"pointer_position":[pointer.x,pointer.y],"windows":windows,"surface_commits":self.commits,"rendered_frames":self.rendered_frames,"forwarded_keys":self.forwarded_keys,"selection_updates":self.selection_updates,"dmabuf_imports":self.dmabuf_imports,"dmabuf_failures":self.dmabuf_failures,"popup_events":self.popup_events,"popup_grabs":self.popup_grabs})
    }
}

#[derive(Default)]
pub struct ClientState {
    pub compositor_state: CompositorClientState,
}

fn window_width_limits(window: &Window) -> (i32, i32) {
    smithay::wayland::compositor::with_states(window.toplevel().unwrap().wl_surface(), |states| {
        let mut cached = states
            .cached_state
            .get::<smithay::wayland::shell::xdg::SurfaceCachedState>();
        let state = cached.current();
        (state.min_size.w, state.max_size.w)
    })
}

impl ClientData for ClientState {
    fn initialized(&self, _client_id: ClientId) {}
    fn disconnected(&self, _client_id: ClientId, _reason: DisconnectReason) {}
}
