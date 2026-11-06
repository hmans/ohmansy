//! Private local commands for testing, launchers, and future shell integration.
use crate::CalloopData;
use anyhow::{Context, Result};
use serde_json::{json, Value};
use smithay::reexports::calloop::{channel, EventLoop};
use std::{
    io::{BufRead, BufReader, Read, Write},
    os::unix::{
        fs::PermissionsExt,
        net::{UnixListener, UnixStream},
    },
    path::PathBuf,
    sync::{
        atomic::{AtomicBool, Ordering},
        mpsc, Arc,
    },
    time::Duration,
};

pub struct Server {
    path: PathBuf,
    stopped: Arc<AtomicBool>,
}

impl Drop for Server {
    fn drop(&mut self) {
        self.stopped.store(true, Ordering::Relaxed);
        let _ = std::fs::remove_file(&self.path);
    }
}

pub fn start(event_loop: &EventLoop<CalloopData>, path: PathBuf) -> Result<Server> {
    let listener = UnixListener::bind(&path).context("Create private compositor control socket")?;
    std::fs::set_permissions(&path, std::fs::Permissions::from_mode(0o600))?;
    listener.set_nonblocking(true)?;
    let stopped = Arc::new(AtomicBool::new(false));
    let stop = stopped.clone();
    let (sender, receiver) = channel::channel::<(Value, mpsc::SyncSender<Value>)>();
    event_loop
        .handle()
        .insert_source(receiver, |event, _, data| {
            if let channel::Event::Msg((request, response)) = event {
                let action = request["action"].as_str().unwrap_or("status");
                let mut app_activated = false;
                let result = if action == "activate-app" {
                    let names: Vec<_> = request["app_ids"]
                        .as_array()
                        .into_iter()
                        .flatten()
                        .filter_map(|v| v.as_str())
                        .map(str::to_owned)
                        .collect();
                    if request["wayland_display"].as_str() == data.state.socket_name.to_str() {
                        app_activated = data.state.activate_app(&names);
                    }
                    Ok(())
                } else if action == "pointer" {
                    if !data.state.test_input {
                        Err("Test input is disabled".into())
                    } else if let (Some(x), Some(y)) =
                        (request["x"].as_f64(), request["y"].as_f64())
                    {
                        data.state.process_motion(
                            (x, y).into(),
                            data.state.start_time.elapsed().as_millis() as u32,
                        );
                        Ok(())
                    } else {
                        Err("pointer needs x and y".into())
                    }
                } else if action == "button" {
                    if !data.state.test_input {
                        Err("Test input is disabled".into())
                    } else if let Some(pressed) = request["pressed"].as_bool() {
                        let state = if pressed {
                            smithay::backend::input::ButtonState::Pressed
                        } else {
                            smithay::backend::input::ButtonState::Released
                        };
                        data.state.process_button(
                            request["code"].as_u64().unwrap_or(0x110) as u32,
                            state,
                            data.state.start_time.elapsed().as_millis() as u32,
                        );
                        Ok(())
                    } else {
                        Err("button needs pressed".into())
                    }
                } else if action == "key" {
                    if !data.state.test_input {
                        Err("Test input is disabled".into())
                    } else if let (Some(code), Some(pressed)) = (
                        request["code"].as_u64().filter(|code| *code <= 255),
                        request["pressed"].as_bool(),
                    ) {
                        let key = smithay::input::keyboard::Keycode::new(code as u32 + 8);
                        let state = if pressed {
                            smithay::backend::input::KeyState::Pressed
                        } else {
                            smithay::backend::input::KeyState::Released
                        };
                        data.state.process_key(
                            key,
                            state,
                            data.state.start_time.elapsed().as_millis() as u32,
                        );
                        Ok(())
                    } else {
                        Err("key needs a physical code and pressed boolean".into())
                    }
                } else if action == "screenshot-screen" {
                    data.state.request_screenshot(
                        request["path"].as_str().map(PathBuf::from),
                        request["annotate"].as_bool().unwrap_or(false),
                    )
                } else if action == "screenshot" {
                    if data.state.native_mode {
                        Err("Framebuffer screenshots are currently available in nested mode".into())
                    } else if let Some(path) = request["path"].as_str() {
                        data.state.screenshot = Some(PathBuf::from(path));
                        data.state.needs_redraw = true;
                        Ok(())
                    } else {
                        Err("screenshot needs a path".into())
                    }
                } else if matches!(
                    action,
                    "configure-outputs" | "configure-lighting" | "reload-config" | "save-config"
                ) {
                    data.state.output_request(action, &request)
                } else if action == "status" {
                    Ok(())
                } else if action == "quit" {
                    data.state.loop_signal.stop();
                    Ok(())
                } else if action == "task" {
                    data.state.focus_task(request["id"].as_str().unwrap_or(""))
                } else if action == "launch" {
                    let program = request["program"].as_str().unwrap_or("");
                    let args: Vec<String> = request["args"]
                        .as_array()
                        .into_iter()
                        .flatten()
                        .filter_map(|v| v.as_str().map(str::to_owned))
                        .collect();
                    if program.is_empty() {
                        Err("launch needs a program".into())
                    } else {
                        let environment = request["env"]
                            .as_object()
                            .into_iter()
                            .flatten()
                            .filter_map(|(key, value)| {
                                value.as_str().map(|value| (key.clone(), value.to_owned()))
                            })
                            .collect();
                        crate::spawn_application_with_env(
                            &data.state.socket_name,
                            program,
                            &args,
                            &environment,
                        )
                        .map_err(|e| e.to_string())
                    }
                } else {
                    let output = request["output"].as_str();
                    let target = output.and_then(|name| {
                        data.state
                            .layout
                            .monitors
                            .iter()
                            .position(|m| m.name == name)
                    });
                    if output.is_some() && target.is_none() {
                        Err("Output does not exist".into())
                    } else {
                        if let Some(index) = target {
                            data.state.layout.focus_monitor(index);
                        }
                        data.state.action(action, request["value"].as_i64())
                    }
                };
                let reply = match result {
                    Ok(()) => {
                        let mut state = data.state.status();
                        state["screenshot"] = json!(data.state.capture.last);
                        state["app_activated"] = json!(app_activated);
                        json!({"ok":true,"state":state})
                    }
                    Err(error) => json!({"ok":false,"error":error}),
                };
                let _ = response.send(reply);
            }
        })
        .map_err(|error| anyhow::anyhow!("{}", error.error))?;
    std::thread::spawn(move || {
        while !stop.load(Ordering::Relaxed) {
            match listener.accept() {
                Ok((mut stream, _)) => {
                    let _ = stream.set_read_timeout(Some(Duration::from_secs(1)));
                    let _ = stream.set_write_timeout(Some(Duration::from_secs(1)));
                    let mut line = String::new();
                    let read = BufReader::new((&mut stream).take(16 * 1024)).read_line(&mut line);
                    let response = match read.and_then(|_| {
                        serde_json::from_str::<Value>(&line).map_err(std::io::Error::other)
                    }) {
                        Ok(request) => {
                            let (reply, receive) = mpsc::sync_channel(1);
                            if sender.send((request, reply)).is_err() {
                                break;
                            }
                            receive.recv_timeout(Duration::from_secs(3)).unwrap_or_else(
                                |_| json!({"ok":false,"error":"Compositor did not respond"}),
                            )
                        }
                        Err(error) => json!({"ok":false,"error":error.to_string()}),
                    };
                    let _ = writeln!(stream, "{response}");
                }
                Err(error) if error.kind() == std::io::ErrorKind::WouldBlock => {
                    std::thread::sleep(Duration::from_millis(10))
                }
                Err(_) => break,
            }
        }
    });
    Ok(Server { path, stopped })
}

pub fn send(path: &str, command: &[String]) -> Result<()> {
    let action = command.first().map(String::as_str).unwrap_or("status");
    let mut request = json!({"action":action});
    if action == "config" {
        anyhow::ensure!(command.len() == 2, "Usage: config reload|save");
        request["action"] = match command[1].as_str() {
            "reload" => "reload-config",
            "save" => "save-config",
            _ => anyhow::bail!("Usage: config reload|save"),
        }
        .into();
    } else if action == "output" && command.get(1).is_some_and(|s| s.parse::<i64>().is_err()) {
        let verb = command[1].as_str();
        let mut changes = vec![];
        if verb == "layout" {
            anyhow::ensure!(
                command.len() > 2 && (command.len() - 2).is_multiple_of(3),
                "Usage: output layout NAME X Y [NAME X Y...]"
            );
            for triple in command[2..].chunks_exact(3) {
                changes.push(json!({"name":triple[0],"position":[triple[1].parse::<i32>()?,triple[2].parse::<i32>()?]}));
            }
        } else {
            let name = command.get(2).context("Output name is required")?;
            let mut change = json!({"name":name});
            match verb {
                "position" => {
                    anyhow::ensure!(command.len() == 5, "Usage: output position NAME X Y");
                    change["position"] =
                        json!([command[3].parse::<i32>()?, command[4].parse::<i32>()?]);
                }
                "scale" => {
                    anyhow::ensure!(command.len() == 4, "Usage: output scale NAME PERCENT");
                    let percent = command[3].parse::<f64>()?;
                    anyhow::ensure!(
                        percent.is_finite() && (50.0..=200.0).contains(&percent),
                        "Scale must be 50 to 200 percent"
                    );
                    change["scale"] = json!(percent / 100.0);
                }
                "mode" => {
                    anyhow::ensure!(
                        command.len() == 4,
                        "Usage: output mode NAME WIDTHxHEIGHT[@HZ]|preferred"
                    );
                    change["mode"] = json!(command[3]);
                }
                "primary" | "reset" => {
                    anyhow::ensure!(command.len() == 3, "Usage: output primary|reset NAME");
                    change[if verb == "reset" { "reset" } else { "primary" }] = true.into();
                }
                _ => anyhow::bail!("Output actions: position, layout, scale, mode, primary, reset"),
            }
            changes.push(change);
        }
        request = json!({"action":"configure-outputs","outputs":changes});
    } else if action == "task" {
        request["id"] = command
            .get(1)
            .context("task needs a workspace ID")?
            .clone()
            .into();
    } else if action == "launch" {
        request["program"] = command
            .get(1)
            .context("launch needs a program")?
            .clone()
            .into();
        request["args"] = json!(&command[2..]);
    } else if action == "screenshot-screen" {
        request["annotate"] = command.iter().skip(1).any(|arg| arg == "--annotate").into();
        if let Some(path) = command
            .iter()
            .skip(1)
            .find(|arg| arg.as_str() != "--annotate")
        {
            request["path"] = path.clone().into();
        }
    } else if action == "screenshot" {
        request["path"] = command
            .get(1)
            .context("screenshot needs a PNG path")?
            .clone()
            .into();
    } else if let Some(value) = command.get(1) {
        request["value"] = value.parse::<i64>()?.into();
    }
    let mut stream = UnixStream::connect(path).context("Connect to the experimental compositor")?;
    stream.set_read_timeout(Some(Duration::from_secs(5)))?;
    writeln!(stream, "{request}")?;
    let mut response = String::new();
    BufReader::new(stream).read_line(&mut response)?;
    let value: Value = serde_json::from_str(&response)?;
    println!("{}", serde_json::to_string_pretty(&value)?);
    anyhow::ensure!(value["ok"] == true, "Command failed");
    Ok(())
}
