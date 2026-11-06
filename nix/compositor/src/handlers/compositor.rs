use crate::{grabs::resize_grab, state::ClientState, Smallvil};
use smithay::{
    backend::renderer::utils::on_commit_buffer_handler,
    delegate_compositor, delegate_shm,
    reexports::calloop::Interest,
    reexports::wayland_server::{
        protocol::{wl_buffer, wl_surface::WlSurface},
        Client, Resource,
    },
    wayland::{
        buffer::BufferHandler,
        compositor::{
            add_blocker, add_pre_commit_hook, get_parent, is_sync_subsurface, with_states,
            BufferAssignment, CompositorClientState, CompositorHandler, CompositorState,
            SurfaceAttributes,
        },
        dmabuf::get_dmabuf,
        shm::{ShmHandler, ShmState},
    },
};

use super::xdg_shell;

impl CompositorHandler for Smallvil {
    fn new_surface(&mut self, surface: &WlSurface) {
        // Keep the previous contents until the client's GPU has finished writing.
        // A pre-commit blocker also preserves synchronized subsurface transactions.
        add_pre_commit_hook::<Self, _>(surface, |state, _dh, surface| {
            let dmabuf = with_states(surface, |states| {
                states
                    .cached_state
                    .get::<SurfaceAttributes>()
                    .pending()
                    .buffer
                    .as_ref()
                    .and_then(|assignment| match assignment {
                        BufferAssignment::NewBuffer(buffer) => get_dmabuf(buffer).cloned().ok(),
                        _ => None,
                    })
            });
            let Some(dmabuf) = dmabuf else { return };
            let Ok((blocker, source)) = dmabuf.generate_blocker(Interest::READ) else {
                return;
            };
            let Some(client) = surface.client() else {
                return;
            };
            match state.loop_handle.insert_source(source, move |_, _, data| {
                let dh = data.display_handle.clone();
                data.state
                    .client_compositor_state(&client)
                    .blocker_cleared(&mut data.state, &dh);
                Ok(())
            }) {
                Ok(_) => add_blocker(surface, blocker),
                Err(error) => eprintln!("Failed to monitor client GPU readiness: {error}"),
            }
        });
        self.client_surfaces.push(surface.clone());
        self.update_client_scale(surface);
    }

    fn new_subsurface(&mut self, surface: &WlSurface, _parent: &WlSurface) {
        self.update_client_scale(surface);
    }

    fn destroyed(&mut self, surface: &WlSurface) {
        self.client_surfaces.retain(|known| known != surface);
    }
    fn compositor_state(&mut self) -> &mut CompositorState {
        &mut self.compositor_state
    }

    fn client_compositor_state<'a>(&self, client: &'a Client) -> &'a CompositorClientState {
        &client.get_data::<ClientState>().unwrap().compositor_state
    }

    fn commit(&mut self, surface: &WlSurface) {
        self.commits += 1;
        self.needs_redraw = true;
        self.update_client_scale(surface);
        on_commit_buffer_handler::<Self>(surface);
        if !is_sync_subsurface(surface) {
            let mut root = surface.clone();
            while let Some(parent) = get_parent(&root) {
                root = parent;
            }
            if let Some(window) = self
                .space
                .elements()
                .find(|w| w.toplevel().unwrap().wl_surface() == &root)
            {
                window.on_commit();
            }
        };

        self.apply_task_placement(surface);
        if self.apply_window_preferences() {
            self.apply_positions();
        }
        xdg_shell::handle_commit(&mut self.popups, &self.space, surface);
        resize_grab::handle_commit(&mut self.space, surface);
        self.commit_layer(surface);
    }
}

impl BufferHandler for Smallvil {
    fn buffer_destroyed(&mut self, _buffer: &wl_buffer::WlBuffer) {}
}

impl ShmHandler for Smallvil {
    fn shm_state(&self) -> &ShmState {
        &self.shm_state
    }
}

delegate_compositor!(Smallvil);
delegate_shm!(Smallvil);
