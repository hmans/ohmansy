//! Standard image capture. Like wlr-screencopy, these globals trust local
//! Wayland clients; the desktop portal owns application consent.
use std::{collections::BTreeMap, sync::Mutex};

use crate::{layout::WindowId, Smallvil};
use smithay::{
    backend::renderer::gles::GlesRenderer,
    output::Output,
    reexports::{
        wayland_protocols::ext::{
            image_capture_source::v1::server::{
                ext_foreign_toplevel_image_capture_source_manager_v1::ExtForeignToplevelImageCaptureSourceManagerV1 as WindowManager,
                ext_image_capture_source_v1::ExtImageCaptureSourceV1 as Source,
                ext_output_image_capture_source_manager_v1::ExtOutputImageCaptureSourceManagerV1 as OutputManager,
            },
            image_copy_capture::v1::server::{
                ext_image_copy_capture_cursor_session_v1::{
                    self as cursor, ExtImageCopyCaptureCursorSessionV1 as CursorSession,
                },
                ext_image_copy_capture_frame_v1::{
                    self as frame, ExtImageCopyCaptureFrameV1 as Frame,
                },
                ext_image_copy_capture_manager_v1::{
                    self as manager, ExtImageCopyCaptureManagerV1 as Manager,
                },
                ext_image_copy_capture_session_v1::{
                    self as session, ExtImageCopyCaptureSessionV1 as Session,
                },
            },
        },
        wayland_server::{
            protocol::{wl_buffer::WlBuffer, wl_shm},
            Client, DataInit, Dispatch, DisplayHandle, GlobalDispatch, New, Resource, Weak,
        },
    },
    utils::IsAlive,
    wayland::{
        compositor::with_states,
        foreign_toplevel_list::{
            ForeignToplevelHandle, ForeignToplevelListHandler, ForeignToplevelListState,
        },
        shell::xdg::XdgToplevelSurfaceData,
    },
};

#[derive(Clone)]
pub enum Target {
    Output(Output),
    Window(WindowId),
    Unavailable,
}

pub struct CaptureState {
    pub list: ForeignToplevelListState,
    handles: BTreeMap<WindowId, ForeignToplevelHandle>,
    sessions: Vec<Session>,
    pending: Vec<Frame>,
}

pub struct SessionData {
    target: Target,
    cursor: bool,
    inner: Mutex<SessionInner>,
}
#[derive(Default)]
struct SessionInner {
    size: Option<(i32, i32)>,
    stopped: bool,
    frame: Option<Weak<Frame>>,
}
pub struct FrameData {
    session: Session,
    inner: Mutex<FrameInner>,
}
#[derive(Default)]
struct FrameInner {
    buffer: Option<WlBuffer>,
    captured: bool,
}
#[derive(Default)]
pub struct CursorData {
    requested: Mutex<bool>,
}

impl CaptureState {
    pub fn new(dh: &DisplayHandle) -> Self {
        dh.create_global::<Smallvil, Manager, _>(1, ());
        dh.create_global::<Smallvil, OutputManager, _>(1, ());
        dh.create_global::<Smallvil, WindowManager, _>(1, ());
        Self {
            list: ForeignToplevelListState::new::<Smallvil>(dh),
            handles: BTreeMap::new(),
            sessions: Vec::new(),
            pending: Vec::new(),
        }
    }
}

impl ForeignToplevelListHandler for Smallvil {
    fn foreign_toplevel_list_state(&mut self) -> &mut ForeignToplevelListState {
        &mut self.image_capture.list
    }
}
smithay::delegate_foreign_toplevel_list!(Smallvil);

macro_rules! global {
    ($ty:ty) => {
        impl GlobalDispatch<$ty, ()> for Smallvil {
            fn bind(
                _: &mut Self,
                _: &DisplayHandle,
                _: &Client,
                object: New<$ty>,
                _: &(),
                data: &mut DataInit<'_, Self>,
            ) {
                data.init(object, ());
            }
        }
    };
}
global!(Manager);
global!(OutputManager);
global!(WindowManager);

impl Dispatch<OutputManager, ()> for Smallvil {
    fn request(
        _: &mut Self,
        _: &Client,
        _: &OutputManager,
        request: <OutputManager as Resource>::Request,
        _: &(),
        _: &DisplayHandle,
        data: &mut DataInit<'_, Self>,
    ) {
        use smithay::reexports::wayland_protocols::ext::image_capture_source::v1::server::ext_output_image_capture_source_manager_v1::Request;
        if let Request::CreateSource { source, output } = request {
            data.init(
                source,
                Output::from_resource(&output)
                    .map(Target::Output)
                    .unwrap_or(Target::Unavailable),
            );
        }
    }
}
impl Dispatch<WindowManager, ()> for Smallvil {
    fn request(
        state: &mut Self,
        _: &Client,
        _: &WindowManager,
        request: <WindowManager as Resource>::Request,
        _: &(),
        _: &DisplayHandle,
        data: &mut DataInit<'_, Self>,
    ) {
        use smithay::reexports::wayland_protocols::ext::image_capture_source::v1::server::ext_foreign_toplevel_image_capture_source_manager_v1::Request;
        if let Request::CreateSource {
            source,
            toplevel_handle,
        } = request
        {
            let target = ForeignToplevelHandle::from_resource(&toplevel_handle)
                .filter(|handle| !handle.is_closed())
                .and_then(|handle| handle.user_data().get::<WindowId>().copied())
                .filter(|id| state.windows.contains_key(id))
                .map(Target::Window)
                .unwrap_or(Target::Unavailable);
            data.init(source, target);
        }
    }
}
impl Dispatch<Source, Target> for Smallvil {
    fn request(
        _: &mut Self,
        _: &Client,
        _: &Source,
        _: <Source as Resource>::Request,
        _: &Target,
        _: &DisplayHandle,
        _: &mut DataInit<'_, Self>,
    ) {
    }
}

impl Dispatch<Manager, ()> for Smallvil {
    fn request(
        state: &mut Self,
        _: &Client,
        resource: &Manager,
        request: manager::Request,
        _: &(),
        _: &DisplayHandle,
        data: &mut DataInit<'_, Self>,
    ) {
        match request {
            manager::Request::CreateSession {
                session,
                source,
                options,
            } => {
                let options = u32::from(options);
                if options & !1 != 0 {
                    resource.post_error(manager::Error::InvalidOption, "Invalid capture options");
                    return;
                }
                let target = source
                    .data::<Target>()
                    .cloned()
                    .unwrap_or(Target::Unavailable);
                let session = data.init(
                    session,
                    SessionData {
                        target,
                        cursor: options & 1 != 0,
                        inner: Mutex::default(),
                    },
                );
                state.update_capture_session(&session);
                state.image_capture.sessions.push(session);
            }
            manager::Request::CreatePointerCursorSession { session, .. } => {
                // Cursor metadata streams aren't used by our portal (it offers
                // hidden/embedded cursors). An unsupported stream stops cleanly.
                data.init(session, CursorData::default());
            }
            _ => (),
        }
    }
}
impl Dispatch<CursorSession, CursorData> for Smallvil {
    fn request(
        _: &mut Self,
        _: &Client,
        resource: &CursorSession,
        request: cursor::Request,
        user: &CursorData,
        _: &DisplayHandle,
        data: &mut DataInit<'_, Self>,
    ) {
        if let cursor::Request::GetCaptureSession { session } = request {
            let mut requested = user.requested.lock().unwrap();
            if *requested {
                resource.post_error(
                    cursor::Error::DuplicateSession,
                    "Cursor session already requested",
                );
                return;
            }
            *requested = true;
            let session = data.init(
                session,
                SessionData {
                    target: Target::Unavailable,
                    cursor: false,
                    inner: Mutex::new(SessionInner {
                        stopped: true,
                        ..Default::default()
                    }),
                },
            );
            session.stopped();
        }
    }
}
impl Dispatch<Session, SessionData> for Smallvil {
    fn request(
        _: &mut Self,
        _: &Client,
        resource: &Session,
        request: session::Request,
        user: &SessionData,
        _: &DisplayHandle,
        data: &mut DataInit<'_, Self>,
    ) {
        if let session::Request::CreateFrame { frame } = request {
            let mut inner = user.inner.lock().unwrap();
            if inner
                .frame
                .as_ref()
                .and_then(|f| f.upgrade().ok())
                .is_some()
            {
                resource.post_error(
                    session::Error::DuplicateFrame,
                    "Previous frame has not been destroyed",
                );
                return;
            }
            let frame = data.init(
                frame,
                FrameData {
                    session: resource.clone(),
                    inner: Mutex::default(),
                },
            );
            inner.frame = Some(frame.downgrade());
        }
    }
}
impl Dispatch<Frame, FrameData> for Smallvil {
    fn request(
        state: &mut Self,
        _: &Client,
        resource: &Frame,
        request: frame::Request,
        user: &FrameData,
        _: &DisplayHandle,
        _: &mut DataInit<'_, Self>,
    ) {
        if matches!(request, frame::Request::Destroy) {
            return;
        }
        let mut inner = user.inner.lock().unwrap();
        if inner.captured {
            resource.post_error(frame::Error::AlreadyCaptured, "Frame already submitted");
            return;
        }
        match request {
            frame::Request::AttachBuffer { buffer } => inner.buffer = Some(buffer),
            frame::Request::DamageBuffer {
                x,
                y,
                width,
                height,
            } => {
                if x < 0 || y < 0 || width <= 0 || height <= 0 {
                    resource.post_error(frame::Error::InvalidBufferDamage, "Invalid buffer damage");
                }
            }
            frame::Request::Capture => {
                if inner.buffer.is_none() {
                    resource.post_error(frame::Error::NoBuffer, "No buffer attached");
                    return;
                }
                inner.captured = true;
                state.image_capture.pending.push(resource.clone());
                state.needs_redraw = true;
            }
            _ => (),
        }
    }
}

impl Smallvil {
    fn capture_size(&self, target: &Target) -> Option<(i32, i32)> {
        let size = match target {
            Target::Output(output) => {
                self.space
                    .outputs()
                    .find(|o| *o == output)?
                    .current_mode()?
                    .size
            }
            Target::Window(id) => {
                let window = self.windows.get(id).filter(|w| w.alive())?;
                let scale = self.layout.monitors.get(self.layout.owner(*id)?)?.scale;
                window
                    .bbox_with_popups()
                    .size
                    .to_physical_precise_round(scale)
            }
            Target::Unavailable => return None,
        };
        (size.w > 0
            && size.h > 0
            && size.w <= 16384
            && size.h <= 16384
            && i64::from(size.w) * i64::from(size.h) <= 64 * 1024 * 1024)
            .then_some((size.w, size.h))
    }

    fn update_capture_session(&self, session: &Session) {
        let data = session.data::<SessionData>().unwrap();
        let mut inner = data.inner.lock().unwrap();
        if inner.stopped {
            return;
        }
        let Some(size) = self.capture_size(&data.target) else {
            inner.stopped = true;
            session.stopped();
            return;
        };
        if inner.size != Some(size) {
            inner.size = Some(size);
            session.buffer_size(size.0 as u32, size.1 as u32);
            session.shm_format(wl_shm::Format::Xrgb8888);
            session.done();
        }
    }

    pub fn maintain_capture_sources(&mut self) {
        self.image_capture.handles.retain(|id, handle| {
            if self.windows.get(id).is_some_and(|w| w.alive()) {
                true
            } else {
                handle.send_closed();
                false
            }
        });
        for (id, window) in &self.windows {
            if !window.alive() || window.bbox().size.w <= 0 {
                continue;
            }
            let (title, app_id) = with_states(window.toplevel().unwrap().wl_surface(), |states| {
                let metadata = states
                    .data_map
                    .get::<XdgToplevelSurfaceData>()
                    .unwrap()
                    .lock()
                    .unwrap();
                (
                    metadata.title.clone().unwrap_or_default(),
                    metadata.app_id.clone().unwrap_or_default(),
                )
            });
            let handle = self.image_capture.handles.entry(*id).or_insert_with(|| {
                let handle = self
                    .image_capture
                    .list
                    .new_toplevel::<Self>(title.clone(), app_id.clone());
                handle.user_data().insert_if_missing(|| *id);
                handle
            });
            if handle.title() != title || handle.app_id() != app_id {
                handle.send_title(&title);
                handle.send_app_id(&app_id);
                handle.send_done();
            }
        }
        self.image_capture.sessions.retain(Resource::is_alive);
        for session in &self.image_capture.sessions {
            self.update_capture_session(session);
        }
    }

    pub fn copy_images(
        &mut self,
        renderer: &mut GlesRenderer,
        decorations: &mut crate::decoration::Renderer,
    ) {
        let pending = std::mem::take(&mut self.image_capture.pending);
        for frame in pending {
            if !frame.is_alive() {
                continue;
            }
            let frame_data = frame.data::<FrameData>().unwrap();
            let session = &frame_data.session;
            let data = session.data::<SessionData>().unwrap();
            if !session.is_alive() || data.inner.lock().unwrap().stopped {
                frame.failed(frame::FailureReason::Stopped);
                continue;
            }
            let size = data.inner.lock().unwrap().size.unwrap();
            let buffer = frame_data.inner.lock().unwrap().buffer.take().unwrap();
            if !crate::screencopy::valid_shm_buffer(&buffer, size) {
                frame.failed(frame::FailureReason::BufferConstraints);
                continue;
            }
            let result = match &data.target {
                Target::Output(output) => {
                    self.render_capture(renderer, output, decorations, data.cursor)
                }
                Target::Window(id) => self.render_window_capture(renderer, *id, data.cursor),
                Target::Unavailable => unreachable!(),
            };
            if result
                .ok()
                .is_some_and(|image| crate::screencopy::write_shm_image(&buffer, image))
            {
                frame.transform(smithay::utils::Transform::Normal.into());
                frame.damage(0, 0, size.0, size.1);
                let now: std::time::Duration =
                    smithay::utils::Clock::<smithay::utils::Monotonic>::new()
                        .now()
                        .into();
                frame.presentation_time(
                    (now.as_secs() >> 32) as u32,
                    now.as_secs() as u32,
                    now.subsec_nanos(),
                );
                frame.ready();
            } else {
                frame.failed(frame::FailureReason::Unknown);
            }
        }
    }
}
