//! User screenshots share the scene renderer, independent of the display backend.
use std::{
    ffi::OsString,
    fs::{self, File, OpenOptions},
    io::{Cursor, Seek, Write},
    os::unix::fs::OpenOptionsExt,
    path::{Path, PathBuf},
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
    id: u64,
    pub output: String,
    path: Option<PathBuf>,
    annotate: bool,
}

#[derive(serde::Serialize)]
pub struct Saved {
    path: PathBuf,
    width: u32,
    height: u32,
    clipboard: bool,
    clipboard_error: Option<String>,
    annotation_error: Option<String>,
}

#[derive(serde::Serialize)]
#[serde(untagged)]
enum Outcome {
    Saved(Saved),
    Failed { error: String },
}

impl From<Result<Saved, String>> for Outcome {
    fn from(result: Result<Saved, String>) -> Self {
        match result {
            Ok(saved) => Self::Saved(saved),
            Err(error) => Self::Failed { error },
        }
    }
}

#[derive(serde::Serialize)]
pub struct Completion {
    id: u64,
    output: String,
    #[serde(flatten)]
    outcome: Outcome,
}

struct Worker {
    id: u64,
    output: String,
    receiver: Receiver<Result<Saved, String>>,
}

#[derive(Default)]
pub struct State {
    pending: Option<Request>,
    worker: Option<Worker>,
    next_id: u64,
    pub last: Option<Completion>,
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
        self.capture.next_id += 1;
        self.capture.pending = Some(Request {
            id: self.capture.next_id,
            output,
            path,
            annotate,
        });
        self.capture.last = None;
        self.needs_redraw = true;
        Ok(())
    }

    pub fn poll_screenshot(&mut self) {
        if let Some(worker) = &self.capture.worker {
            let result = match worker.receiver.try_recv() {
                Ok(result) => Some(result),
                Err(mpsc::TryRecvError::Disconnected) => {
                    Some(Err("Screenshot worker stopped".into()))
                }
                Err(mpsc::TryRecvError::Empty) => None,
            };
            if let Some(result) = result {
                let worker = self.capture.worker.take().unwrap();
                self.capture.last = Some(Completion {
                    id: worker.id,
                    output: worker.output,
                    outcome: result.into(),
                });
            }
        }
        if self
            .capture
            .pending
            .as_ref()
            .is_some_and(|r| !self.space.outputs().any(|o| o.name() == r.output))
        {
            let request = self.capture.pending.take().unwrap();
            self.capture.last = Some(Completion {
                id: request.id,
                output: request.output,
                outcome: Outcome::Failed {
                    error: "Screenshot monitor disconnected".into(),
                },
            });
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
            let elements = self.output_elements(
                renderer,
                output,
                None,
                decorations,
                (0, 0).into(),
                crate::scene::RenderPurpose::Capture,
            );
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
                self.capture.worker = Some(Worker {
                    id: request.id,
                    output: request.output.clone(),
                    receiver,
                });
                std::thread::spawn(move || {
                    let result = save(image, request, socket).map_err(|error| format!("{error:#}"));
                    let _ = sender.send(result);
                });
            }
            Err(error) => {
                eprintln!("Screenshot failed: {error:#}");
                self.capture.last = Some(Completion {
                    id: request.id,
                    output: request.output,
                    outcome: Outcome::Failed {
                        error: format!("{error:#}"),
                    },
                });
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

fn copy_png(file: File, socket: &OsString) -> Result<()> {
    // wl-copy detaches only after acquiring the selection. Keep serving Wayland
    // on the main thread while this worker waits for that handshake.
    let start = Instant::now();
    let mut child = Command::new("wl-copy")
        .args(["--type", "image/png"])
        .env("WAYLAND_DISPLAY", socket)
        .env_remove("WAYLAND_SOCKET")
        // A regular file avoids an unbounded blocking pipe write before the
        // timeout can run. The descriptor refers to the image we published.
        .stdin(file)
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
        .context("Start clipboard helper")?;
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

fn save(image: image::RgbaImage, request: Request, socket: OsString) -> Result<Saved> {
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
    let file = publish(&path, &bytes).with_context(|| format!("Save {}", path.display()))?;
    let clipboard = copy_png(file, &socket).map_err(|error| format!("{error:#}"));
    let mut annotation_error = None;
    if request.annotate {
        annotation_error = crate::spawn_application(
            &socket,
            "satty",
            &[
                "--filename".into(),
                path.to_string_lossy().into_owned(),
                // GTK's selection disappears when Satty closes. wl-copy owns
                // the edited PNG independently, including after early-exit.
                "--copy-command".into(),
                "wl-copy --type image/png".into(),
            ],
        )
        .err()
        .map(|error| format!("{error:#}"));
    }
    Ok(Saved {
        path,
        width: image.width(),
        height: image.height(),
        clipboard: clipboard.is_ok(),
        clipboard_error: clipboard.err(),
        annotation_error,
    })
}

struct Temporary(PathBuf);
impl Drop for Temporary {
    fn drop(&mut self) {
        let _ = fs::remove_file(&self.0);
    }
}

fn publish(path: &Path, bytes: &[u8]) -> Result<File> {
    publish_with(path, |file| Ok(file.write_all(bytes)?))
}

fn publish_with(path: &Path, write: impl FnOnce(&mut File) -> Result<()>) -> Result<File> {
    use smithay::reexports::rustix::fs::{renameat_with, RenameFlags, CWD};
    let parent = path
        .parent()
        .filter(|p| !p.as_os_str().is_empty())
        .unwrap_or(Path::new("."));
    let nonce = SystemTime::now().duration_since(UNIX_EPOCH)?.as_nanos();
    let temporary_path = parent.join(format!(
        ".ohmansy-screenshot-{}-{nonce}.tmp",
        std::process::id()
    ));
    let mut file = OpenOptions::new()
        .read(true)
        .write(true)
        .create_new(true)
        .mode(0o600)
        .open(&temporary_path)?;
    let temporary = Temporary(temporary_path);
    write(&mut file)?;
    file.sync_all()?;
    // Atomic publication on the same filesystem, refusing existing files and
    // symlinks. A failed/interrupted write never becomes a destination PNG.
    renameat_with(CWD, &temporary.0, CWD, path, RenameFlags::NOREPLACE)?;
    file.rewind()?;
    Ok(file)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Read;

    #[test]
    fn publication_is_complete_no_clobber_and_cleans_up_failed_writes() {
        let directory = std::env::temp_dir().join(format!(
            "shine-publication-{}-{}",
            std::process::id(),
            SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        fs::create_dir(&directory).unwrap();
        let path = directory.join("image.png");
        assert!(publish_with(&path, |file| {
            file.write_all(b"partial")?;
            bail!("Injected write failure")
        })
        .is_err());
        assert!(!path.exists());
        assert_eq!(fs::read_dir(&directory).unwrap().count(), 0);
        let mut file = publish(&path, b"complete image").unwrap();
        let mut bytes = Vec::new();
        file.read_to_end(&mut bytes).unwrap();
        assert_eq!(bytes, b"complete image");
        assert!(publish(&path, b"replacement").is_err());
        assert_eq!(fs::read(&path).unwrap(), bytes);
        let link = directory.join("link.png");
        std::os::unix::fs::symlink(&path, &link).unwrap();
        assert!(publish(&link, b"replacement").is_err());
        assert!(link.is_symlink());
        assert_eq!(fs::read_dir(&directory).unwrap().count(), 2);
        fs::remove_dir_all(directory).unwrap();
    }
}
