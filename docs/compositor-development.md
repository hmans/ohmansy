# Shine

Shine is ohmansy's experimental scrolling Wayland compositor.

## Login session

The shared ohmansy desktop defaults to **Shine (experimental)** at login and
for live-image autologin. **ohmansy (Niri)** is also available in **Session**.
Installed systems need a rebuild to get the updated default; an existing boot
image stays unchanged.
Follow [the installed-system workflow](linux-development.md) and plan a reboot
for login-manager updates rather than restarting greetd from a running desktop.
Use `mise run os-boot` to build this checkout for the next boot, then reboot
when ready to try the updated login screen.

The experimental session opens your configured terminal and normal login shell,
or the apps in your [task workspaces](#task-workspaces) when configured.
**Super+Space** opens the application picker. **Super+Shift+E** opens a sign-out
confirmation; Cancel keeps the desktop running, while Sign out returns to the
login screen. Applications use their normal profiles in this session.

Shine handles DRM/KMS displays, seat access, input devices, and VT switching
directly through Smithay, libseat, and libinput. Cage is no longer part of the
session. Without saved settings, connected monitors on the primary GPU are placed
side by side in connector order, with preferred modes and a scale of 125%.
Each monitor has four independent scrolling workspaces by default, or your
configured task workspaces. Disconnecting a monitor
moves its windows to a remaining monitor. Shine's Quickshell shell draws the
shared animated ribbon wallpaper on each monitor, behind application windows.
The ribbon render target uses 75% of its capped resolution (up to 1800 pixels
wide), while the desktop animation remains about 15 frames per second.
The balanced default keeps two particle layers with full particle motion.
The background stays stationary while columns and workspaces change; Niri's
parallax is not yet connected to Shine. Saved wallpaper images are honored,
with a static fallback when ribbon rendering is unavailable. Foot's shared
defaults provide a translucent background; Shine does not yet blur it.
Niri's panel, wallpaper service, and other services remain tied to Niri.

Workspace buttons echo Shine's window frames: purple/slate translucent surfaces,
fine grain, a northwest bevel, and the same focus-tint fade. They read the current
frame colors, radii, lighting and animation settings from Shine. A small marker
also identifies the selected workspace. Labels follow light/dark appearance,
and clicking a workspace continues to preserve the app's keyboard focus.

This session is experimental: it has no screen locking, IME,
X11 support, or complete desktop portal integration. Keep Niri available as the
alternative desktop. Normal logins use the regular user D-Bus, so applications can
reach the login keyring. Once its Wayland socket is ready, Shine publishes the
display and desktop environment for D-Bus and systemd activation. It also
inherits the user's SSH agent, using the user manager's agent socket or GCR
when the login environment did not supply one. On logout, it clears its display
settings if they still belong to that session. When GNOME Keyring is enabled,
Shine completes the PAM-started daemon's initialization before starting desktop
applications, retaining the keyring unlock from password login.

Nested previews use a separate private bus and preserve the parent desktop's
activation environment. Keyring unlock dialogs can appear in a normal login;
autologin does not provide a password to unlock an encrypted keyring.

### Screen sharing

Shine exposes displays and individual windows through the standard
`ext-image-copy-capture-v1`, `ext-image-capture-source-v1` and
`ext-foreign-toplevel-list-v1` protocols, retaining `wlr-screencopy` for existing
display-capture clients. The `ohmansy-portals.conf` configuration selects wlr
for ScreenCast, GTK for file choosers and other general portals, and GNOME
Keyring for secrets when enabled. Niri keeps its own GNOME capture backend.
The system picker lists displays and windows according to the application's
request; Escape cancels without starting capture. Window capture renders only
the selected window, its subsurfaces and popups. It continues on hidden
workspaces, follows resize and monitor-scale changes, and ends when the app
closes. Transparent pixels composite against black, without revealing the
desktop or other windows. Region sharing and separate cursor-metadata streams
are unsupported. Capture uses shared memory, with hidden or embedded cursors
and a default limit of 30 FPS.

Rebuild the installed machine configuration with the updated sources, preserving
its hardware and account configuration. Then log out and back in: the running
compositor cannot gain a new Wayland protocol through a portal restart. The
session wrapper imports `DISPLAY`, `WAYLAND_DISPLAY`, `XDG_CURRENT_DESKTOP`,
`XDG_SESSION_DESKTOP` and `XDG_SESSION_TYPE` into D-Bus and systemd after its
Wayland socket is ready, then queues restarts of active portal services without
waiting for them. Waiting here would deadlock startup because portals need
Wayland replies from the compositor's event loop. No reboot
is needed for the screen-sharing change alone.

Shine sessions start their own `xwayland-satellite` for X11 applications such as
Steam. Shine selects an unused X display; satellite signals readiness while Shine
continues dispatching Wayland requests. Only then does Shine accept launch
requests, publish `DISPLAY` to D-Bus and systemd, and start the shell and apps.
Terminals and launcher apps inherit that display. Nested sessions own a separate
X server and activation bus, preserving the host environment. Sign-out stops the
bridge and its X server; compositor termination also ends the bridge. X11 TCP
listening is disabled. The packaged session includes satellite explicitly.

Use `python3 tools/tests/compositor_xwayland.py` inside `nix develop .#spatial`
to test X11 pixels, keyboard and pointer input, stale-display isolation and
shutdown on the private headless display. `compositor_session.py` also checks
the packaged terminal, launcher/GIO and D-Bus activation environments. A running
compositor needs a planned login restart after rebuilding to receive this code;
existing terminals retain the environment with which they were started.

For later portal-configuration-only changes, restarting
`xdg-desktop-portal-wlr.service`, `xdg-desktop-portal-gtk.service` and then
`xdg-desktop-portal.service` with `systemctl --user restart` is sufficient if
the compositor already supports capture and the session environment is current.
Restarting portals interrupts active portal requests and screen shares.

Verify the application-facing interface after login:

```sh
busctl --user get-property \
  org.freedesktop.portal.Desktop \
  /org/freedesktop/portal/desktop \
  org.freedesktop.portal.ScreenCast AvailableSourceTypes
```

The result should be `u 3` (monitors and windows). Then verify actual video
frames from a selected window in an application, resizing, closing the window,
repeated sharing and cancellation. The bitmask alone does not verify capture.
Application handling of a canceled request remains application work.

For the automated private-display trial, build the development compositor with
the normal compositor build task, then run:

```sh
nix build .#portal-test-tools --out-link .local/portal-test-tools
OHMANSY_PORTAL_TOOLS="$PWD/.local/portal-test-tools" \
  python3 tools/dev/compositor-test-display.py -- \
  .local/portal-test-tools/bin/python3 tools/tests/compositor_portals.py
```

This checks a real shared-memory output image, the public ScreenCast methods,
the retained file chooser, and a GStreamer consumer receiving actual PipeWire
frames. It verifies isolated window pixels, popups, resize, animation on a hidden
workspace, app closure, repeated sharing, display capture and cancellation.
Its private PipeWire server, WirePlumber policy (hardware monitors disabled) and
D-Bus session do not change the logged-in desktop's services or activation
environment. Test Chatto's own sharing flow after activating the installed
configuration; the private trial does not use the running Chatto instance.

To omit it from a host configuration:

```nix
ohmansy.compositor.enable = false;
```

Disabling Shine restores Niri as the default. To keep both sessions and default
to Niri, set this in the host configuration:

```nix
services.displayManager.defaultSession = "niri";
```

The session package also supports an explicit nested preview:

```sh
nix run .#compositor-session -- --nested
```

Choose **Displays** in Shine's bar to change a monitor's UI scale or refresh
rate at its current resolution. **Apply** previews the change for 15 seconds;
choose **Keep changes** to save it, or **Revert** to restore the previous settings.
Unconfirmed changes also revert when the preview worker loses its input or
times out. Shine saves kept choices in `~/.config/shine/config.toml`, alongside
its other settings, and reads them at login. Shine supports scales up to 200%.
Nested previews support scale changes; their resolution follows the host window.

The module honors `ohmansy.terminal`; the standalone flake preview uses Foot.
Close the preview's outer window or use its sign-out confirmation to end it.

## Notification clicks

Clicking a notification can focus its originating window, switching to
that window's monitor and workspace. The application must provide a notification
action and use the supplied Wayland activation token to select its window.
Notifications without an action, or applications that ignore activation tokens,
cannot identify a destination for Shine.
The pinned GLib 2.88 GNotification backend drops the notification activation token, so
applications using that path also need toolkit support before clicks can focus
their windows. Clients that handle the token directly can use it now.

Shine and Niri share the Quickshell notification service in
`nix/modules/notifications/`. It uses the shared UI components and a small native
Wayland helper to send an activation token before invoking a clicked action.
The compositor still validates the input serial; showing a notification grants
no focus permission.

Choose **Notifications** in the launcher, or Shine's bar, to open history and
Do Not Disturb. The last 100 non-transient messages and the quiet-mode preference
are saved privately under `$XDG_STATE_HOME/ohmansy/notifications.json` (default
`~/.local/state/ohmansy/notifications.json`). History contains text, not executable
actions. Explicit application timeouts are honored; zero stays until dismissed,
and an unspecified timeout defaults to eight seconds, or no timeout for urgent
messages. Hovering pauses expiry. Do Not Disturb suppresses popups while retaining
history. QML reloads retain active notifications; a process restart retains history.

Shine accepts activation only after recent input to the requesting client.
Tokens expire after ten seconds and can be used once. Background presentation
requests without that input do not gain permission to change focus.
Compositor changes require rebuilding and starting a new Shine session.

## Wallpaper fidelity

The wallpaper's render scale, particle layers and particle motion detail can
change live. Use `quickshell list` to find the desktop shell's PID, then:

```sh
quickshell ipc --pid SHELL_PID call wallpaper quality balanced
quickshell ipc --pid SHELL_PID call wallpaper status
```

| Preset | Render scale | Particle layers | Particle motion detail |
| --- | --- | --- | --- |
| `high` | 100% | 3 | Full |
| `balanced` (default) | 75% | 2 | Full |
| `low` | 50% | 1 | Simple |

The scale applies after the renderer's 2400-pixel width cap. All presets keep
the same ribbon shape, motion speed and roughly 15 FPS. Lower detail removes
the faintest particle layers first; simple particle motion skips the curl
calculation. Changes apply to every monitor in that shell and last until it
restarts. Niri exposes the same controls through its wallpaper process.

For custom settings, supply scale (0.25–1), layers (0–3), and particle motion
detail (0–1). Particle settings update shader uniforms; the shader stays loaded.
Motion detail scales curl strength; zero skips its four noise samples per
particle and retains the simpler drift.
Pause freezes the animation in place and resume continues it:

```sh
quickshell ipc --pid SHELL_PID call wallpaper configure 0.75 2 0.5
quickshell ipc --pid SHELL_PID call wallpaper pause true
quickshell ipc --pid SHELL_PID call wallpaper pause false
```

## Nested development demo

For an interactive development loop inside the current Wayland desktop:

```sh
mise run shine-dev
# Optional: --outputs 2 --scale 1.5, or --no-watch for one build.
```

The command prints the preview's shortcut prefix. It normally uses Super+Alt;
when the parent config maps left Option/Alt to AltGr, it selects Ctrl+Alt
(Control+Option on a Mac keyboard) so the outer desktop can forward the chord.
Use `--mod-key ctrl-alt` to select this explicitly, or `--mod-key super-alt`
to override detection. In Ctrl+Alt mode, add Shift to minus/equal for column
resizing; plain minus/equal still changes scale. The host keyboard layout stays
unchanged.

This command requires hardware rendering and prints the actual GPU and render
device. Software and unverified EGL devices are rejected. The `graphics` field
in IPC status reports vendor, renderer, GL version, device and acceleration.
Nested rendering shares the physical GPU with the main desktop; it does not
isolate driver faults. Investigate recurring desktop freezes before stress tests.

Rust saves build a replacement while the existing preview stays open. Successful
builds gracefully close only the preview and reopen its disposable applications.
Failed builds leave it running and retry after the next save. Closing the preview
or pressing Ctrl+C stops the development loop. It uses a private D-Bus session and
its own config/workspaces under `.local/shine-dev/`. Build/session logs and the
current preview's control socket information are saved there too. `preview.png`
captures the desktop after startup and is replaced after each Rust restart.

Fragment shaders and `rounded-coverage.glsl` reload on save without restarting
the preview. The explicit `OHMANSY_SHINE_SHADER_DIR` override loads checkout
sources; without it, packaged builds use embedded shaders. A successful shader
reload replaces decoration programs and caches together. Failed compilation or
missing files keep the working shaders and log an error. QML and TOML edits also
reload live. `mise run compositor-desktop` remains a single-run GPU-only demo.

It opens a nested desktop with a new terminal, Firefox, GNOME Text Editor, and
a Quickshell bar on each monitor. The bar has workspace buttons, a Terminal
button, and a clock. Buttons act on their own monitor. Windows leave room for
the bar; fullscreen covers it. The same bar starts in the packaged Shine session.
Its QML lives in `nix/modules/shine-shell/shell.qml` and reloads on save in the
development preview. Shared UI changes require rebuilt dependencies and a shell
replacement; Rust changes require rebuilding and restarting the disposable preview.
For styling in an installed session, use the
[runtime iteration workflow](linux-development.md#iterate-in-the-running-desktop)
to reload settings or replace only the shell while keeping applications open.

These are interactive applications on a private Wayland socket. Firefox uses a
fresh profile, and the editor uses separate application state under ignored
`.local/compositor-demo/`. Commands in the new terminal execute on this machine.
Closing the outer window ends the nested session and disconnects its clients.

The bar uses Shine's layer-shell support and private control socket, independent
of Niri's panel and services. Mod+Space or the ohmansy button opens the shared
Quickshell launcher, with fuzzy search across apps and desktop commands. Its
source is in `nix/modules/launcher/`, packaged as `Ohmansy.Launcher`. Providers
contribute stable IDs, titles, subtitles, icons, keywords and activation data;
the launcher owns search and selection, while each shell handles desktop commands.
External providers and nested views remain future work.

Shine honors exclusive keyboard focus for mapped top and overlay layer surfaces.
The launcher requests it only while open; closing restores the selected app's
keyboard focus. Background and panel commits preserve application popup grabs.
`python3 tools/tests/compositor_launcher.py` tests search, app and command
activation, errors, empty results, dismissal and focus on the private display.
This shell still has no tray or audio controls. The plain `compositor` demo
stays minimal; use `compositor-desktop` to preview the bar.

Windows form a horizontal strip with persistent widths. Focusing a window
scrolls it into view; adding another window keeps existing widths. There are
four workspaces, fullscreen, client maximize requests, and column resizing.
Click a window to focus it. **Mod** means **Super** in a login session and
**Super+Alt** in a nested demo or packaged `--nested` preview. The host matches
Super without Alt, so it forwards the child's Super+Alt shortcuts. Add Shift
for the actions below. `--mod-key super|super-alt|ctrl-alt` overrides the default.
The development watcher can choose Ctrl+Alt automatically for an AltGr host,
as described above; use its printed prefix in place of Mod.

When nesting under the supplied Niri configuration, use the arrow keys for
navigation: Niri reserves Super+Alt+L for screen locking.

| Shortcut | Action |
| --- | --- |
| Mod+H/L or Left/Right | Focus previous/next column |
| Mod+Tab | Focus the next column, wrapping from the last to the first |
| Mod+C / Mod+V | Copy / paste; terminal windows receive Ctrl+Shift+C/V |
| Mod+Shift+H/L or Left/Right | Move column left/right |
| Mod+comma/period | Focus previous/next monitor |
| Mod+Shift+comma/period | Move window to previous/next monitor |
| Mod+minus/plus (or equal) | Decrease/increase the focused monitor's scale by 5 percentage points (50–200%) |
| Mod+0 | Restore the focused monitor's scale to 100% |
| Mod+Ctrl+minus/equal (Ctrl+Alt preview: Mod+Shift+minus/equal) | Narrow/widen the focused column |
| Mod+R / Mod+Shift+R | Cycle column widths through 33⅓%, 50%, and 66⅔%, forward/backward |
| Mod+1–4 | Switch workspace |
| Mod+Up / Mod+Down | Cycle to the previous/next workspace, wrapping at either end |
| Mod+Shift+Up / Mod+Shift+Down | Move to the previous/next workspace and follow the window, wrapping at either end |
| Mod+Enter | Open a terminal |
| Mod+E | Open Files |
| Mod+Space | Open the application picker |
| Mod+Shift+Space | Toggle the focused window between floating and tiled |
| Mod+F | Toggle 100% working width, restoring the previous width |
| Mod+Shift+F | Toggle fullscreen |
| Mod+W | Close the focused window |
| Print / Ctrl+Print | Save the focused monitor and copy its PNG to the clipboard |
| Mod+Shift+4 | Capture the focused monitor (Mac keyboard screenshot key) |
| Shift+Print | Capture the focused monitor and open Satty for annotation |

Ctrl+Alt+function keys are reserved for switching Linux virtual terminals.

Selecting an app in the launcher first looks for an existing mapped window using
the desktop ID or `StartupWMClass`. Shine brings it into view on its monitor and
workspace; otherwise GIO starts the app normally. New windows receive focus when
their first buffer maps, after workspace placement. Closing a window focuses its
left neighbor, with a right-neighbor fallback for the first column. Closing a
floating dialog returns focus to its parent when available.

Transient dialogs and fixed-size windows float at a bounded size inside the
monitor's work area. Dialogs start centered over their parent, stay above tiled
windows, and accompany their parent on workspace and monitor moves. Client
move/resize requests operate on floating geometry; tiled movement keeps its
column behavior. Menus and tooltips continue using xdg popups and popup grabs.
`Mod+Shift+Space` also floats or tiles an ordinary window. Both window types use
a frame whose color changes with focus; `decorations.frame.active_color` and
`inactive_color` configure its colors.

Copy and paste use Ctrl+C/V in ordinary apps and Ctrl+Shift+C/V in recognized
terminals. Ctrl+C still interrupts terminal programs. Terminal copy uses the
terminal's selection, including when a text editor runs inside it.

Customize these shortcuts in `~/.config/shine/config.toml`; changes reload live
after installing a compositor build that supports them. For example:

```toml
[bindings]
"Mod+C" = { action = "none" } # Remove the default copy shortcut.
"Mod+Insert" = { action = "copy" }
"Mod+V" = { action = "paste" }

[clipboard]
copy = "Ctrl+C"
paste = "Ctrl+V"
terminal_copy = "Ctrl+Shift+C"
terminal_paste = "Ctrl+Shift+V"
```

The optional `clipboard.terminal_app_ids` list replaces the built-in terminal
IDs with exact, case-sensitive app IDs. Include all terminals you use when
overriding it; `[]` sends ordinary app shortcuts everywhere. Window app IDs
are visible in IPC `status`. The complete default list is in
[`config.example.toml`](../nix/compositor/config.example.toml).
Target shortcuts use explicit modifiers such as Ctrl and Shift; `Mod` is only
for the incoming binding. Applications with other clipboard conventions need
their own settings. These defaults apply to Shine sessions.

Moving a window between workspaces keeps you on the current workspace. These
moves stay on the current monitor and wrap between workspaces 1 and 4.

Width presets use the focused monitor's working width minus the outer gaps.
From a custom width, forward selects the next larger preset and reverse selects
the next smaller one; both wrap. Client minimum/maximum widths and the 200 px
column minimum still apply, with duplicate constrained presets skipped.

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

The compositor requests a render density matching each surface's monitor.
The existing 5-percentage-point scale controls change both desktop size and
the preferred app density, including when a window moves between monitors.
Popups and subsurfaces inherit their owner's scale, panels use their assigned
monitor, and cursor surfaces follow the pointer. Clients without fractional
scaling receive the monitor scale rounded up to the next integer.
Wayland clients choose their buffers: a modern client can use `buffer_scale=1`
and a viewporter destination for fractional rendering. Inspect `render_density`,
rather than just `buffer_scale`, in the status report. It accounts for the
sampled source crop, so padded buffer allocations do not inflate the result.

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
on one primary GPU, with preferred or explicitly selected modes. Rotation
and multi-GPU rendering are not implemented.
Clipboard exchange is local to
its clients. X11 clients and
moving existing Niri windows into it are unsupported. Its 3D presentation remains
in the separate snapshot experiment.

## Screenshots

**Print**, **Ctrl+Print**, or **Cmd/Super+Shift+4** captures the focused monitor
without the mouse cursor. The last shortcut also supports the Keychron Mac-mode
screenshot key. In nested previews it follows Mod: **Super+Alt+Shift+4**.
The PNG includes its windows, application popups, panel and compositor decorations,
and excludes Shine's screenshot feedback popup. Shine
saves it under `Screenshots` in your configured Pictures directory and copies
the same image to the clipboard. A popup briefly shows the saved path and
whether copying succeeded, including in fullscreen. It keeps keyboard focus
in your application. Screenshots have unique timestamped names and never
replace an existing file. A completed temporary file is published atomically;
an interrupted write never appears as a partial destination PNG.
PNG encoding, saving and clipboard transfer run off
the compositor thread.
Clipboard helpers use the data-control protocol, so copying does not require
opening a temporary window or changing keyboard focus.

**Shift+Print** also opens the saved image in Satty, which is included for
annotation. Satty's own save and copy actions apply your edits; the initial
clipboard image is the unedited screenshot. Shine launches Satty with
`--copy-command 'wl-copy --type image/png'` so the edited image stays available
for paste after Satty closes. Region and window selection are
not yet available in Shine. Niri retains its built-in selection workflow.

The parent desktop may intercept Print in a nested preview. Use the private
control socket or configure another binding for that preview:

```toml
[bindings]
"Mod+P" = { action = "screenshot" }
"Mod+Shift+P" = { action = "screenshot", annotate = true }
```

Capture through the CLI with either backend:

```sh
.build/spatial/debug/ohmansy-compositor msg --socket .local/compositor-control.sock screenshot-screen
.build/spatial/debug/ohmansy-compositor msg --socket .local/compositor-control.sock screenshot-screen /tmp/shine.png --annotate
```

The command queues a capture; poll `status` for its `screenshot` result, including
the completion `id`, originating `output`, saved path, pixel dimensions, and any
save, clipboard or annotation error. Each accepted request gets a new ID,
including repeated failures. Clipboard helpers have a five-second deadline and
read the completed file directly, avoiding blocking pipe writes.
The older `screenshot PNG` command remains a nested-only diagnostic capture of
the whole preview canvas. Neither command supplies a public Wayland capture
protocol or desktop portal; external capture apps still need those interfaces.

Run `python3 tools/tests/compositor_screenshots.py` inside `nix develop .#spatial`
after building the development binary. Build
`.#checks.x86_64-linux.compositor-screenshots` for a focused native VM check
of two monitors, mixed scaling, mode changes, Print, fullscreen and PNG clipboard
contents. It checks visible feedback pixels against a clean capture and exports
the captured PNGs under `screenshots/` in its result. The nested trial also checks
popup dismissal and expiry, repeated failures, and recovery from a stuck
clipboard helper. Pillow is included in the development shell for pixel checks.
Run `python3 tools/tests/compositor_satty.py` in the same shell for the focused
annotation regression: Copy closes Satty, then a separate client reads and
decodes the PNG from the clipboard after the editor has exited.

## Configuration

Shine keeps compositor settings in `~/.config/shine/config.toml`, honoring
`XDG_CONFIG_HOME`; `--config PATH` selects another file for development.
Task workspaces and startup apps live separately in
`~/.config/shine/workspaces.toml`; see [task workspaces](#task-workspaces).
Every section is optional. See the complete
[example configuration](../nix/compositor/config.example.toml) for outputs,
input, layout, window decorations, bindings, application rules and animations.

Edits reload live. Unknown fields/actions, invalid widths or shortcuts, and
keyboard layouts that fail to compile keep the working configuration. Inspect
`config_error` and `preferences` in status for errors and effective preferences.
Automatic reload failures and successful reload revisions are also written to
the session log (`journalctl -b -t ohmansy-session` in a login session).
Check a file without starting a compositor:

```sh
ohmansy-compositor validate ~/.config/shine/config.toml
```

Validation checks syntax, preferences, keymaps and shortcut profiles. Supported
display modes and monitor geometry are checked against connected outputs when
the configuration is applied.

### Favorite browser

Press **Mod+Shift+Enter** (Command+Shift+Enter on a Mac keyboard) to focus an
existing browser window, including on another workspace or monitor, or launch
the browser if none matches. Configure it in `~/.config/shine/config.toml`:

```toml
[browser]
program = "firefox"
args = []
app_ids = ["firefox", "org.mozilla.firefox"]
```

These are the defaults. For Chromium, for example, set `program = "chromium"`
and `app_ids = ["chromium"]`. Use the window's `app_id` from IPC status if its
name differs. Matching ignores case and a trailing `.desktop`; an empty list
always launches the command. Arguments are passed directly without a shell,
so Flatpak browsers can use `program = "flatpak"` and
`args = ["run", "org.mozilla.firefox"]`. Edits reload live once the updated
compositor is installed. The shortcut can be overridden with
`"Mod+Shift+Return" = { action = "browser" }` in `[bindings]`, or disabled with
`action = "none"`.

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
column widths. Animations control scrolling and same-workspace column reordering;
`duration_ms` is 0–5000, with 180 ms as the default. Shift+Mod+Left/Right (or H/L)
slides both swapped columns using cubic easing. Repeated moves start from their
current visible positions, and any accompanying viewport scroll uses the same
timing. Keyboard focus stays with the moved window; its frame, menus, and pointer
input follow the visible position. Disabling animations or choosing zero snaps
to the destination. Width changes, workspace transfers, and monitor transfers
remain immediate. Resize, fullscreen, layout changes, and window removal finish
pending reorder animations.

### Window frames and shadows

Every window has a 7 px frosted glass frame, with a 30 px top edge for an 18 px
app icon and an ellipsized window title. Focused frames use a muted purple tint;
unfocused frames use a dark slate tint. Click the frame to focus a window.
Drag its top edge to move a
floating window or reorder a tiled column. The frame reserves space in the
layout and never covers application content. Fullscreen windows omit the frame
and shadow. Clients supporting server decorations omit their own titlebar;
apps with integrated headerbars can keep them inside the frame.

```toml
[decorations]
corner_radius = 14

[decorations.frame]
enabled = true
width = 7
titlebar_height = 30
title_font_size = 13.0
icon_width = 18
icon_height = 18
title_padding = 11
icon_title_gap = 7
outer_corner_radius = 10
inner_corner_radius = 8
focus_duration_ms = 150
focus_easing = "ease-in-out"
active_color = [0.317647, 0.250980, 0.372549, 0.55]
inactive_color = [0.145098, 0.156863, 0.207843, 0.40]

[decorations.frame.glass]
enabled = true
blur_radius = 12
opacity = 0.9
noise = 0.025

[decorations.shadow]
enabled = true
softness = 12
spread = 2
offset = [0, 6]
color = [0.0, 0.0, 0.0, 0.35]
```

All dimensions, including font size, use logical pixels. Frame width accepts
1–16, top height 20–64, title font size 4–64, icon width/height 1–128, and
padding, gap and both radii 0–128. Font size can be fractional. Icon dimensions
are independent; the icon and title are centered vertically in the top edge.
Oversized captions are clipped to the frame and long titles are ellipsized.
The outer radius controls the frame silhouette and shadow; the inner radius
controls the client cutout independently. Both rendering and pointer hit areas
follow these shapes. `decorations.corner_radius` applies when frames are disabled.
Colors are RGBA values from 0 to 1; alpha controls tint strength in glass mode. Settings reload live on a
compositor built with frame support. Rendering code changes need a new preview
process; they cannot update the compositor in an existing login session.
Desktop-entry icons support PNG and SVG, with a window glyph as fallback.
Title text uses Inter with font fallback for other scripts. Titles and icons
are cached until the title, app, caption measurements or render density changes.

Focus tint fades between the active and inactive RGBA colors over 150 ms,
independently of inactive-window scaling and grading. Rapid focus changes reverse
from the currently visible tint. `focus_duration_ms` accepts 0–5000; zero makes
the change immediate. `focus_easing` accepts `linear`, `ease-in`, `ease-out` or
`ease-in-out`. Disabling global animations also makes tint changes immediate.
The fade stops scheduling repaints at its exact endpoint. Tint-only changes
reuse the existing backdrop texture; lower scene changes still refresh it.

Glass samples the actual scene behind each window, excluding that window's
own contents, caption and shadow. Blur runs on the GPU; there is no CPU pixel
readback. `blur_radius` accepts 0–64 logical pixels, `opacity` and `noise` accept
0–1. The default fine grain stays fixed to the frame instead of shimmering.
Set `glass.enabled = false` for a plain color frame. Backdrop snapshots are
cached until lower surfaces, their geometry or frame settings change. A changing
wallpaper updates the blur too. Individual-window sharing excludes frames.
`python3 tools/tests/compositor_glass.py` checks real blur, transparency, grain,
background updates and scaling on the private test display.

### Frame bevels and inset shadows

A thin bevel makes frames look raised: the outer top and left edges catch a
northwest light, while the bottom and right edges are shaded. The inner bevel
reverses that lighting around the client cutout. Rounded corners use continuous
surface normals. Both plain and glass frames use the same lighting.

```toml
[decorations.frame.bevel]
enabled = true
width = 1.5
inner_width = 1.0
highlight = 0.20
shadow = 0.18
light_direction = [-1.0, -1.0]

[decorations.frame.inset_shadow]
enabled = false
width = 8.0
softness = 8.0
offset = [2.0, 2.0]
color = [0.0, 0.0, 0.0, 0.22]
```

Widths use logical pixels and accept fractions. Bevel widths accept 0–16;
highlight and shadow strengths accept 0–1. Zero width disables that bevel.
`light_direction` points toward the light in screen coordinates: negative X is
left, negative Y is up. Components accept −1 to 1; the vector must be nonzero
and is normalized automatically. `[1.0, 1.0]` moves the light to the southeast.

The optional inset shadow is cast inward **over app content**, making the app
look recessed beneath its frame. Shine draws a separate translucent overlay
above the client surface tree and below menus, tooltips and the frame caption.
The app's own buffer and input regions stay unchanged. The rounded client and
outer frame masks clip the shadow; fullscreen and frameless windows omit it.
Individual-window sharing continues to capture client surfaces without desktop
decorations, while display sharing includes the shadow.

Width and softness accept 0–64 logical pixels, offsets accept −64–64, and color
is RGBA from 0–1. Positive offsets cast farther down/right, emphasizing top/left
app edges. Width zero disables the shadow. Settings reload live on a compositor
built with this overlay; older builds drew it on the frame itself. This code
change needs a new preview or login session. It adds no idle animation or
offscreen capture pass and does not darken workspace-button contents.
`python3 tools/tests/compositor_bevel.py` checks actual pixels for both frame
types, light reversal, curved corners, clipping, live settings and scale.

Drop shadows follow each window's rounded outer frame. Their interiors are cut
out so translucent windows keep their original background opacity. `enabled =
false` disables shadows. `softness` controls falloff (1–64), `spread` expands the
shape (0–64), and `offset` sets displacement (−128–128 each). Menus and tooltips
remain free to extend beyond the window. Transparent corners do not receive
pointer input. Individual-window sharing includes only client surfaces.

The former halo and focus ring have been removed. Old halo and ring settings
are accepted for configuration compatibility and have no visual effect.
`python3 tools/tests/compositor_frames.py` exercises the frame privately.
IPC `geometry` and `target_geometry` describe the outer layout slot;
`content_geometry` and `content_target_geometry` describe its client area.

### Unfocused window appearance

Unfocused windows recede slightly: 99% visual scale, 85% saturation and an
8% neutral fog, with a reversible 160 ms cubic ease-out focus transition. This
preserves app opacity, client sizes and column spacing. The selected app stays emphasized
while the launcher or another desktop overlay has keyboard focus. Windows on
other monitors also recede; fullscreen windows keep their normal appearance.

```toml
[decorations.inactive]
enabled = true
scale = 0.99
saturation = 0.85
fog = 0.08
fog_color = [0.5, 0.5, 0.55]
duration_ms = 160
easing = "ease-out"
```

Edit this section in `~/.config/shine/config.toml`; these settings reload live.
Set `enabled = false` to disable the effect, or
`scale = 1.0` for color muting alone. Numeric values are clamped when loaded:
scale to 0.8–1, saturation and fog to 0–1, and duration to 0–5000 ms.
Fog color is RGB, with each channel clamped to 0–1. A `nan` value uses that
setting's default. Clamping leaves your file unchanged; IPC `preferences` shows
the effective values. These adjustments allow the rest of an edit to apply.
Choose a lighter or darker neutral fog color to suit your wallpaper and appearance.
Disabling animations also makes focus transitions immediate.
`easing` accepts `linear`, `ease-in`, `ease-out` (default), or `ease-in-out`.
The eased curves are cubic and apply when both focusing and unfocusing a window.
Changing the curve during a transition continues from its current visible value.

Windows, menus, corners, rings and shadows share the visual transform. Pointer
coordinates follow the displayed surfaces, including during a click drag.
Whole-display captures include the desktop effect; individual-window sharing
captures the app at its normal size and colors. Window status reports
`inactive_amount` and `visual_scale` for diagnostics; `geometry` still describes
the layout slot. Run `python3 tools/tests/compositor_inactive.py` for the private
pixel, input, transition and live-reload trial.

### Bindings and window rules

```toml
[bindings]
"Mod+Return" = { action = "terminal" }
"Mod+Space" = { action = "launcher" }
"Mod+R" = { action = "cycle-width" }
"Mod+Shift+R" = { action = "cycle-width", reverse = true }
"Mod+N" = { action = "launch", program = "foot", args = [] }
"Mod+1" = { action = "workspace", value = 1 }
"Mod+Shift+Right" = { action = "move-next" }
"Mod+W" = { action = "none" }

[[window_rules]]
match = { app_id = "firefox" }
default_column_width = { proportion = 0.75 }
```

Custom bindings replace the matching default; omitted bindings keep defaults.
`none` removes a binding and lets the client receive the chord. `Mod` is Super
in a login and Super+Alt in a nested preview. Explicit Super, Alt, Ctrl/Control
and Shift modifiers are also supported, with exact modifier matching. AltGr
(or Level3) and Level5 are distinct modifiers: they do not match plain Super
shortcuts. Keys use
XKB names such as Return, Left, comma, space or F6. Ctrl+Alt+F1–F12 remain reserved
for VT switching. Key releases stay paired with intercepted presses across reloads.

Actions include terminal, launcher, logout, close, maximize, fullscreen, toggle-floating, focus-prev/next,
move-prev/next, focus-output-prev/next, move-output-prev/next, resize, cycle-width, workspace,
workspace-prev/next, move-workspace, move-workspace-prev/next, task, output, scale, scale-adjust, launch, reload-config and save-config. Resize
uses `value` in logical pixels; workspace/move-workspace use 1-based indexes, output is
1-based, scale uses a percentage, and scale-adjust uses a signed percentage point
delta (for example, `{ action = "scale-adjust", value = 5 }`). Launch executes the program and argument
array directly. The configured terminal action still honors the OS launcher.
Cycle-width accepts optional `reverse = true`; its IPC direction is 1 (forward,
the default) or -1 (reverse).

Window rules match an exact, case-sensitive `app_id` from status. The last
matching rule supplies the default width when a new window identifies itself.
Existing windows retain their widths when rules or defaults reload, including
manual resizes; client minimum/maximum constraints still apply.

## Task workspaces

Define task workspaces in `~/.config/shine/workspaces.toml`. The bar shows their
names in configuration order. Each monitor has the same task list and its own
windows. Startup apps open once, on the primary monitor, after the desktop
environment is ready. A nonempty task list replaces the default startup terminal.
With no tasks configured, the existing four-workspace desktop stays available.
This feature is specific to Shine; it does not configure Niri.

The workspace file loads and reloads independently of `config.toml`. Invalid
workspace definitions keep the last working task list without blocking display,
keyboard or other compositor changes. IPC exposes `task_config_path`,
`task_config_error` and `task_config_revision` separately from compositor errors.
Saving display settings never writes the workspace file. A missing or empty
workspace file returns to the default four workspaces while preserving windows.

By default, Shine reads `workspaces.toml` beside the selected compositor config,
including when `--config PATH` is used for development. `--workspaces PATH`
selects a different workspace file explicitly.

```toml
[[workspaces]]
id = "dev"
name = "dev"

[[workspaces.apps]]
command = ["foot", "--app-id=dev-terminal"]
match = { app_id = "dev-terminal" }

[[workspaces]]
id = "chat"
name = "chat"
```

See [the dev/chat example](../nix/compositor/tasks.example.toml) for terminal,
Chrome, Paseo, Chatto HQ, Bluesky, and WhatsApp. Install the apps separately and
adjust commands to your system. For an existing desktop launcher, a command can
use `gio launch /absolute/path/to/app.desktop`, with each argument as a separate
array entry. Commands run without a shell: `~`, `$HOME`, pipes and redirection
are not expanded. Use absolute paths for personal scripts and files.

Every app needs an exact Wayland `app_id` match. Add `title_contains` when an
app ID alone is ambiguous. Inspect IDs and titles with
`ohmansy-compositor msg --socket "$OHMANSY_COMPOSITOR_CONTROL" status`.
Chrome app windows normally have IDs derived from their URL and profile;
the example uses the Default profile. Custom terminal app IDs are useful for
distinguishing terminals belonging to different tasks.

Placement happens once, at the first window buffer commit, using the metadata
available then. The first matching task wins. Later title changes and manual
window moves do not trigger placement again. Apps that expose their final title
only later need an app ID match instead. New windows receive focus after task
placement, revealing their workspace. Startup app failures do not block other apps; immediate
launch errors appear in the session log and IPC `task_startup_errors`.
This is startup launching, not process supervision or session restoration.

Config edits reload without launching apps again. Stable IDs preserve task
contents and the active task through renaming and reordering. Removing a task
moves its windows to the remaining active task. Empty tasks are allowed.
Invalid workspace configuration keeps the working task list and reports
`task_config_error`.
Restarting only the shell also does not relaunch apps.

Optional shortcuts target stable IDs, independent of names and order. Keep
shortcuts in the existing `[bindings]` table in `~/.config/shine/config.toml`:

```toml
[bindings]
"Mod+D" = { action = "task", id = "dev" }
"Mod+G" = { action = "task", id = "chat" }
```

Bindings override existing shortcuts when the same chord is already assigned.
Task IDs are resolved when invoked, so a missing task does not invalidate the
compositor configuration.
IPC also accepts `msg --socket PATH task dev`. Previous/next workspace controls
cycle through the configured task count; numeric IPC indexes remain 1-based.

Validate without launching anything:

```sh
ohmansy-compositor validate-workspaces ~/.config/shine/workspaces.toml
```

Use a Shine build with task support to load the workspace file. Keep workspace
tables out of `config.toml`. A nested session launches real apps using your regular profiles;
use the private headless test for automated verification:

```sh
mise run compositor -- --help
python3 tools/tests/compositor_tasks.py
```

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

For a freeze in an existing session, `tools/dev/shine-hang-watch.py` can observe
the verified compositor PID and control socket without restarting it:

```sh
python3 tools/dev/shine-hang-watch.py --pid PID --socket PATH \
  --directory .local/shine-hang-watch
```

It checks status every five seconds. After two consecutive failures, it saves
two thread wait-state snapshots and recent session/kernel logs, then exits.
It never sends input, changes settings or restarts processes. Diagnostics stay
in the ignored directory. Kernel stacks and syscalls may be denied by ptrace
permissions; the report records those limits. This gathers evidence, not a fix.
The observer exits when its original process exits; start it again after login.

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
Packaged builds use Crane to cache compiled Rust dependencies separately from
Shine's source. The first build fills this cache; later source edits reuse it,
including through `mise run os-switch`. Dependency, compiler, or native library
changes can rebuild the cache. This uses the Nix store, not `.build/spatial/`.
Both Rust experiments share the incremental cache in `.build/spatial/`.
Restart the nested process to try code changes; no OS rebuild is needed.

`mise run shine-check` checks new Git inputs, Rust formatting/tests/Clippy,
the preview lifecycle, the shipped Nix package, and selected private GPU trials.
Use `mise run shine-check -- --no-graphics` for package and non-graphical checks
while diagnosing GPU instability. Neither command activates the installed OS;
use the installed-system workflow for that separate verification step.

```sh
mise run compositor-check
mise run compositor-integration
python3 tools/tests/compositor_nesting.py
python3 tools/tests/compositor_monitors.py
python3 tools/tests/compositor_notifications.py
python3 tools/tests/compositor_preferences.py
python3 tools/tests/compositor_clipboard.py
python3 tools/tests/compositor_clipboard.py super
python3 tools/tests/compositor_movement.py
python3 tools/tests/compositor_shadows.py
nix build .#checks.x86_64-linux.compositor-drm
mise run compositor -- --scale 1.5 --close-after 10
```

The integration task creates disposable Firefox, GTK editor, and terminal clients
and checks rendering, input, scrolling, menus, clipboard, workspaces, and idle
frames. Automated compositor tests run on a private headless Wayland display by
default, including direct Python invocations above. No test windows appear on
your desktop. The runner starts Weston with its headless GL backend, an isolated
Shine parent, and a private D-Bus session with temporary runtime and configuration
directories. GPU rendering remains enabled. It needs no logged-in desktop and
never falls back to a visible display if setup fails.

Run an individual test through the runner, or opt into visible windows when
you specifically want to watch it:

```sh
mise run compositor-test -- tools/tests/compositor_clipboard.py
python3 tools/dev/compositor-test-display.py --visible -- python3 tools/tests/compositor_clipboard.py
```

The development shell supplies Weston and D-Bus; direct tests enter that shell
automatically. Build the development compositor first with
`mise run compositor-integration` if no binary exists. Interactive commands such
as `mise run compositor-desktop` still open a visible preview.

Headless display and activation-bus logs are saved in
`.local/compositor-tests/headless-*/`; each trial keeps its usual screenshots
and reports. Shared IPC, display guards, and input helpers live in
`tools/tests/compositor_support.py`. Use `control.send_keys(...)` to make the
destination compositor explicit. The runner registers each process group for
cleanup as it starts, including descendants that outlive the group leader.
Test input goes through a private
control socket into the normal compositor handlers; `--test-input` enables this
path and ignores physical input from the parent window during the trial.
Artifacts stay in ignored `.local/compositor-tests/`.

The shell trial checks two-monitor ribbon animation, wallpaper image overrides,
the software-rendered fallback, foot transparency, panel actions, scale changes,
and clean shell shutdown. Screenshot trials use a static wallpaper so pixel
comparisons and idle checks remain independent of the animation.

The movement trial checks intermediate window/ring pixels, visible-position
pointer input, interrupted swaps, coordinated scrolling, unchanged client sizes,
animation disabling and cleanup. Window status exposes visual `geometry`, final
`target_geometry`, and `moving` so these transitions can be inspected over IPC.
The nesting trial checks real Wayland key forwarding between a Super host and
a Super+Alt child, including focus changes and independent scale shortcuts.
The clipboard trial checks Foot and Qt copy/paste, preserved Ctrl+C, live
incoming and outgoing shortcut overrides, invalid-config recovery, and releases
across a binding reload. Both modifier profiles have a trial invocation above.

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
`focus-next`, `focus-next-wrap`, `focus-prev`, `move-next`, `move-prev`, `resize DELTA`, `cycle-width [1|-1]`, `workspace N`,
`workspace-prev`, `workspace-next`, `move-workspace N`, `maximize`, `fullscreen`, `terminal`, `close`, `screenshot PNG`, and `quit`.
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
