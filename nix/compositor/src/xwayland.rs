//! A session-owned satellite. Readiness requires Wayland dispatch, so never
//! wait for it with Command::status() before entering the compositor loop.
use anyhow::{Context, Result};
use smithay::reexports::rustix::process::{
    getpid, getppid, kill_process_group, set_parent_process_death_signal, Pid, Signal,
};
use std::{
    os::unix::{net::UnixDatagram, process::CommandExt},
    path::PathBuf,
    process::{Child, Command},
    time::{Duration, Instant},
};

pub struct Satellite {
    child: Child,
    notify: UnixDatagram,
    path: PathBuf,
    pub display: String,
}

impl Satellite {
    pub fn start(socket: &std::ffi::OsStr) -> Result<Self> {
        // Xwayland arbitrates the lock atomically itself. Skip occupied slots;
        // if another server wins the race, startup fails rather than using it.
        let number = (0..128)
            .find(|n| {
                !PathBuf::from(format!("/tmp/.X{n}-lock")).exists()
                    && !PathBuf::from(format!("/tmp/.X11-unix/X{n}")).exists()
            })
            .context("No free X11 display")?;
        let display = format!(":{number}");
        let path = PathBuf::from(
            std::env::var_os("XDG_RUNTIME_DIR").context("Missing runtime directory")?,
        )
        .join(format!("shine-xwayland-{}.notify", std::process::id()));
        let notify = UnixDatagram::bind(&path)?;
        notify.set_nonblocking(true)?;
        let program = std::env::var_os("OHMANSY_XWAYLAND_SATELLITE")
            .unwrap_or_else(|| "xwayland-satellite".into());
        let parent = getpid();
        let mut command = Command::new(program);
        command
            .args([&display, "-nolisten", "tcp"])
            .env("WAYLAND_DISPLAY", socket)
            .env("NOTIFY_SOCKET", &path)
            .env_remove("WAYLAND_SOCKET")
            .env_remove("DISPLAY")
            .process_group(0);
        // The bridge must also disappear if the compositor crashes or is
        // terminated before Rust can drop the session guard. Xwayland exits
        // when satellite's WM connection closes.
        unsafe {
            command.pre_exec(move || {
                set_parent_process_death_signal(Some(Signal::TERM))?;
                if getppid() != Some(parent) {
                    return Err(std::io::Error::other(
                        "Shine exited during satellite startup",
                    ));
                }
                Ok(())
            });
        }
        let child = match command.spawn() {
            Ok(child) => child,
            Err(error) => {
                let _ = std::fs::remove_file(&path);
                return Err(error).context("Start Xwayland satellite");
            }
        };
        Ok(Self {
            child,
            notify,
            path,
            display,
        })
    }

    pub fn ready(&mut self) -> Result<bool> {
        if let Some(status) = self.child.try_wait()? {
            anyhow::bail!("Xwayland satellite exited: {status}");
        }
        let mut message = [0; 4096];
        match self.notify.recv(&mut message) {
            Ok(len) => Ok(message[..len]
                .split(|b| *b == b'\n')
                .any(|line| line == b"READY=1")),
            Err(error) if error.kind() == std::io::ErrorKind::WouldBlock => Ok(false),
            Err(error) => Err(error.into()),
        }
    }
}

impl Drop for Satellite {
    fn drop(&mut self) {
        // Satellite and its Xwayland child share a private process group.
        if let Some(pid) = Pid::from_raw(self.child.id() as i32) {
            let _ = kill_process_group(pid, Signal::TERM);
            let deadline = Instant::now() + Duration::from_secs(2);
            while matches!(self.child.try_wait(), Ok(None)) && Instant::now() < deadline {
                std::thread::sleep(Duration::from_millis(10));
            }
            let _ = kill_process_group(pid, Signal::KILL);
            let _ = self.child.wait();
        }
        let _ = std::fs::remove_file(&self.path);
    }
}
