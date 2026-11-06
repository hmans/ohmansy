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

pub fn valid_shm_buffer(buffer: &WlBuffer, size: (i32, i32)) -> bool {
    with_buffer_contents_mut(buffer, |_, len, spec| shm_range(spec, len, size).is_some())
        .unwrap_or(false)
}

fn shm_range(
    spec: smithay::wayland::shm::BufferData,
    len: usize,
    size: (i32, i32),
) -> Option<(usize, usize)> {
    let (w, h) = size;
    if spec.format != wl_shm::Format::Xrgb8888
        || spec.width != w
        || spec.height != h
        || w <= 0
        || h <= 0
        || spec.offset < 0
        || spec.stride < w.checked_mul(4)?
    {
        return None;
    }
    let offset = spec.offset as usize;
    let stride = spec.stride as usize;
    let end = offset
        .checked_add(stride.checked_mul((h - 1) as usize)?)?
        .checked_add(w as usize * 4)?;
    (end <= len).then_some((offset, stride))
}

pub fn write_shm_image(buffer: &WlBuffer, image: image::RgbaImage) -> bool {
    let size = (image.width() as i32, image.height() as i32);
    with_buffer_contents_mut(buffer, |ptr, len, spec| {
        let Some((offset, stride)) = shm_range(spec, len, size) else {
            return false;
        };
        let mut pixels = image.into_raw();
        for pixel in pixels.chunks_exact_mut(4) {
            let value = (255_u32 << 24)
                | ((pixel[0] as u32) << 16)
                | ((pixel[1] as u32) << 8)
                | pixel[2] as u32;
            pixel.copy_from_slice(&value.to_ne_bytes());
        }
        for (y, row) in pixels.chunks_exact(size.0 as usize * 4).enumerate() {
            // Validate the full range first; do not create references into
            // memory that another process can modify concurrently.
            unsafe {
                std::ptr::copy_nonoverlapping(
                    row.as_ptr(),
                    ptr.add(offset + y * stride),
                    row.len(),
                );
            }
        }
        true
    })
    .unwrap_or(false)
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
            let copied = result
                .ok()
                .is_some_and(|image| write_shm_image(&request.buffer, image));
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

#[cfg(test)]
mod tests {
    use super::*;

    fn spec() -> smithay::wayland::shm::BufferData {
        smithay::wayland::shm::BufferData {
            offset: 4,
            width: 3,
            height: 2,
            stride: 16,
            format: wl_shm::Format::Xrgb8888,
        }
    }

    #[test]
    fn capture_shm_range_accepts_row_padding_and_checks_last_row() {
        assert_eq!(shm_range(spec(), 32, (3, 2)), Some((4, 16)));
        assert_eq!(shm_range(spec(), 31, (3, 2)), None);
        let mut invalid = spec();
        invalid.stride = 8;
        assert_eq!(shm_range(invalid, 32, (3, 2)), None);
    }

    #[test]
    fn capture_shm_range_rejects_invalid_metadata_and_overflow() {
        let mut invalid = spec();
        invalid.offset = -1;
        assert_eq!(shm_range(invalid, usize::MAX, (3, 2)), None);
        let mut invalid = spec();
        invalid.format = wl_shm::Format::Argb8888;
        assert_eq!(shm_range(invalid, usize::MAX, (3, 2)), None);
        assert_eq!(shm_range(spec(), usize::MAX, (i32::MAX, 2)), None);
        assert_eq!(shm_range(spec(), usize::MAX, (3, 0)), None);
        assert_eq!(shm_range(spec(), usize::MAX, (4, 2)), None);
    }
}
