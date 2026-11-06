use std::{
    collections::VecDeque,
    time::{Duration, Instant},
};

use smithay::{
    input::Seat,
    reexports::wayland_server::{backend::ClientId, protocol::wl_surface::WlSurface, Resource},
    utils::Serial,
    wayland::xdg_activation::{
        XdgActivationHandler, XdgActivationState, XdgActivationToken, XdgActivationTokenData,
    },
};

use crate::Smallvil;

const ACTIVATION_TIMEOUT: Duration = Duration::from_secs(10);

#[derive(Default)]
pub(crate) struct RecentInput(VecDeque<(Serial, ClientId, Instant)>);

impl RecentInput {
    fn record(&mut self, serial: Serial, client: ClientId) {
        self.0
            .retain(|(_, _, time)| time.elapsed() < ACTIVATION_TIMEOUT);
        // Bound storage even when a client never asks for activation.
        if self.0.len() >= 32 {
            self.0.pop_front();
        }
        self.0.push_back((serial, client, Instant::now()));
    }

    fn consume(&mut self, serial: Serial, client: &ClientId) -> bool {
        let Some(index) = self.0.iter().position(|(event, owner, time)| {
            *event == serial && owner == client && time.elapsed() < ACTIVATION_TIMEOUT
        }) else {
            return false;
        };
        self.0.remove(index);
        true
    }
}

impl Smallvil {
    pub(crate) fn record_activation_input(&mut self, serial: Serial, surface: Option<WlSurface>) {
        let Some(client) = surface.and_then(|surface| surface.client()) else {
            return;
        };
        self.activation_input.record(serial, client.id());
    }
}

impl XdgActivationHandler for Smallvil {
    fn activation_state(&mut self) -> &mut XdgActivationState {
        &mut self.activation_state
    }

    fn token_created(&mut self, _token: XdgActivationToken, data: XdgActivationTokenData) -> bool {
        self.activation_state
            .retain_tokens(|_, data| data.timestamp.elapsed() < ACTIVATION_TIMEOUT);
        let Some((serial, seat)) = data.serial else {
            return false;
        };
        if Seat::<Self>::from_resource(&seat).as_ref() != Some(&self.seat) {
            return false;
        }
        // The click belongs to Mako, not to the application it will activate.
        // Check the requesting client rather than the current keyboard focus.
        let Some(client) = data.client_id else {
            return false;
        };
        self.activation_input.consume(serial, &client)
    }

    fn request_activation(
        &mut self,
        token: XdgActivationToken,
        data: XdgActivationTokenData,
        surface: WlSurface,
    ) {
        // A notification action grants one short-lived activation, not ongoing
        // permission to steal focus. The app supplies its exact target surface.
        if !self.activation_state.remove_token(&token)
            || data.timestamp.elapsed() >= ACTIVATION_TIMEOUT
        {
            return;
        }
        if let Some(id) = self.window_id(&surface) {
            self.layout.focus(id);
            self.relayout();
            self.sync_focus();
            self.needs_redraw = true;
        }
    }
}

smithay::delegate_xdg_activation!(Smallvil);

#[cfg(test)]
mod tests {
    use super::*;
    use smithay::reexports::wayland_server::Display;
    use std::{os::unix::net::UnixStream, sync::Arc};

    fn client_ids() -> (ClientId, ClientId) {
        let display = Display::<Smallvil>::new().unwrap();
        let mut handle = display.handle();
        let (first, _first_peer) = UnixStream::pair().unwrap();
        let (second, _second_peer) = UnixStream::pair().unwrap();
        let first = handle
            .insert_client(first, Arc::new(crate::state::ClientState::default()))
            .unwrap();
        let second = handle
            .insert_client(second, Arc::new(crate::state::ClientState::default()))
            .unwrap();
        (first.id(), second.id())
    }

    #[test]
    fn input_grants_belong_to_one_client_and_cannot_be_reused() {
        let (owner, other) = client_ids();
        let mut input = RecentInput::default();
        input.record(42.into(), owner.clone());
        assert!(!input.consume(42.into(), &other));
        assert!(!input.consume(43.into(), &owner));
        assert!(input.consume(42.into(), &owner));
        assert!(!input.consume(42.into(), &owner));
    }

    #[test]
    fn expired_input_cannot_grant_activation_and_storage_is_bounded() {
        let (owner, _) = client_ids();
        let mut input = RecentInput::default();
        input.0.push_back((
            42.into(),
            owner.clone(),
            Instant::now() - ACTIVATION_TIMEOUT,
        ));
        assert!(!input.consume(42.into(), &owner));
        for serial in 100..140 {
            input.record(serial.into(), owner.clone());
        }
        assert_eq!(input.0.len(), 32);
        assert!(!input.consume(100.into(), &owner));
        assert!(input.consume(139.into(), &owner));
    }
}
