//! User screenshots share the scene renderer, independent of the display backend.
use std::{
    ffi::OsString,
    fs::{self, OpenOptions},
    io::{Cursor, Write},
    path::PathBuf,
    process::{Command, Stdio},
    sync::mpsc::{self, Receiver},
    time::{Duration, Instant, SystemTime, UNIX_EPOCH},
};

use anyhow::{bail, Context, Result};
use smithay::{
    backend::{
        allocator::Fourcc,
        renderer::{
            damage::OutputDamageTracker,
            gles::{GlesRenderer, GlesTexture},
            Bind, ExportMem, Offscreen, TextureMapping,
        },
    },
    output::Output,
    utils::{Rectangle, Transform},
};

pub struct Request {
    pub output: String,
    path: Option<PathBuf>,
    annotate: bool,
}

#[derive(Default)]
pub struct State {
    pending: Option<Request>,
    worker: Option<Receiver<Result<serde_json::Value, String>>>,
    pub last: Option<serde_json::Value>,
}

impl crate::Smallvil {
    pub fn request_screenshot(
        &mut self,
        path: Option<PathBuf>,
        annotate: bool,
    ) -> Result<(), String> {
        if self.capture.pending.is_some() || self.capture.worker.is_some() {
            return Err("A screenshot is already in progress".into());
        }
        let output = self
            .layout
            .monitors
            .get(self.layout.active_monitor)
            .ok_or("No focused monitor to capture")?
            .name
            .clone();
        self.capture.pending = Some(Request {
            output,
            path,
            annotate,
        });
        self.capture.last = None;
        self.needs_redraw = true;
        Ok(())
    }

    pub fn poll_screenshot(&mut self) {
        if let Some(receiver) = &self.capture.worker {
            match receiver.try_recv() {
                Ok(result) => {
                    self.capture.last = Some(match result {
                        Ok(value) => value,
                        Err(error) => serde_json::json!({"error": error}),
                    });
                    self.capture.worker = None;
                }
                Err(mpsc::TryRecvError::Disconnected) => {
                    self.capture.last =
                        Some(serde_json::json!({"error":"Screenshot worker stopped"}));
                    self.capture.worker = None;
                }
                Err(mpsc::TryRecvError::Empty) => (),
            }
        }
        if self
            .capture
            .pending
            .as_ref()
            .is_some_and(|r| !self.space.outputs().any(|o| o.name() == r.output))
        {
            self.capture.pending = None;
            self.capture.last =
                Some(serde_json::json!({"error":"Screenshot monitor disconnected"}));
        }
    }

    pub fn capture_output(
        &mut self,
        renderer: &mut GlesRenderer,
        output: &Output,
        decorations: &mut crate::decoration::Renderer,
    ) {
        if self
            .capture
            .pending
            .as_ref()
            .is_none_or(|r| r.output != output.name())
        {
            return;
        }
        let request = self.capture.pending.take().unwrap();
        let result = (|| -> Result<image::RgbaImage> {
            let size = output
                .current_mode()
                .context("Monitor has no current mode")?
                .size;
            let mut texture: GlesTexture =
                renderer.create_buffer(Fourcc::Abgr8888, (size.w, size.h).into())?;
            let elements =
                self.output_elements(renderer, output, None, decorations, (0, 0).into(), false);
            let mut framebuffer = renderer.bind(&mut texture)?;
            // PNG rows run top to bottom, while an OpenGL offscreen target has
            // its origin at the bottom. Match the nested framebuffer's Y flip.
            let mut damage = OutputDamageTracker::new(size, 1.0, Transform::Flipped180);
            damage.render_output(
                renderer,
                &mut framebuffer,
                0,
                &elements,
                [0.035, 0.035, 0.055, 1.0],
            )?;
            let mapping = renderer.copy_framebuffer(
                &framebuffer,
                Rectangle::from_size((size.w, size.h).into()),
                Fourcc::Abgr8888,
            )?;
            let bytes = renderer.map_texture(&mapping)?;
            let mut image =
                image::RgbaImage::from_raw(size.w as u32, size.h as u32, bytes.to_vec())
                    .context("Invalid screenshot buffer")?;
            if mapping.flipped() {
                image::imageops::flip_vertical_in_place(&mut image);
            }
            Ok(image)
        })();
        match result {
            Ok(image) => {
                let socket = self.socket_name.clone();
                let (sender, receiver) = mpsc::channel();
                self.capture.worker = Some(receiver);
                std::thread::spawn(move || {
                    let result = save(image, request, socket).map_err(|error| format!("{error:#}"));
                    let _ = sender.send(result);
                });
            }
            Err(error) => {
                eprintln!("Screenshot failed: {error:#}");
                self.capture.last = Some(serde_json::json!({"error":format!("{error:#}")}));
            }
        }
    }
}

fn screenshot_directory() -> Result<PathBuf> {
    let pictures = Command::new("xdg-user-dir")
        .arg("PICTURES")
        .output()
        .context("Find the Pictures directory")?;
    if !pictures.status.success() {
        bail!("Could not find the Pictures directory");
    }
    let directory = PathBuf::from(String::from_utf8(pictures.stdout)?.trim_end_matches('\n'));
    if !directory.is_absolute() {
        bail!("Pictures directory must be absolute");
    }
    Ok(directory.join("Screenshots"))
}

fn copy_png(bytes: &[u8], socket: &OsString) -> Result<()> {
    // wl-copy detaches only after acquiring the selection. Keep serving Wayland
    // on the main thread while this worker waits for that handshake.
    let mut child = Command::new("wl-copy")
        .args(["--type", "image/png"])
        .env("WAYLAND_DISPLAY", socket)
        .env_remove("WAYLAND_SOCKET")
        .stdin(Stdio::piped())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
        .context("Start clipboard helper")?;
    if let Err(error) = child.stdin.take().unwrap().write_all(bytes) {
        let _ = child.kill();
        let _ = child.wait();
        return Err(error.into());
    }
    let start = Instant::now();
    loop {
        if let Some(status) = child.try_wait()? {
            if !status.success() {
                bail!("Clipboard helper failed");
            }
            return Ok(());
        }
        if start.elapsed() > Duration::from_secs(5) {
            let _ = child.kill();
            let _ = child.wait();
            bail!("Clipboard helper timed out");
        }
        std::thread::sleep(Duration::from_millis(10));
    }
}

fn save(image: image::RgbaImage, request: Request, socket: OsString) -> Result<serde_json::Value> {
    let mut png = Cursor::new(Vec::new());
    image.write_to(&mut png, image::ImageFormat::Png)?;
    let bytes = png.into_inner();
    let path = match request.path {
        Some(path) => path,
        None => {
            let directory = screenshot_directory()?;
            fs::create_dir_all(&directory)?;
            let timestamp = SystemTime::now().duration_since(UNIX_EPOCH)?;
            let date = Command::new("date").arg("+%Y-%m-%d_%H-%M-%S").output()?;
            if !date.status.success() {
                bail!("Could not format screenshot date");
            }
            let date = String::from_utf8(date.stdout)?;
            directory.join(format!(
                "Screenshot-{}-{:09}.png",
                date.trim(),
                timestamp.subsec_nanos()
            ))
        }
    };
    // Never overwrite an earlier screenshot or follow a destination symlink.
    let mut file = OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(&path)
        .with_context(|| format!("Save {}", path.display()))?;
    if let Err(error) = file.write_all(&bytes) {
        drop(file);
        let _ = fs::remove_file(&path);
        return Err(error.into());
    }
    let clipboard = copy_png(&bytes, &socket).map_err(|error| format!("{error:#}"));
    let mut annotation_error = None;
    if request.annotate {
        annotation_error = crate::spawn_application(
            &socket,
            "satty",
            &["--filename".into(), path.to_string_lossy().into_owned()],
        )
        .err()
        .map(|error| format!("{error:#}"));
    }
    Ok(
        serde_json::json!({"path":path,"output":request.output,"width":image.width(),"height":image.height(),
        "clipboard":clipboard.is_ok(),"clipboard_error":clipboard.err(),"annotation_error":annotation_error}),
    )
}
