use std::{
    io::{BufRead, BufReader, Read, Write},
    process::{Command, Stdio},
    time::{Duration, Instant},
};

use anyhow::{Context, Result, bail};
use image::RgbaImage;
use serde::Deserialize;
use wl_clipboard_rs::{copy, paste};

pub struct Card {
    pub title: String,
    pub app: String,
    pub image: RgbaImage,
}

impl Card {
    pub fn aspect(&self) -> f32 {
        self.image.width() as f32 / self.image.height().max(1) as f32
    }
}

#[derive(Deserialize)]
struct Window {
    id: u64,
    title: Option<String>,
    app_id: Option<String>,
    is_focused: bool,
}

/// Niri's screenshot action also updates the clipboard. Save every advertised
/// format before capture, then restore only if the clipboard still contains
/// our last screenshot. The primary selection is never changed.
struct Clipboard {
    formats: Vec<(String, Vec<u8>)>,
    last_image: Option<Vec<u8>>,
}

fn clipboard_bytes(mime: &str) -> Result<Vec<u8>> {
    let (mut pipe, _) = paste::get_contents(
        paste::ClipboardType::Regular,
        paste::Seat::Unspecified,
        paste::MimeType::Specific(mime),
    )?;
    let mut bytes = Vec::new();
    (&mut pipe)
        .take(64 * 1024 * 1024 + 1)
        .read_to_end(&mut bytes)?;
    if bytes.len() > 64 * 1024 * 1024 {
        bail!("Clipboard item is too large to preserve safely");
    }
    Ok(bytes)
}

impl Clipboard {
    fn save() -> Result<Self> {
        let types =
            match paste::get_mime_types(paste::ClipboardType::Regular, paste::Seat::Unspecified) {
                Ok(types) => types,
                Err(paste::Error::ClipboardEmpty) => Default::default(),
                Err(error) => {
                    return Err(error)
                        .context("Cannot preserve the clipboard; capture was not started");
                }
            };
        let mut formats = Vec::new();
        let mut total = 0;
        for mime in types {
            let bytes = clipboard_bytes(&mime)
                .with_context(|| format!("Preserve clipboard format {mime}"))?;
            total += bytes.len();
            if total > 64 * 1024 * 1024 {
                bail!("Clipboard is too large to preserve safely");
            }
            formats.push((mime, bytes));
        }
        Ok(Self {
            formats,
            last_image: None,
        })
    }

    fn restore(&mut self) -> Result<()> {
        let Some(last) = self.last_image.take() else {
            return Ok(());
        };
        // Encoding and clipboard publication happen asynchronously in Niri.
        let deadline = Instant::now() + Duration::from_secs(2);
        loop {
            if clipboard_bytes("image/png").is_ok_and(|current| current == last) {
                break;
            }
            if Instant::now() >= deadline {
                // A different selection may have been copied during capture.
                // Leave it alone rather than overwriting it with old data.
                return Ok(());
            }
            std::thread::sleep(Duration::from_millis(20));
        }
        if self.formats.is_empty() {
            copy::clear(copy::ClipboardType::Regular, copy::Seat::All)?;
            return Ok(());
        }
        // A dedicated source process keeps the restored clipboard available
        // after the preview closes. It exits naturally on the next copy.
        // No daemon, terminal, or existing desktop process is stopped.
        let mut helper = Command::new(std::env::current_exe()?)
            .arg("--serve-clipboard")
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::null())
            .spawn()
            .context("Start clipboard restoration")?;
        serde_json::to_writer(
            helper.stdin.take().context("Clipboard helper input")?,
            &self.formats,
        )?;
        let mut ready = String::new();
        BufReader::new(helper.stdout.take().context("Clipboard helper output")?)
            .read_line(&mut ready)?;
        if ready.trim() != "ready" {
            bail!("Clipboard restoration did not finish");
        }
        std::thread::spawn(move || {
            let _ = helper.wait();
        });
        Ok(())
    }
}

impl Drop for Clipboard {
    fn drop(&mut self) {
        if let Err(error) = self.restore() {
            eprintln!("Clipboard restoration: {error:#}");
        }
    }
}

pub fn serve_clipboard() -> Result<()> {
    let formats: Vec<(String, Vec<u8>)> = serde_json::from_reader(std::io::stdin().lock())?;
    let sources = formats
        .into_iter()
        .map(|(mime, bytes)| copy::MimeSource {
            source: copy::Source::Bytes(bytes.into_boxed_slice()),
            mime_type: copy::MimeType::Specific(mime),
        })
        .collect();
    let mut options = copy::Options::new();
    options
        .foreground(true)
        .omit_additional_text_mime_types(true);
    let prepared = options.prepare_copy_multi(sources)?;
    println!("ready");
    std::io::stdout().flush()?;
    prepared.serve()?;
    Ok(())
}

pub fn current_windows() -> Result<Vec<Card>> {
    let output = Command::new("niri")
        .args(["msg", "--json", "windows"])
        .output()
        .context("Run this preview inside a Niri session, or use --demo")?;
    if !output.status.success() {
        bail!(
            "Cannot read Niri windows: {}",
            String::from_utf8_lossy(&output.stderr).trim()
        );
    }
    let mut windows: Vec<Window> = serde_json::from_slice(&output.stdout)?;
    windows.retain(|window| {
        window.app_id.as_deref() != Some("ohmansy-spatial")
            && !window
                .title
                .as_deref()
                .unwrap_or_default()
                .starts_with("ohmansy spatial lab")
    });
    windows.sort_by_key(|window| (!window.is_focused, window.id));
    windows.truncate(16);
    if windows.is_empty() {
        bail!("No application windows were found");
    }

    let temporary = tempfile::Builder::new()
        .prefix("ohmansy-spatial-")
        .tempdir()?;
    let mut clipboard = Clipboard::save()?;
    let mut cards = Vec::new();
    let mut failures = Vec::new();
    for window in windows {
        let path = temporary.path().join(format!("{}.png", window.id));
        let result = Command::new("niri")
            .args([
                "msg",
                "action",
                "screenshot-window",
                "--id",
                &window.id.to_string(),
                "--path",
            ])
            .arg(&path)
            .output()?;
        if !result.status.success() {
            failures.push(format!(
                "{}: {}",
                window.id,
                String::from_utf8_lossy(&result.stderr).trim()
            ));
            continue;
        }
        let deadline = Instant::now() + Duration::from_secs(4);
        let image = loop {
            if let Ok(bytes) = std::fs::read(&path)
                && let Ok(image) = image::load_from_memory(&bytes)
            {
                clipboard.last_image = Some(bytes);
                break image.to_rgba8();
            }
            if Instant::now() >= deadline {
                bail!("Timed out capturing window {}", window.id);
            }
            std::thread::sleep(Duration::from_millis(20));
        };
        cards.push(Card {
            title: window.title.unwrap_or_else(|| "Untitled window".into()),
            app: window.app_id.unwrap_or_else(|| "Application".into()),
            image,
        });
    }
    clipboard
        .restore()
        .context("Restore clipboard after window capture")?;
    if cards.is_empty() {
        bail!("No windows could be captured. {}", failures.join("; "));
    }
    for failure in failures {
        eprintln!("Capture skipped: {failure}");
    }
    Ok(cards)
}

/// A real 2x source for checking minification and fine detail, independent of
/// the current desktop's application render scales.
pub fn demo_cards() -> Vec<Card> {
    let palettes = [[61, 44, 83], [30, 66, 76], [73, 49, 45]];
    palettes
        .into_iter()
        .enumerate()
        .map(|(index, base)| {
            let mut image = RgbaImage::new(1600, 1000);
            for (x, y, pixel) in image.enumerate_pixels_mut() {
                let top = y < 60;
                let grid = x % 80 == 0 || y % 80 == 0;
                let fine = y > 780 && (x + y) % 4 < 2;
                let line = (130..710).contains(&y)
                    && y % 56 < 9
                    && x > 100
                    && x < 1400 - (y / 56 % 4) * 180;
                let brightness = if top {
                    20
                } else if fine {
                    65
                } else if grid {
                    17
                } else {
                    0
                };
                let rgb = if line {
                    [180, 177, 195]
                } else {
                    base.map(|v| v + brightness)
                };
                *pixel = image::Rgba([rgb[0], rgb[1], rgb[2], 255]);
            }
            Card {
                title: format!("Scale study {}", index + 1),
                app: "2x test surface".into(),
                image,
            }
        })
        .collect()
}
