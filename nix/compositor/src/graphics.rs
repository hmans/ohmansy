//! Report the actual rendering device, and enforce GPU-only development previews.
use smithay::backend::{
    egl::EGLDevice,
    renderer::gles::{ffi, GlesRenderer},
};
use std::ffi::CStr;

#[derive(Default, serde::Serialize)]
pub struct Info {
    vendor: String,
    renderer: String,
    version: String,
    device: Option<String>,
    acceleration: Acceleration,
}

#[derive(Clone, Copy, Default, PartialEq, Debug, serde::Serialize)]
#[serde(rename_all = "lowercase")]
enum Acceleration {
    Hardware,
    Software,
    #[default]
    Unknown,
}

fn classify(renderer: &str, software_device: Option<bool>) -> Acceleration {
    let name = renderer.to_ascii_lowercase();
    if software_device == Some(true)
        || [
            "llvmpipe",
            "softpipe",
            "swrast",
            "software rasterizer",
            "swiftshader",
            "lavapipe",
            "gdi generic",
            "microsoft basic render",
        ]
        .iter()
        .any(|marker| name.contains(marker))
    {
        Acceleration::Software
    } else if software_device == Some(false) && !name.trim().is_empty() {
        Acceleration::Hardware
    } else {
        Acceleration::Unknown
    }
}

pub fn inspect(renderer: &mut GlesRenderer) -> anyhow::Result<Info> {
    let (vendor, name, version) = renderer.with_context(|gl| {
        let string = |key| unsafe {
            let value = gl.GetString(key);
            if value.is_null() {
                String::new()
            } else {
                CStr::from_ptr(value.cast()).to_string_lossy().into_owned()
            }
        };
        (
            string(ffi::VENDOR),
            string(ffi::RENDERER),
            string(ffi::VERSION),
        )
    })?;
    let device = EGLDevice::device_for_display(renderer.egl_context().display()).ok();
    let acceleration = classify(&name, device.as_ref().map(EGLDevice::is_software));
    let path = device.and_then(|device| {
        device
            .render_device_path()
            .or_else(|_| device.drm_device_path())
            .ok()
    });
    let info = Info {
        vendor,
        renderer: name,
        version,
        device: path.map(|p| p.to_string_lossy().into_owned()),
        acceleration,
    };
    eprintln!(
        "Shine graphics: {} / {} ({:?}), device {}",
        info.vendor,
        info.renderer,
        info.acceleration,
        info.device.as_deref().unwrap_or("unavailable")
    );
    if std::env::var_os("OHMANSY_REQUIRE_HARDWARE_RENDERER").is_some_and(|v| v == "1") {
        anyhow::ensure!(acceleration == Acceleration::Hardware,
            "Hardware rendering is required for this preview, but the renderer is {} ({:?}). Check GPU driver and render-device access; no software fallback was started.", info.renderer, acceleration);
    }
    Ok(info)
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn software_and_unverified_renderers_cannot_pass_as_hardware() {
        for name in [
            "llvmpipe (LLVM 19)",
            "softpipe",
            "Google SwiftShader",
            "Software Rasterizer",
        ] {
            assert_eq!(classify(name, Some(false)), Acceleration::Software);
        }
        assert_eq!(
            classify("Mesa Intel UHD Graphics", Some(true)),
            Acceleration::Software
        );
        assert_eq!(
            classify("NVIDIA GeForce RTX 3060 Ti/PCIe/SSE2", None),
            Acceleration::Unknown
        );
        assert_eq!(classify("", Some(false)), Acceleration::Unknown);
        assert_eq!(
            classify("NVIDIA GeForce RTX 3060 Ti/PCIe/SSE2", Some(false)),
            Acceleration::Hardware
        );
        assert_eq!(
            classify("Mesa Intel UHD Graphics", Some(false)),
            Acceleration::Hardware
        );
    }
}
