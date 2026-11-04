# Shine

Shine is ohmansy's experimental scrolling Wayland compositor.

## Login session

The shared ohmansy desktop includes an alternative session. At the login screen,
choose **Shine (experimental)** in **Session**, then sign in normally.
**ohmansy (Niri)** remains the default. Installed systems need a rebuild to get
the session package and updated greeter; an existing boot image stays unchanged.
Follow [the installed-system workflow](linux-development.md) and plan a reboot
for login-manager updates rather than restarting greetd from a running desktop.
Use `mise run os-boot` to build this checkout for the next boot, then reboot
when ready to try the updated login screen.

The experimental session opens your configured terminal and normal login shell.
**Super+D** opens the application picker. **Super+Shift+E** opens a sign-out
confirmation; Cancel keeps the desktop running, while Sign out returns to the
login screen. Applications use their normal profiles in this session.

Cage supplies DRM/KMS display handling, input devices, and VT switching. It hosts
Shine fullscreen, which manages its own clients and layout.
This adds a composition layer; it is a bridge until the compositor has its own
hardware backend. The session currently uses one monitor (Cage's last connected
output). Niri's panel, wallpaper, and services remain tied to Niri.

This session is experimental: it has no screen locking, screen sharing, IME,
X11 support, or complete desktop portal integration. Keep Niri available as the
regular desktop. A private D-Bus session keeps app activation on the correct
Wayland socket without changing another session's activation environment.

To omit it from a host configuration:

```nix
ohmansy.compositor.enable = false;
```

The session package also supports an explicit nested preview:

```sh
nix run .#compositor-session -- --nested
```

The module honors `ohmansy.terminal`; the standalone flake preview uses Foot.
Close the preview's outer window or use its sign-out confirmation to end it.

## Nested development demo

Run the Shine desktop experiment inside the current Wayland desktop:

```sh
mise run compositor-desktop
```

It opens a nested desktop with a new terminal, Firefox, and GNOME Text Editor.
These are interactive applications on a private Wayland socket. Firefox uses a
fresh profile, and the editor uses separate application state under ignored
`.local/compositor-demo/`. Commands in the new terminal execute on this machine.
Closing the outer window ends the nested session and disconnects its clients.

Windows form a horizontal strip with persistent widths. Focusing a window
scrolls it into view; adding another window keeps existing widths. There are
four workspaces, fullscreen, client maximize requests, and column resizing.
Click a window to focus it. **Mod** means **Super** in a login session and
**Super+Alt** in a nested demo or packaged `--nested` preview. The host matches
Super without Alt, so it forwards the child's Super+Alt shortcuts. Add Shift
for the actions below. `--mod-key super|super-alt` overrides the default.

When nesting under the supplied Niri configuration, use the arrow keys for
navigation: Niri reserves Super+Alt+L for screen locking.

| Shortcut | Action |
| --- | --- |
| Mod+H/L or Left/Right | Focus previous/next column |
| Mod+Shift+H/L or Left/Right | Move column left/right |
| Mod+minus/equal | Narrow/widen the focused column |
| Mod+1–4 | Switch workspace |
| Mod+Shift+1–4 | Move the focused window to a workspace |
| Mod+Enter | Open a terminal |
| Mod+F | Toggle fullscreen |
| Mod+Q | Close the focused window |
| Mod+S | Cycle display scale from 100% to 200% |

Ctrl+Alt+function keys are reserved for switching Linux virtual terminals.

`mise run compositor` starts the smaller terminal and animated terminal demo.
The separate [spatial lab](spatial-lab.md) demonstrates 3D presentation using
snapshots. Those transforms are not applied to live clients.

## Rendering and application support

The compositor requests a fixed 2× render density through integer and fractional
scale protocols. A separate display scale controls the final presentation.
Wayland clients choose their buffers: a modern client can submit a 2× image
using `buffer_scale=1` and a viewporter destination. Inspect `render_density`,
rather than just `buffer_scale`, in the status report. Native trials verified
Foot, Firefox, and GTK at 2×, including at 150% presentation scale.

The compositor supports GPU DMA-BUF imports, viewporter, fractional scale,
client decorations, popup grabs, cursor surfaces, and clipboard and primary
selection between nested clients. It redraws when surfaces change, input arrives,
or the viewport animates. An empty idle workspace stops rendering frames.

Named Wayland cursors use the packaged Adwaita theme, including a `default`
theme alias. The session, standalone package, and development shell supply the
cursor assets while honoring existing `XCURSOR_THEME`, `XCURSOR_SIZE`, and
`XCURSOR_PATH` preferences. These Xcursor settings also apply to Wayland cursor
images; they are not limited to X11.

The Smithay compositor has no direct display/input backend of its own; the login
session uses Cage for that role. The development demo runs directly inside the
parent desktop. Clipboard exchange is local to its clients. X11 clients and
moving existing Niri windows into it are unsupported. Its 3D presentation remains
in the separate snapshot experiment.

## Development

Rust is pinned in `mise.toml`. The shared `.#spatial` Nix shell supplies NixOS's
patched rustup, a C compiler, native graphics libraries, and the demo applications.
On a fresh NixOS checkout, bootstrap once before mise auto-installs its generic
Rust tool:

```sh
OHMANSY_EXPERIMENT=compositor bash tools/dev/spatial.sh run
```

Source is in `nix/compositor/`, with upstream attribution beside it. Keeping it
under `nix/` includes it in shipped release sources and offline rebuild inputs.
Nix packages and the session module live in `nix/modules/compositor*.nix`.
Both Rust experiments share the incremental cache in `.build/spatial/`.
Restart the nested process to try code changes; no OS rebuild is needed.

```sh
mise run compositor-check
mise run compositor-integration
python3 tools/tests/compositor_nesting.py
mise run compositor -- --scale 1.5 --close-after 10
```

The integration task creates disposable Firefox, GTK editor, and terminal clients
and checks rendering, input, scrolling, menus, clipboard, workspaces, and idle
frames. It requires a running Niri or ohmansy desktop. Test input goes through a private
control socket into the normal compositor handlers; `--test-input` enables this
path and ignores physical input from the parent window during the trial.
Artifacts stay in ignored `.local/compositor-tests/`.
The nesting trial checks real Wayland key forwarding between a Super host and
a Super+Alt child, including focus changes and independent scale shortcuts.

After building `nix build --out-link .local/compositor-session .#compositor-session`,
`python3 tools/tests/compositor_session.py` checks the packaged Cage session,
normal terminal, app picker, canceled and confirmed sign-out, and preservation
of the parent desktop and its activation environment. Add `--headless` to exercise
Cage's headless backend without a parent display. These checks do not establish
a successful physical DRM login or a booted system image.

For local automation or a future shell, enable the private control socket:

```sh
mise run compositor-desktop -- --control-socket .local/compositor-control.sock
```

In another terminal, use the built binary:

```sh
.build/spatial/debug/ohmansy-compositor msg --socket .local/compositor-control.sock status
.build/spatial/debug/ohmansy-compositor msg --socket .local/compositor-control.sock scale 150
.build/spatial/debug/ohmansy-compositor msg --socket .local/compositor-control.sock launch foot
```

The socket has owner-only permissions. Status includes window geometry, workspace,
render density, and render/import counters. Commands also include `focus ID`,
`focus-next`, `focus-prev`, `move-next`, `move-prev`, `resize DELTA`, `workspace N`,
`move-workspace N`, `fullscreen`, `terminal`, `close`, `screenshot PNG`, and `quit`.
Test key and pointer commands are disabled in normal sessions.

`--socket-file PATH` writes the nested Wayland socket name for launching clients
with an explicit `WAYLAND_DISPLAY`. `-- COMMAND ARGS...` runs a custom application
instead of the default demos. Use separate-instance options for applications
that normally reuse a running process. Do not import the experimental display
into the global systemd or D-Bus environment.

`--screenshot PATH.png` saves the framebuffer after startup without changing the
clipboard. `--report PATH.json` writes final status when the session ends. Keep
these development artifacts under ignored `.local/`.
