//! Exercise the conversion used by Smithay when a cursor cannot be copied
//! directly to its ARGB KMS buffer (including fractional output scales).
use smithay::{
    backend::{
        allocator::{
            gbm::{GbmAllocator, GbmBufferFlags, GbmDevice},
            Allocator, Fourcc, Modifier,
        },
        renderer::{pixman::PixmanRenderer, Bind, Color32F, Frame, ImportMem, Renderer},
    },
    reexports::{
        drm::{Device as _, DriverCapability},
        pixman::{FormatCode, Image},
    },
    utils::{DeviceFd, Rectangle, Transform},
};
use std::os::fd::{AsFd, BorrowedFd};

fn source(format: Fourcc) -> Vec<u8> {
    let mut bytes = vec![0; 48 * 48 * 4];
    for y in 0..32 {
        for x in 0..48 {
            let rgba = match x / 16 {
                0 => [255, 0, 0, 255],
                1 => [0, 255, 0, 255],
                _ => [0, 0, 255, 255],
            };
            let pixel = if format == Fourcc::Abgr8888 {
                rgba
            } else {
                [rgba[2], rgba[1], rgba[0], rgba[3]]
            };
            bytes[(y * 48 + x) * 4..(y * 48 + x + 1) * 4].copy_from_slice(&pixel);
        }
    }
    bytes
}

fn convert(
    bytes: &mut [u8],
    width: usize,
    height: usize,
    stride: usize,
    format: Fourcc,
    side: i32,
) {
    bytes.fill(0xcc);
    let mut renderer = PixmanRenderer::new().unwrap();
    let texture = renderer
        .import_memory(&source(format), format, (48, 48).into(), false)
        .unwrap();
    // This is the same target format and conversion used by Smithay's
    // renderer_pixman cursor fallback. The slice outlives the image/frame.
    let mut target = unsafe {
        Image::from_raw_mut(
            FormatCode::try_from(Fourcc::Argb8888).unwrap(),
            width,
            height,
            bytes.as_mut_ptr().cast(),
            stride,
            false,
        )
        .unwrap()
    };
    let mut framebuffer = renderer.bind(&mut target).unwrap();
    let mut frame = renderer
        .render(
            &mut framebuffer,
            (width as i32, height as i32).into(),
            Transform::Normal,
        )
        .unwrap();
    frame
        .clear(
            Color32F::TRANSPARENT,
            &[Rectangle::from_size((width as i32, height as i32).into())],
        )
        .unwrap();
    let destination = Rectangle::from_size((side, side).into());
    frame
        .render_texture_from_to(
            &texture,
            Rectangle::from_size((48, 48).into()).to_f64(),
            destination,
            &[destination],
            &[],
            Transform::Normal,
            1.0,
        )
        .unwrap();
    frame.finish().unwrap().wait().unwrap();
}

fn check(bytes: &[u8], stride: usize, side: i32) {
    let pixel = |x: usize, y: usize| {
        u32::from_ne_bytes(
            bytes[y * stride + x * 4..y * stride + x * 4 + 4]
                .try_into()
                .unwrap(),
        )
    };
    for (fraction, expected) in [(1, 0xffff0000), (3, 0xff00ff00), (5, 0xff0000ff)] {
        assert_eq!(
            pixel(side as usize * fraction / 6, side as usize / 4),
            expected,
            "Cursor channel order or fractional scaling is wrong"
        );
    }
    assert_eq!(
        pixel(side as usize / 2, side as usize * 7 / 8),
        0,
        "Transparent cursor pixels were lost"
    );
    assert_eq!(
        pixel(side as usize + 8, side as usize + 8),
        0,
        "Cursor padding was not cleared"
    );
}

#[test]
fn fractional_cursor_conversion_preserves_colors_alpha_and_padding() {
    for format in [Fourcc::Abgr8888, Fourcc::Argb8888] {
        for scale in [1.0_f64, 1.2, 1.25, 2.0] {
            let side = (24.0 * scale).round() as i32;
            let mut target = vec![0; 64 * 64 * 4];
            convert(&mut target, 64, 64, 64 * 4, format, side);
            check(&target, 64 * 4, side);
        }
    }
}

// No master acquisition, modeset or plane assignment. Explicit opt-in is
// required because this allocates/maps temporary buffers on a live GPU.
#[test]
#[ignore = "requires OHMANSY_TEST_DRM_CURSOR_DEVICE and a live DRM device"]
fn driver_cursor_buffer_conversion() {
    #[derive(Clone)]
    struct ProbeFd(DeviceFd);
    impl AsFd for ProbeFd {
        fn as_fd(&self) -> BorrowedFd<'_> {
            self.0.as_fd()
        }
    }
    impl smithay::reexports::drm::Device for ProbeFd {}
    let path =
        std::env::var("OHMANSY_TEST_DRM_CURSOR_DEVICE").expect("Explicit DRM device required");
    let file = std::fs::OpenOptions::new()
        .read(true)
        .write(true)
        .open(path)
        .unwrap();
    let fd = ProbeFd(DeviceFd::from(std::os::fd::OwnedFd::from(file)));
    let width = fd
        .get_driver_capability(DriverCapability::CursorWidth)
        .unwrap() as u32;
    let height = fd
        .get_driver_capability(DriverCapability::CursorHeight)
        .unwrap() as u32;
    let gbm = GbmDevice::new(fd).unwrap();
    let mut allocator = GbmAllocator::new(gbm, GbmBufferFlags::CURSOR | GbmBufferFlags::WRITE);
    for format in [Fourcc::Abgr8888, Fourcc::Argb8888] {
        for scale in [1.0_f64, 1.2, 1.25, 2.0] {
            let mut buffer = allocator
                .create_buffer(width, height, Fourcc::Argb8888, &[Modifier::Linear])
                .unwrap();
            let side = (24.0 * scale).round() as i32;
            buffer
                .map_mut(0, 0, width, height, |mapping| {
                    let stride = mapping.stride() as usize;
                    convert(
                        mapping.buffer_mut(),
                        width as usize,
                        height as usize,
                        stride,
                        format,
                        side,
                    );
                    check(mapping.buffer_mut(), stride, side);
                })
                .unwrap();
            println!("Cursor buffer {width}x{height}: {format:?}, scale {scale} passed");
        }
    }
}
