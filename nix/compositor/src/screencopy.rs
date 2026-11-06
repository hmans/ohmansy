//! Shared-memory output capture for xdg-desktop-portal-wlr.
//!
//! Like clipboard access, this protocol trusts local Wayland clients. The
//! portal supplies application consent; this is not a sandbox permission gate.
use std::sync::atomic::{AtomicBool, Ordering};

use smithay::{
    backend::renderer::gles::GlesRenderer,
    output::Output,
    reexports::{
        wayland_protocols_wlr::screencopy::v1::server::{
            zwlr_screencopy_frame_v1::{self as frame, ZwlrScreencopyFrameV1},
            zwlr_screencopy_manager_v1::{self as manager, ZwlrScreencopyManagerV1},
        },
        wayland_server::{
            protocol::{wl_buffer::WlBuffer, wl_shm},
            Client, DataInit, Dispatch, DisplayHandle, GlobalDispatch, New, Resource,
        },
    },
    wayland::shm::with_buffer_contents_mut,
};

use crate::Smallvil;

pub struct Frame {
    output: Option<Output>,
    size: (i32, i32),
    cursor: bool,
    used: AtomicBool,
}

pub struct Pending {
    frame: ZwlrScreencopyFrameV1,
    buffer: WlBuffer,
    damage: bool,
}

pub fn init(dh: &DisplayHandle) {
    dh.create_global::<Smallvil, ZwlrScreencopyManagerV1, _>(3, ());
}

impl GlobalDispatch<ZwlrScreencopyManagerV1, ()> for Smallvil {
    fn bind(
        _: &mut Self,
        _: &DisplayHandle,
        _: &Client,
        resource: New<ZwlrScreencopyManagerV1>,
        _: &(),
        data: &mut DataInit<'_, Self>,
    ) {
        data.init(resource, ());
    }
}

impl Dispatch<ZwlrScreencopyManagerV1, ()> for Smallvil {
    fn request(
        _: &mut Self,
        _: &Client,
        _: &ZwlrScreencopyManagerV1,
        request: manager::Request,
        _: &(),
        _: &DisplayHandle,
        data: &mut DataInit<'_, Self>,
    ) {
        let (id, output, cursor, supported) = match request {
            manager::Request::CaptureOutput {
                frame,
                output,
                overlay_cursor,
            } => (frame, output, overlay_cursor != 0, true),
            // The portal offers entire displays. Fail unsupported region requests
            // explicitly instead of silently returning pixels outside the region.
            manager::Request::CaptureOutputRegion {
                frame,
                output,
                overlay_cursor,
                ..
            } => (frame, output, overlay_cursor != 0, false),
            _ => return,
        };
        let output = Output::from_resource(&output);
        let size = output
            .as_ref()
            .and_then(Output::current_mode)
            .map(|m| (m.size.w, m.size.h));
        let valid = supported && size.is_some_and(|(w, h)| w > 0 && h > 0 && w <= i32::MAX / 4);
        let frame = data.init(
            id,
            Frame {
                output,
                size: size.unwrap_or_default(),
                cursor,
                used: AtomicBool::new(!valid),
            },
        );
        if !valid {
            frame.failed();
            return;
        }
        let (w, h) = size.unwrap();
        frame.buffer(wl_shm::Format::Xrgb8888, w as u32, h as u32, (w * 4) as u32);
        if frame.version() >= 3 {
            frame.buffer_done();
        }
    }
}

impl Dispatch<ZwlrScreencopyFrameV1, Frame> for Smallvil {
    fn request(
        state: &mut Self,
        _: &Client,
        resource: &ZwlrScreencopyFrameV1,
        request: frame::Request,
        data: &Frame,
        _: &DisplayHandle,
        _: &mut DataInit<'_, Self>,
    ) {
        let (buffer, damage) = match request {
            frame::Request::Copy { buffer } => (buffer, false),
            frame::Request::CopyWithDamage { buffer } => (buffer, true),
            _ => return,
        };
        if data.used.swap(true, Ordering::Relaxed) {
            resource.post_error(frame::Error::AlreadyUsed, "Frame has already been copied");
            return;
        }
        state.screencopy.push(Pending {
            frame: resource.clone(),
            buffer,
            damage,
        });
        state.needs_redraw = true;
    }
}

impl Smallvil {
    pub fn copy_output(
        &mut self,
        renderer: &mut GlesRenderer,
        output: &Output,
        decorations: &mut crate::decoration::Renderer,
    ) {
        // Drop destroyed frames and fail disconnected or resized sources. Each
        // request owns its buffer only until ready/failed; never retain a stream.
        let pending = std::mem::take(&mut self.screencopy);
        for request in pending {
            if !request.frame.is_alive() {
                request.buffer.release();
                continue;
            }
            let data = request.frame.data::<Frame>().unwrap();
            let Some(source) = data
                .output
                .as_ref()
                .filter(|o| self.space.outputs().any(|s| s == *o))
            else {
                request.frame.failed();
                request.buffer.release();
                continue;
            };
            if source != output {
                self.screencopy.push(request);
                continue;
            }
            if output.current_mode().map(|m| (m.size.w, m.size.h)) != Some(data.size) {
                request.frame.failed();
                request.buffer.release();
                continue;
            }
            let result = self.render_capture(renderer, output, decorations, data.cursor);
            let copied = result.ok().is_some_and(|image| {
                let (w, h) = data.size;
                with_buffer_contents_mut(&request.buffer, |ptr, len, spec| {
                    let bytes = (w as usize) * (h as usize) * 4;
                    if spec.format != wl_shm::Format::Xrgb8888
                        || spec.width != w
                        || spec.height != h
                        || spec.stride != w * 4
                        || spec.offset < 0
                        || (spec.offset as usize)
                            .checked_add(bytes)
                            .is_none_or(|end| end > len)
                    {
                        return false;
                    }
                    // XRGB8888 is B,G,R,X in memory on little-endian hosts.
                    // Never make a Rust reference into client-owned shared memory.
                    let mut pixels = image.into_raw();
                    for pixel in pixels.chunks_exact_mut(4) {
                        let value = (255_u32 << 24)
                            | ((pixel[0] as u32) << 16)
                            | ((pixel[1] as u32) << 8)
                            | pixel[2] as u32;
                        pixel.copy_from_slice(&value.to_ne_bytes());
                    }
                    // The checked shm range is live for this callback. Copying
                    // raw bytes avoids aliasing client-owned memory with a slice.
                    unsafe {
                        std::ptr::copy_nonoverlapping(
                            pixels.as_ptr(),
                            ptr.add(spec.offset as usize),
                            bytes,
                        );
                    }
                    true
                })
                .unwrap_or(false)
            });
            request.buffer.release();
            if copied {
                request.frame.flags(frame::Flags::empty());
                if request.damage {
                    request
                        .frame
                        .damage(0, 0, data.size.0 as u32, data.size.1 as u32);
                }
                let elapsed = self.start_time.elapsed();
                request.frame.ready(
                    (elapsed.as_secs() >> 32) as u32,
                    elapsed.as_secs() as u32,
                    elapsed.subsec_nanos(),
                );
            } else {
                request.frame.failed();
            }
        }
    }
}
