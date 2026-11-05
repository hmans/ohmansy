#![allow(irrefutable_let_patterns)]

mod desktop;
mod grabs;
mod handlers;
mod input;
mod ipc;
mod layout;
mod native;
mod output_config;
mod output_control;
mod preferences;
mod scene;
mod state;
mod winit;

use anyhow::{Context, Result};
use smithay::reexports::{
    calloop::EventLoop,
    wayland_server::{Display, DisplayHandle},
};
pub use state::Smallvil;
use std::{
    path::PathBuf,
    time::{Duration, Instant},
};

pub struct CalloopData {
    state: Smallvil,
    display_handle: DisplayHandle,
}

fn asset_path(name: &str) -> PathBuf {
    PathBuf::from(option_env!("OHMANSY_COMPOSITOR_ASSETS").unwrap_or(env!("CARGO_MANIFEST_DIR")))
        .join(name)
}

pub fn spawn_session_tool(socket: &std::ffi::OsStr, name: &str) -> Result<()> {
    let program = std::env::var(format!("OHMANSY_COMPOSITOR_{name}"))
        .with_context(|| format!("{name} is available through ohmansy-compositor-session"))?;
    spawn_application(socket, &program, &[])
}

pub fn spawn_application(socket: &std::ffi::OsStr, program: &str, args: &[String]) -> Result<()> {
    spawn_application_with_env(socket, program, args, &Default::default())
}

pub fn spawn_application_with_env(
    socket: &std::ffi::OsStr,
    program: &str,
    args: &[String],
    environment: &std::collections::BTreeMap<String, String>,
) -> Result<()> {
    let child = std::process::Command::new(program)
        .args(args)
        .envs(environment)
        .env("WAYLAND_DISPLAY", socket)
        .env_remove("WAYLAND_SOCKET")
        .env_remove("DISPLAY")
        .env_remove("NIRI_SOCKET")
        .env("MOZ_ENABLE_WAYLAND", "1")
        .env("GDK_BACKEND", "wayland")
        .env("QT_QPA_PLATFORM", "wayland")
        .env("GTK_USE_PORTAL", "0")
        .spawn()
        .with_context(|| format!("Launch {program}"))?;
    eprintln!("Started nested application {program}, PID {}", child.id());
    std::thread::spawn(move || {
        let mut child = child;
        let _ = child.wait();
    });
    Ok(())
}

fn desktop_demo(socket: &std::ffi::OsStr) -> Result<()> {
    use std::os::unix::fs::DirBuilderExt;
    let base = std::env::current_dir()?.join(".local/compositor-demo");
    std::fs::create_dir_all(&base)?;
    let profile = base.join(format!(
        "{}-{}",
        std::process::id(),
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)?
            .as_nanos()
    ));
    std::fs::DirBuilder::new().mode(0o700).create(&profile)?;
    std::fs::write(profile.join("user.js"), "user_pref(\"browser.shell.checkDefaultBrowser\", false);\nuser_pref(\"browser.aboutwelcome.enabled\", false);\nuser_pref(\"browser.startup.homepage_override.mstone\", \"ignore\");\n")?;
    spawn_terminal(socket, false)?;
    let editor_environment = ["DATA", "CONFIG", "CACHE", "STATE"]
        .into_iter()
        .map(|kind| {
            (
                format!("XDG_{kind}_HOME"),
                profile
                    .join(format!("editor-{}", kind.to_lowercase()))
                    .to_string_lossy()
                    .into_owned(),
            )
        })
        .collect();
    spawn_application_with_env(
        socket,
        "gnome-text-editor",
        &["--standalone".into()],
        &editor_environment,
    )?;
    spawn_application(
        socket,
        "firefox",
        &[
            "--no-remote".into(),
            "--profile".into(),
            profile.to_string_lossy().into_owned(),
            format!(
                "file://{}?mod={}",
                asset_path("demo.html").display(),
                std::env::var("OHMANSY_COMPOSITOR_MODIFIER")
                    .unwrap_or_else(|_| "Super+Alt".into())
                    .replace('+', "%2B")
            ),
        ],
    )?;
    eprintln!("Separate demo browser profile: {}", profile.display());
    Ok(())
}

pub fn spawn_terminal(socket: &std::ffi::OsStr, demo: bool) -> Result<()> {
    let mut command = std::process::Command::new("foot");
    command
        .env("WAYLAND_DISPLAY", socket)
        .env_remove("WAYLAND_SOCKET")
        .env_remove("DISPLAY")
        .env_remove("NIRI_SOCKET")
        .env("XDG_CURRENT_DESKTOP", "ohmansy-lab")
        .args(["--app-id=ohmansy-nested-client", "--title=Shine terminal"]);
    if demo {
        command
            .args(["--title=Shine live surface", "python3"])
            .arg(asset_path("demo.py"));
    } else {
        command
            .env("PS1", "Shine> ")
            .env_remove("PROMPT_COMMAND")
            .args(["bash", "--noprofile", "--norc", "-i"]);
    }
    let child = command
        .spawn()
        .context("Launch a new isolated Foot client")?;
    eprintln!("Started nested client PID {}", child.id());
    // Reap only the child we created. Closing the server disconnects its own
    // clients; no existing terminal, compositor, or desktop service is killed.
    std::thread::spawn(move || {
        let mut child = child;
        let _ = child.wait();
    });
    Ok(())
}

fn main() -> Result<()> {
    let initial: Vec<String> = std::env::args().skip(1).collect();
    if initial.first().is_some_and(|arg| arg == "validate") {
        anyhow::ensure!(
            initial.len() == 2,
            "Usage: ohmansy-compositor validate PATH"
        );
        let settings = output_config::Settings::parse(&std::fs::read_to_string(&initial[1])?)
            .map_err(anyhow::Error::msg)?;
        preferences::bindings(&settings.bindings, input::ShortcutModifier::SuperAlt)
            .map_err(anyhow::Error::msg)?;
        println!("Shine configuration is valid (display modes and geometry are checked against connected outputs when applied).");
        return Ok(());
    }
    if initial.first().is_some_and(|argument| argument == "msg") {
        anyhow::ensure!(
            initial.get(1).is_some_and(|value| value == "--socket"),
            "Usage: ohmansy-compositor msg --socket PATH [action] [value]"
        );
        return ipc::send(
            initial.get(2).context("Missing control socket path")?,
            &initial[3..],
        );
    }
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env().unwrap_or_else(|_| "warn".into()),
        )
        .init();

    let mut scale = 1.25_f64;
    let mut outputs = 1;
    let mut backend = "winit".to_owned();
    let mut config_path = None;
    let mut close_after = None;
    let mut socket_file: Option<PathBuf> = None;
    let mut screenshot = None;
    let mut report: Option<PathBuf> = None;
    let mut no_clients = false;
    let mut desktop = false;
    let mut session_mode = false;
    let mut shortcut_modifier = None;
    let mut test_input = false;
    let mut control_socket = None;
    let mut client = vec![];
    let mut args = std::env::args().skip(1);
    while let Some(arg) = args.next() {
        match arg.as_str() {
            "--help" => {
                println!("Shine\n\nUsage: mise run compositor -- [--desktop | --session] [--mod-key super|super-alt] [--backend winit|drm] [--outputs 2] [--scale 1.25] [--config PATH] [--control-socket PATH] [--close-after SECONDS] [--socket-file PATH] [--no-clients] [-- COMMAND ARGS...]\n\nMod is Super in login sessions and Super+Alt in nested demos.\nMod+H/L or Left/Right: focus column\nMod+Shift+H/L: move column\nMod+comma/period: focus monitor; add Shift to move window\nMod+minus/plus (or equal): scale by 5 percentage points; Mod+Ctrl+minus/equal: resize column\nMod+1..4: workspace; add Shift to move the window\nMod+Enter: terminal; F: fullscreen; Q: close; S: display scale\nMod+D: applications; Mod+Shift+E: sign out (session mode)\n\nmsg --socket PATH status|focus-next|focus-prev|resize DELTA|workspace INDEX|move-workspace INDEX|fullscreen|scale PERCENT|terminal|close|launch PROGRAM ARGS...|screenshot PNG\n\noutput position NAME X Y; output layout NAME X Y [NAME X Y...]; output scale NAME PERCENT; output primary NAME; output mode NAME WIDTHxHEIGHT[@HZ]; output reset NAME\nconfig reload|save; edits to ~/.config/shine/config.toml reload automatically.\n\n--desktop starts isolated browser/editor clients. --session uses the installed session wrapper. --test-input enables control-socket input for automated trials and ignores parent input.\nClose the outer window to end only this experimental session.");
                return Ok(());
            }
            "--scale" => scale = args.next().context("--scale needs a number")?.parse()?,
            "--outputs" => {
                outputs = args
                    .next()
                    .context("--outputs needs a number")?
                    .parse::<usize>()?
            }
            "--backend" => backend = args.next().context("--backend needs winit or drm")?,
            "--config" => {
                config_path = Some(PathBuf::from(
                    args.next().context("--config needs a TOML path")?,
                ))
            }
            "--close-after" => {
                close_after = Some(Duration::from_secs(
                    args.next()
                        .context("--close-after needs seconds")?
                        .parse()?,
                ))
            }
            "--socket-file" => {
                socket_file = Some(PathBuf::from(
                    args.next().context("--socket-file needs a path")?,
                ))
            }
            "--screenshot" => {
                screenshot = Some(PathBuf::from(
                    args.next().context("--screenshot needs a PNG path")?,
                ))
            }
            "--report" => {
                report = Some(PathBuf::from(
                    args.next().context("--report needs a JSON path")?,
                ))
            }
            "--no-clients" => no_clients = true,
            "--desktop" => desktop = true,
            "--session" => session_mode = true,
            "--mod-key" => {
                shortcut_modifier = Some(
                    input::ShortcutModifier::parse(
                        &args.next().context("--mod-key needs super or super-alt")?,
                    )
                    .map_err(anyhow::Error::msg)?,
                );
            }
            "--test-input" => test_input = true,
            "--control-socket" => {
                control_socket = Some(PathBuf::from(
                    args.next().context("--control-socket needs a path")?,
                ))
            }
            "--" => {
                client.extend(args);
                break;
            }
            _ => anyhow::bail!("Unknown argument: {arg}"),
        }
    }
    anyhow::ensure!(
        scale.is_finite() && (0.5..=2.0).contains(&scale),
        "Scale must be between 0.5 and 2.0"
    );
    anyhow::ensure!(
        backend != "drm" || screenshot.is_none(),
        "Framebuffer screenshots currently require the winit backend"
    );
    anyhow::ensure!(
        backend == "drm" || std::env::var_os("WAYLAND_DISPLAY").is_some(),
        "Use ohmansy-compositor-session for a login session, or start inside a Wayland desktop"
    );
    anyhow::ensure!(
        !(session_mode && desktop),
        "Choose session mode or the desktop demo"
    );
    let mut event_loop: EventLoop<CalloopData> = EventLoop::try_new()?;
    let display: Display<Smallvil> = Display::new()?;
    let display_handle = display.handle();
    let mut state = Smallvil::new(&mut event_loop, display);
    state.ui_scale = scale;
    state.default_output_scale = scale;
    anyhow::ensure!((1..=8).contains(&outputs), "Choose 1 to 8 preview outputs");
    state.virtual_outputs = outputs;
    state.native_mode = backend == "drm";
    state.test_input = test_input;
    state.session_mode = session_mode;
    state.shortcut_modifier = shortcut_modifier.unwrap_or(if session_mode {
        input::ShortcutModifier::Super
    } else {
        input::ShortcutModifier::SuperAlt
    });
    state.init_output_config(config_path)?;
    std::env::set_var(
        "OHMANSY_COMPOSITOR_MODIFIER",
        state.shortcut_modifier.label(),
    );
    state.screenshot = screenshot;
    let mut data = CalloopData {
        state,
        display_handle,
    };
    match backend.as_str() {
        "winit" => crate::winit::init_winit(&mut event_loop, &mut data)?,
        "drm" => crate::native::init_native(&mut event_loop, &mut data)?,
        _ => anyhow::bail!("Backend must be winit or drm"),
    }
    let control_path = control_socket.unwrap_or_else(|| {
        PathBuf::from(std::env::var_os("XDG_RUNTIME_DIR").unwrap())
            .join(format!("ohmansy-compositor-{}.sock", std::process::id()))
    });
    let _control = ipc::start(&event_loop, control_path.clone())?;
    std::env::set_var("OHMANSY_COMPOSITOR_CONTROL", &control_path);
    eprintln!("Control socket: {}", control_path.display());

    eprintln!(
        "Nested Wayland socket: {}",
        data.state.socket_name.to_string_lossy()
    );
    eprintln!(
        "Client render scale: 2x; display scale: {scale}x. {}+Enter terminal; H/L focus; S scale.",
        data.state.shortcut_modifier.label()
    );
    if let Some(path) = &socket_file {
        std::fs::write(path, data.state.socket_name.to_string_lossy().as_bytes())?;
    }
    if !client.is_empty() {
        let child = std::process::Command::new(&client[0])
            .args(&client[1..])
            .env("WAYLAND_DISPLAY", &data.state.socket_name)
            .env_remove("WAYLAND_SOCKET")
            .env_remove("DISPLAY")
            .env_remove("NIRI_SOCKET")
            .spawn()?;
        std::thread::spawn(move || {
            let mut child = child;
            let _ = child.wait();
        });
    } else if session_mode {
        // The session wrapper creates a private D-Bus session. Update only that
        // bus, after our own Wayland socket exists; never import into systemd.
        let setup = std::env::var("OHMANSY_COMPOSITOR_SESSION_SETUP")
            .context("Start session mode through ohmansy-compositor-session")?;
        let status = std::process::Command::new(setup)
            .env("WAYLAND_DISPLAY", &data.state.socket_name)
            .status()?;
        anyhow::ensure!(
            status.success(),
            "Initialize the desktop session environment"
        );
        if !no_clients {
            spawn_session_tool(&data.state.socket_name, "TERMINAL")?;
        }
    } else if desktop {
        desktop_demo(&data.state.socket_name)?;
    } else if !no_clients {
        spawn_terminal(&data.state.socket_name, false)?;
        spawn_terminal(&data.state.socket_name, true)?;
    }
    let started = Instant::now();
    event_loop.run(Some(Duration::from_millis(50)), &mut data, |data| {
        // Protocol replies must reach clients even when no frame is drawn.
        let _ = data.display_handle.flush_clients();
        if close_after.is_some_and(|duration| started.elapsed() >= duration) {
            data.state.loop_signal.stop();
        }
    })?;
    if let Some(path) = report {
        use smithay::{
            backend::renderer::utils::RendererSurfaceStateUserData,
            wayland::compositor::with_states,
        };
        let scales: Vec<_> = data
            .state
            .space
            .elements()
            .filter_map(|window| {
                with_states(window.toplevel()?.wl_surface(), |states| {
                    states
                        .data_map
                        .get::<RendererSurfaceStateUserData>()
                        .map(|state| state.lock().unwrap().buffer_scale())
                })
            })
            .collect();
        let mut report = data.state.status();
        report["client_buffer_scales"] = serde_json::json!(scales);
        std::fs::write(path, serde_json::to_vec_pretty(&report)?)?;
        eprintln!("Verification: {report}");
    }
    if let Some(path) = socket_file {
        // Remove only our own handoff, never another instance's socket file.
        if std::fs::read_to_string(&path)
            .is_ok_and(|name| name == data.state.socket_name.to_string_lossy())
        {
            let _ = std::fs::remove_file(path);
        }
    }
    if let Some(error) = data.state.runtime_error {
        anyhow::bail!("Shine stopped: {error}");
    }
    Ok(())
}
