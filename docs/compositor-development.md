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

Shine handles DRM/KMS displays, seat access, input devices, and VT switching
directly through Smithay, libseat, and libinput. Cage is no longer part of the
session. Without saved settings, connected monitors on the primary GPU are placed
side by side in connector order, with preferred modes and a scale of 125%.
Each monitor has four independent scrolling workspaces. Disconnecting a monitor
moves its windows to a remaining monitor. Niri's panel, wallpaper, and services
remain tied to Niri.

This session is experimental: it has no screen locking, screen sharing, IME,
X11 support, or complete desktop portal integration. Keep Niri available as the
regular desktop. Normal logins use the regular user D-Bus, so applications can
reach the login keyring. Once its Wayland socket is ready, Shine publishes the
display and desktop environment for D-Bus and systemd activation. It also
inherits the user's SSH agent, using the user manager's agent socket or GCR
when the login environment did not supply one. On logout, it clears its display
settings if they still belong to that session.

Nested previews use a separate private bus and preserve the parent desktop's
activation environment. Keyring unlock dialogs can appear in a normal login;
autologin does not provide a password to unlock an encrypted keyring.

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

It opens a nested desktop with a new terminal, Firefox, GNOME Text Editor, and
a Quickshell bar on each monitor. The bar has four workspace buttons, a Terminal
button, and a clock. Buttons act on their own monitor. Windows leave room for
the bar; fullscreen covers it. The same bar starts in the packaged Shine session.
Its QML lives in `nix/modules/shine-shell/shell.qml` and reloads on save in the
development preview. Restart the preview after changing Rust or shared UI components.

These are interactive applications on a private Wayland socket. Firefox uses a
fresh profile, and the editor uses separate application state under ignored
`.local/compositor-demo/`. Commands in the new terminal execute on this machine.
Closing the outer window ends the nested session and disconnects its clients.

The bar uses Shine's layer-shell support and private control socket, independent
of Niri's panel and services. This first version has no application menu, tray,
audio controls, or keyboard-focused layer popups. The plain `compositor` demo
stays minimal; use `compositor-desktop` to preview the bar.

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
| Mod+comma/period | Focus previous/next monitor |
| Mod+Shift+comma/period | Move window to previous/next monitor |
| Mod+minus/plus (or equal) | Decrease/increase the focused monitor's scale by 5 percentage points (50–200%) |
| Mod+Ctrl+minus/equal | Narrow/widen the focused column |
| Mod+1–4 | Switch workspace |
| Mod+Shift+1–4 | Move the focused window to a workspace |
| Mod+Enter | Open a terminal |
| Mod+F | Toggle fullscreen |
| Mod+Q | Close the focused window |
| Mod+S | Cycle the focused monitor's scale from 100% to 200% |

Ctrl+Alt+function keys are reserved for switching Linux virtual terminals.

To preview multiple monitors inside one development window:

```sh
mise run compositor-desktop -- --outputs 2
```

The halves are separate Wayland outputs, with independent scales, workspaces,
and clipping. This preview uses the same layout and rendering as the hardware
backend. Click a window or use the monitor shortcut to select its monitor.

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

Named Wayland cursors use the packaged Bibata Modern Classic theme, including
a `default` theme alias. The session, standalone package, and development shell supply the
cursor assets while honoring existing `XCURSOR_THEME`, `XCURSOR_SIZE`, and
`XCURSOR_PATH` preferences. These Xcursor settings also apply to Wayland cursor
images; they are not limited to X11.

The login session uses `--backend drm`; development uses `--backend winit`
inside the parent desktop. Native output support currently covers connectors
on one primary GPU, with preferred or explicitly selected modes. Rotation,
multi-GPU rendering, and native framebuffer screenshots are not implemented.
Clipboard exchange is local to
its clients. X11 clients and
moving existing Niri windows into it are unsupported. Its 3D presentation remains
in the separate snapshot experiment.

## Configuration

Shine uses one TOML file at `~/.config/shine/config.toml`, honoring
`XDG_CONFIG_HOME`; `--config PATH` selects a separate file for development.
Every section is optional. See the complete
[example configuration](../nix/compositor/config.example.toml) for outputs,
input, layout, bindings, application rules and animations.

Edits reload live. Unknown fields/actions, invalid widths or shortcuts, and
keyboard layouts that fail to compile keep the working configuration. Inspect
`config_error` and `preferences` in status for errors and effective preferences.
Check a file without starting a compositor:

```sh
ohmansy-compositor validate ~/.config/shine/config.toml
```

Validation checks syntax, preferences, keymaps and shortcut profiles. Supported
display modes and monitor geometry are checked against connected outputs when
the configuration is applied.

### Input, layout and animations

```toml
[input.keyboard]
layout = "us"
# variant = "dvorak"
# options = "caps:escape"

[input.touchpad]
tap = true
natural_scroll = true

[layout]
gap = 12
default_column_width = { proportion = 0.62 }

[animations]
enabled = true
duration_ms = 180
```

Keyboard fields that are omitted inherit the login's XKB defaults. Touchpad
preferences apply to native libinput touchpads and newly connected devices;
omitted options restore device defaults. Nested previews configure their own
keyboard mapping and leave the host's physical touchpads alone. Status includes
`input_devices` with native touchpad settings.

Gap is in logical pixels (0–128). Width is either a proportion greater than zero
and at most one, or a pixel width (200–32768). Proportions use the output width
minus its outer gaps; columns have a minimum width of 200. Default widths affect
new windows. Gap changes reposition existing windows while preserving their
column widths. Animations currently control scrolling; `duration_ms` is 0–5000,
and disabling animations or choosing zero snaps to the destination.

### Bindings and window rules

```toml
[bindings]
"Mod+Return" = { action = "terminal" }
"Mod+N" = { action = "launch", program = "foot", args = [] }
"Mod+1" = { action = "workspace", value = 1 }
"Mod+Shift+Right" = { action = "move-next" }
"Mod+Q" = { action = "none" }

[[window_rules]]
match = { app_id = "firefox" }
default_column_width = { proportion = 0.75 }
```

Custom bindings replace the matching default; omitted bindings keep defaults.
`none` removes a binding and lets the client receive the chord. `Mod` is Super
in a login and Super+Alt in a nested preview. Explicit Super, Alt, Ctrl/Control
and Shift modifiers are also supported, with exact modifier matching. Keys use
XKB names such as Return, Left, comma, space or F6. Ctrl+Alt+F1–F12 remain reserved
for VT switching. Key releases stay paired with intercepted presses across reloads.

Actions include terminal, launcher, logout, close, fullscreen, focus-prev/next,
move-prev/next, focus-output-prev/next, move-output-prev/next, resize, workspace,
move-workspace, output, scale, scale-adjust, launch, reload-config and save-config. Resize
uses `value` in logical pixels; workspace/move-workspace use 1–4, output is
1-based, scale uses a percentage, and scale-adjust uses a signed percentage point
delta (for example, `{ action = "scale-adjust", value = 5 }`). Launch executes the program and argument
array directly. The configured terminal action still honors the OS launcher.

Window rules match an exact, case-sensitive `app_id` from status. The last
matching rule supplies the default width when a new window identifies itself.
Existing windows retain their widths when rules or defaults reload, including
manual resizes; client minimum/maximum constraints still apply.

## Monitor configuration

Shine reads `~/.config/shine/config.toml` (or `$XDG_CONFIG_HOME/shine/config.toml`).
Use `--config PATH` for a separate development configuration. File edits reload
automatically within roughly a quarter second; no compositor restart is needed.
Invalid edits keep the last working configuration and report `config_error` in
the control socket's status. No file is created until you save or write one.

Positions use logical pixels: a 2560-pixel-wide monitor at scale 1.25 has logical
width 2048. Negative positions and vertical arrangements are supported. Monitors
must share edges so the pointer can reach every screen; overlapping rectangles
and disconnected arrangements are rejected. For example:

```toml
[[outputs]]
name = "DP-2"
position = [0, 0]
scale = 1.25

[[outputs]]
name = "DP-1"
position = [2048, 0]
scale = 1.25
primary = true
# Optional; omit to use the preferred mode:
# mode = "3440x1440@100"
```

The primary monitor receives startup focus and is the fallback when the focused
monitor disconnects. Changing primary does not steal focus from an existing window.
Unconfigured monitors join the right edge of the connected layout. If unplugging
a monitor leaves a gap, Shine temporarily arranges the survivors side by side;
the saved arrangement returns on reconnect. Windows migrate to a remaining
monitor and are preserved there when the disconnected monitor returns.

Inspect `outputs` in status for names, IDs, modes, positions and scales. A saved
rule can include `id = "edid:..."` to follow a monitor across connector changes.
Shine uses EDID serials where available; anonymous, invalid or duplicated identities
fall back to `connector:NAME`. A rule with an ID only matches that identity; omit
the ID to match the connector name. `config save` records IDs automatically and
keeps rules for disconnected monitors.

For live changes, use the built binary or installed `ohmansy-compositor`:

```sh
ohmansy-compositor msg --socket "$OHMANSY_COMPOSITOR_CONTROL" output layout DP-2 0 0 DP-1 2048 0
ohmansy-compositor msg --socket "$OHMANSY_COMPOSITOR_CONTROL" output primary DP-1
ohmansy-compositor msg --socket "$OHMANSY_COMPOSITOR_CONTROL" output scale DP-2 150
ohmansy-compositor msg --socket "$OHMANSY_COMPOSITOR_CONTROL" output mode DP-1 3440x1440@100
ohmansy-compositor msg --socket "$OHMANSY_COMPOSITOR_CONTROL" config save
```

`output position NAME X Y` moves one output; `output layout` changes multiple
positions atomically, which is useful when swapping monitors. `output reset NAME`
removes its override. A scale/mode change adjusts neighbouring positions for
ordinary horizontal or vertical layouts; more complex layouts may need a single
configuration edit with all positions. Modes must come from the reported list;
`preferred` restores automatic selection. Nested output resolutions follow the
host window, so explicit resolution changes are available on the DRM backend.

Live commands remain temporary until `config save`. `config reload` explicitly
reloads the file. Saves are atomic and refuse to overwrite a symlink or an external
edit that has not been successfully reloaded. Output saves preserve comments,
unchanged values' formatting, and all handwritten preference sections. If Nix manages the file, edit its
source instead. There is no visual arrangement editor yet.

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
python3 tools/tests/compositor_monitors.py
python3 tools/tests/compositor_preferences.py
nix build .#checks.x86_64-linux.compositor-drm
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
`python3 tools/tests/compositor_session.py` checks the packaged nested session,
normal terminal, app picker, canceled and confirmed sign-out, and preservation
of the parent desktop and its activation environment. The `compositor-drm` NixOS
VM check exercises two virtual KMS outputs, per-monitor scaling and window moves,
and leaving and returning to the session's VT. It also verifies user-bus access,
SSH agent inheritance, a standard graphical keyring unlock using a disposable
fixture, and cleanup of activation settings on logout. These checks do not establish
a successful physical DRM login or a booted system image on your hardware.

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

The socket has owner-only permissions. Status includes outputs, their scales,
positions, active workspaces, and each window's output, plus window geometry, workspace,
render density, and render/import counters. Commands also include `focus ID`,
`focus-next`, `focus-prev`, `move-next`, `move-prev`, `resize DELTA`, `workspace N`,
`move-workspace N`, `fullscreen`, `terminal`, `close`, `screenshot PNG`, and `quit`.
Use `output N` to focus a monitor (starting at 1), `focus-output-next` or
`focus-output-prev` to cycle, and `move-output-next` or `move-output-prev` to move
the focused window. `scale PERCENT` affects the focused monitor.
Test key and pointer commands are disabled in normal sessions.

`--socket-file PATH` writes the nested Wayland socket name for launching clients
with an explicit `WAYLAND_DISPLAY`. `-- COMMAND ARGS...` runs a custom application
instead of the default demos. Use separate-instance options for applications
that normally reuse a running process. Do not import a nested preview's display
into the global systemd or D-Bus environment.

In nested mode, `--screenshot PATH.png` saves the framebuffer after startup without changing the
clipboard. `--report PATH.json` writes final status when the session ends. Keep
these development artifacts under ignored `.local/`.
