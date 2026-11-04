mod capture;
mod render;
mod scene;

use std::{
    path::PathBuf,
    sync::{Arc, mpsc},
    time::{Duration, Instant},
};

use anyhow::{Context, Result};
use eframe::{
    egui::{self, Color32, RichText, Vec2, mutex::Mutex},
    egui_glow,
};

struct Lab {
    renderer: Arc<Mutex<render::Renderer>>,
    settings: scene::Settings,
    selected: usize,
    focus: f32,
    capture: Option<mpsc::Receiver<Result<Vec<capture::Card>>>>,
    status: String,
    last_frame: Instant,
    close_at: Option<Instant>,
    close_when_idle: bool,
    screenshot: Option<PathBuf>,
    screenshot_requested: bool,
    started: Instant,
}

impl Lab {
    fn new(
        cc: &eframe::CreationContext<'_>,
        demo: bool,
        close_after: Option<Duration>,
        screenshot: Option<PathBuf>,
    ) -> Result<Self> {
        let gl = cc
            .gl
            .as_ref()
            .context("The spatial lab needs an OpenGL renderer")?;
        let mut renderer = render::Renderer::new(gl)?;
        renderer.replace(gl, capture::demo_cards())?;
        eprintln!("Spatial renderer: {}", renderer.device);
        if let Some(path) = std::env::var_os("OHMANSY_SPATIAL_FONT") {
            let bytes = std::fs::read(path).context("Load the shared Inter font")?;
            let mut fonts = egui::FontDefinitions::default();
            fonts
                .font_data
                .insert("Inter".into(), egui::FontData::from_owned(bytes).into());
            fonts
                .families
                .entry(egui::FontFamily::Proportional)
                .or_default()
                .insert(0, "Inter".into());
            cc.egui_ctx.set_fonts(fonts);
        }
        let mut visuals = egui::Visuals::dark();
        visuals.panel_fill = Color32::from_rgb(20, 20, 27);
        visuals.window_fill = Color32::from_rgb(30, 29, 38);
        visuals.selection.bg_fill = Color32::from_rgb(81, 64, 95);
        visuals.widgets.active.bg_fill = Color32::from_rgb(81, 64, 95);
        visuals.widgets.inactive.bg_fill = Color32::from_rgb(48, 51, 63);
        cc.egui_ctx.set_visuals(visuals);
        let mut lab = Self {
            renderer: Arc::new(Mutex::new(renderer)),
            settings: scene::Settings::default(),
            selected: if demo { 1 } else { 0 },
            focus: if demo { 1.0 } else { 0.0 },
            capture: None,
            status: "Test surfaces • 1600 × 1000 pixels for an 800 × 500 logical window".into(),
            last_frame: Instant::now(),
            close_at: close_after.map(|duration| Instant::now() + duration),
            close_when_idle: false,
            screenshot,
            screenshot_requested: false,
            started: Instant::now(),
        };
        if !demo {
            lab.refresh(&cc.egui_ctx);
        }
        Ok(lab)
    }

    fn refresh(&mut self, ctx: &egui::Context) {
        if self.capture.is_some() {
            return;
        }
        let (tx, rx) = mpsc::channel();
        let ctx = ctx.clone();
        self.capture = Some(rx);
        self.status = "Capturing windows…".into();
        std::thread::spawn(move || {
            let _ = tx.send(capture::current_windows());
            ctx.request_repaint();
        });
    }
}

impl eframe::App for Lab {
    fn update(&mut self, ctx: &egui::Context, frame: &mut eframe::Frame) {
        if let Some(deadline) = self.close_at {
            if Instant::now() >= deadline {
                self.close_when_idle = true;
            } else {
                ctx.request_repaint_after(deadline.saturating_duration_since(Instant::now()));
            }
        }
        if ctx.input(|i| i.viewport().close_requested()) && self.capture.is_some() {
            ctx.send_viewport_cmd(egui::ViewportCommand::CancelClose);
            self.close_when_idle = true;
        }
        if let Some(path) = &self.screenshot {
            let captured = ctx.input(|i| {
                i.events.iter().find_map(|event| {
                    if let egui::Event::Screenshot { image, .. } = event {
                        Some(image.clone())
                    } else {
                        None
                    }
                })
            });
            if let Some(image) = captured {
                let bytes: Vec<u8> = image
                    .pixels
                    .iter()
                    .flat_map(|pixel| pixel.to_array())
                    .collect();
                match image::save_buffer(
                    path,
                    &bytes,
                    image.size[0] as u32,
                    image.size[1] as u32,
                    image::ColorType::Rgba8,
                ) {
                    Ok(()) => eprintln!("Saved preview screenshot: {}", path.display()),
                    Err(error) => eprintln!("Preview screenshot failed: {error}"),
                }
                self.screenshot = None;
            } else if !self.screenshot_requested
                && self.capture.is_none()
                && self.started.elapsed() > Duration::from_secs(2)
            {
                ctx.send_viewport_cmd(egui::ViewportCommand::Screenshot(Default::default()));
                self.screenshot_requested = true;
            } else {
                ctx.request_repaint_after(Duration::from_millis(100));
            }
        }
        let capture_result = self.capture.as_ref().and_then(|rx| match rx.try_recv() {
            Ok(result) => Some(result),
            Err(mpsc::TryRecvError::Empty) => None,
            Err(mpsc::TryRecvError::Disconnected) => {
                Some(Err(anyhow::anyhow!("The capture worker exited")))
            }
        });
        if let Some(result) = capture_result {
            self.capture = None;
            match result {
                Ok(cards) => {
                    let count = cards.len();
                    if let Some(gl) = frame.gl() {
                        match self.renderer.lock().replace(gl, cards) {
                            Ok(()) => {
                                self.status =
                                    format!("{count} window captures • Refresh windows to update");
                                self.selected = 0;
                                self.focus = 0.0;
                            }
                            Err(error) => self.status = format!("{error:#}"),
                        }
                    }
                }
                Err(error) => self.status = format!("{error:#} • Showing test surfaces"),
            }
        }
        if self.close_when_idle && self.capture.is_none() {
            ctx.send_viewport_cmd(egui::ViewportCommand::Close);
        }
        let count = self.renderer.lock().cards.len();
        if ctx.input(|i| i.key_pressed(egui::Key::ArrowRight)) && count > 0 {
            self.selected = (self.selected + 1).min(count - 1);
        }
        if ctx.input(|i| i.key_pressed(egui::Key::ArrowLeft)) {
            self.selected = self.selected.saturating_sub(1);
        }
        if ctx.input(|i| i.key_pressed(egui::Key::R)) {
            self.settings = Default::default();
        }
        let now = Instant::now();
        let delta = (now - self.last_frame).as_secs_f32().min(0.1);
        self.last_frame = now;
        self.focus += (self.selected as f32 - self.focus) * (1.0 - (-delta * 9.0).exp());
        if (self.focus - self.selected as f32).abs() > 0.001 {
            ctx.request_repaint();
        }

        egui::TopBottomPanel::top("toolbar").show(ctx, |ui| {
            ui.add_space(8.0);
            ui.horizontal(|ui| {
                ui.label(RichText::new("ohmansy").size(22.0).strong());
                ui.label(
                    RichText::new("spatial lab")
                        .size(18.0)
                        .color(Color32::from_rgb(168, 160, 181)),
                );
                ui.separator();
                if ui
                    .add_enabled(self.capture.is_none(), egui::Button::new("Refresh windows"))
                    .clicked()
                {
                    self.refresh(ctx);
                }
                if ui.button("Test surfaces").clicked()
                    && let Some(gl) = frame.gl()
                {
                    match self.renderer.lock().replace(gl, capture::demo_cards()) {
                        Ok(()) => {
                            self.selected = 1;
                            self.focus = 1.0;
                            self.status =
                                "2x test surfaces • Window captures keep their original resolution"
                                    .into();
                        }
                        Err(error) => self.status = format!("{error:#}"),
                    }
                }
                if ui.button("Reset view").clicked() {
                    self.settings = Default::default();
                }
                if self.capture.is_some() {
                    ui.spinner();
                }
            });
            ui.add_space(8.0);
        });
        egui::TopBottomPanel::bottom("status").show(ctx, |ui| {
            ui.add_space(6.0);
            ui.label(&self.status);
            ui.label(
                RichText::new(
                    "Left / Right: select window   ·   Drag: orbit   ·   Scroll: zoom   ·   R: reset",
                )
                .small()
                .weak(),
            );
            ui.add_space(6.0);
        });
        egui::SidePanel::right("controls")
            .default_width(245.0)
            .show(ctx, |ui| {
                ui.add_space(14.0);
                ui.label(RichText::new("View").size(18.0).strong());
                ui.add_space(8.0);
                ui.add(egui::Slider::new(&mut self.settings.scale, 0.5..=2.0).text("Scale"));
                ui.add(egui::Slider::new(&mut self.settings.tilt, 0.0..=75.0).text("Tilt"));
                ui.add(egui::Slider::new(&mut self.settings.depth, 0.0..=3.0).text("Depth"));
                ui.add(egui::Slider::new(&mut self.settings.spread, 1.5..=4.5).text("Spacing"));
                ui.add(egui::Slider::new(&mut self.settings.distance, 4.0..=14.0).text("Distance"));
                ui.add_space(16.0);
                ui.separator();
                ui.add_space(10.0);
                ui.label(RichText::new("Windows").size(18.0).strong());
                egui::ScrollArea::vertical().show(ui, |ui| {
                    let renderer = self.renderer.lock();
                    for (index, card) in renderer.cards.iter().enumerate() {
                        ui.add_space(5.0);
                        if ui
                            .selectable_label(self.selected == index, &card.title)
                            .clicked()
                        {
                            self.selected = index;
                        }
                        ui.label(
                            RichText::new(format!(
                                "{} · {} × {}",
                                card.app,
                                card.image.width(),
                                card.image.height()
                            ))
                            .small()
                            .weak(),
                        );
                    }
                    ui.add_space(18.0);
                    ui.separator();
                    ui.label(RichText::new(&renderer.device).small().weak());
                });
            });
        egui::CentralPanel::default()
            .frame(egui::Frame::NONE)
            .show(ctx, |ui| {
                let (rect, response) =
                    ui.allocate_exact_size(ui.available_size(), egui::Sense::click_and_drag());
                ui.painter()
                    .rect_filled(rect, 0.0, Color32::from_rgb(14, 15, 23));
                let center = rect.center();
                for step in -20..=20 {
                    let x = center.x + step as f32 * 48.0;
                    if x >= rect.left() && x <= rect.right() {
                        ui.painter().line_segment(
                            [egui::pos2(x, rect.top()), egui::pos2(x, rect.bottom())],
                            egui::Stroke::new(0.5, Color32::from_rgb(27, 27, 39)),
                        );
                    }
                    let y = center.y + step as f32 * 48.0;
                    if y >= rect.top() && y <= rect.bottom() {
                        ui.painter().line_segment(
                            [egui::pos2(rect.left(), y), egui::pos2(rect.right(), y)],
                            egui::Stroke::new(0.5, Color32::from_rgb(27, 27, 39)),
                        );
                    }
                }
                if response.dragged() {
                    self.settings.orbit =
                        (self.settings.orbit + response.drag_motion().x * 0.15).clamp(-40.0, 40.0);
                }
                if response.hovered() {
                    self.settings.distance = (self.settings.distance
                        - ctx.input(|i| i.smooth_scroll_delta.y) * 0.01)
                        .clamp(4.0, 14.0);
                }
                let renderer = self.renderer.lock();
                let mut windows: Vec<_> = renderer
                    .cards
                    .iter()
                    .enumerate()
                    .map(|(index, card)| {
                        let offset = index as f32 - self.focus;
                        (
                            index,
                            scene::transform(
                                self.settings,
                                card.aspect(),
                                rect.aspect_ratio(),
                                offset,
                            ),
                            index == self.selected,
                        )
                    })
                    .collect();
                windows.sort_by(|a, b| {
                    (b.0 as f32 - self.focus)
                        .abs()
                        .total_cmp(&(a.0 as f32 - self.focus).abs())
                });
                if response.clicked()
                    && let Some(pointer) = response.interact_pointer_pos()
                {
                    let ndc = (pointer - rect.min) / rect.size() * 2.0 - Vec2::splat(1.0);
                    if let Some(&(index, _, _)) = windows
                        .iter()
                        .rev()
                        .find(|(_, mvp, _)| scene::hit(*mvp, ndc.x, -ndc.y))
                    {
                        self.selected = index;
                    }
                }
                drop(renderer);
                let renderer = self.renderer.clone();
                ui.painter().add(egui::PaintCallback {
                    rect,
                    callback: Arc::new(egui_glow::CallbackFn::new(move |_, painter| {
                        renderer.lock().paint(painter.gl(), &windows);
                    })),
                });
            });
        if self.capture.is_some() {
            ctx.request_repaint_after(Duration::from_millis(100));
        }
    }

    fn on_exit(&mut self, gl: Option<&eframe::glow::Context>) {
        if let Some(gl) = gl {
            // The application context remains alive until eframe finishes exit.
            let renderer = &mut *self.renderer.lock();
            // Renderer teardown needs only a borrowed context.
            renderer.destroy_borrowed(gl);
        }
    }
}

fn main() -> Result<()> {
    let args: Vec<String> = std::env::args().skip(1).collect();
    if args.first().is_some_and(|arg| arg == "--serve-clipboard") {
        return capture::serve_clipboard();
    }
    if args.first().is_some_and(|arg| arg == "--capture-check") {
        let cards = capture::current_windows()?;
        println!(
            "Captured {} windows; clipboard restoration completed",
            cards.len()
        );
        return Ok(());
    }
    if args.iter().any(|arg| arg == "--help") {
        println!(
            "ohmansy spatial lab\n\nUsage: mise run spatial -- [--demo] [--close-after SECONDS] [--screenshot PNG]\n\nDisplays captured Niri windows as textured planes. Existing apps stay in place.\nCaptures are snapshots; use Refresh windows to update. Clicks select cards.\nDrag to orbit, scroll to zoom, arrow keys to select, R to reset.\nTest surfaces contain a 2x source; captured windows retain their original pixels."
        );
        return Ok(());
    }
    let mut demo = false;
    let mut screenshot = None;
    let mut close_after = None;
    let mut args = args.iter();
    while let Some(arg) = args.next() {
        match arg.as_str() {
            "--demo" => demo = true,
            "--screenshot" => {
                screenshot = Some(PathBuf::from(
                    args.next().context("--screenshot needs a PNG path")?,
                ))
            }
            "--close-after" => {
                close_after = Some(Duration::from_secs(
                    args.next()
                        .context("--close-after needs seconds")?
                        .parse()
                        .context("Invalid seconds")?,
                ))
            }
            _ => anyhow::bail!("Unknown argument: {arg}. Use --help for usage."),
        }
    }
    let options = eframe::NativeOptions {
        viewport: egui::ViewportBuilder::default()
            .with_title("ohmansy spatial lab")
            .with_app_id("ohmansy-spatial")
            .with_inner_size([1360.0, 850.0])
            .with_min_inner_size([800.0, 500.0]),
        renderer: eframe::Renderer::Glow,
        ..Default::default()
    };
    eframe::run_native(
        "ohmansy spatial lab",
        options,
        Box::new(move |cc| Ok(Box::new(Lab::new(cc, demo, close_after, screenshot)?))),
    )
    .map_err(|error| anyhow::anyhow!("{error}"))
}
