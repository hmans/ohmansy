---
data:
  area: tooling
  kind: workflow
  reviewed: "2026-11-05"
  status: current
id: b4jpz
title: Host tooling and publication workflow
---
# Host development, build, and release tools

Read [root instructions](../AGENTS.md). Run commands from the
repository root unless the tool explicitly supports another working directory.

## Boundaries

- dev/ manages SSH source snapshots and isolated image tests. It must not send
  the host home directory, personal reference flake, keys, or local VM state.
- build/ assembles and signs the Mac bundle. Keep the engine checksum pin and
  stable signing identity. Never modify the installed source runtime app.
- release/ packages images, source archives, manifests, and checksums. Source
  must match the image build. Keep outputs outside Git and refuse accidental
  replacement of release artifacts.
- Runtime code belongs in app/runtime/. Avoid dependencies from shipped code
  on these host-only tools. Update callers, CLI examples, and tests after moves.

## Guest work

For installer UI iteration, use `tools/dev/installer-ui.sh` (also a mise task
and T3 action). It runs the mock preview from working-tree QML, allowing live
reload without rebuilding the ISO. Nix Portable on this host could not create
an OpenGL context, so that launcher branch defaults to software rendering.
The packaged preview still uses immutable QML unless its source override is set.

`tools/dev/installer-vm.sh` provides repeatable ISO and disk launches for IDE
actions, also exposed through mise. It delegates to `linux-iso-vm.py` and uses
rescue media when the state directory exists, preserving the virtual disk.
See the Linux guide for defaults and overrides. `t3.json` declares the two
actions for T3 Code; the wrapper and mise tasks are also versioned. An API
response containing project scripts does not establish visibility in the UI.

`mise run installer-vm` depends on `installer-iso`. Mise sources/outputs freshness
checks cover the flake, lock, all of nix/, and tools/build/installer-iso.sh; the
output is a real host-readable dist/installer/ohmansy-installer.iso, not a Nix
store symlink with epoch timestamps. The builder supports native and portable
Nix, retains a store output link, and atomically replaces the copied ISO so
running VMs retain their open file. The direct shell launcher does not build.

For an agent already inside Linux, use local command tools and the native
[Linux development workflow](../docs/linux-development.md). The Mac bridge is
not needed. Keep live USB work on persistent storage. Mac bundle commands remain
macOS-only; use native Nix checks and Python tests for the desktop.

Installed OS iteration (2026-11-04): `mise run os-build`, `os-test`, `os-boot`, and
`os-switch` call `tools/dev/os-rebuild.sh`. The helper rebuilds the installed
`/etc/nixos#ohmansy` configuration with a `git+file://` override of its `ohmansy`
input and `--no-write-lock-file`. `OHMANSY_SYSTEM_FLAKE` selects a custom machine
configuration. It preserves the installed release pin; boot selects the checkout
build for the next boot without activating running services, while switch also
activates immediately. `--dry-run` prints the command without sudo or
Nix. Bash syntax, TOML parsing, and command execution with mocked sudo passed
for all actions, custom paths with spaces, invocation outside the checkout,
invalid arguments, dry runs, and child failure propagation. No OS build or
activation was performed. Later verified `mise run os-test -- --dry-run` with
the pinned Nix-packaged mise; argument forwarding printed the expected command
without invoking sudo. Direct Bash invocation is also supported. The boot action's real mise dry run
and mocked execution passed, including custom paths with spaces, invocation
outside the checkout, and rebuild failure propagation. No boot generation was
built or selected during these command-routing checks.
Shared changes belong in the repo's reusable modules, packages, and defaults;
the installed machine is their test target. Root AGENTS.md records this rule
for every session. A runtime fix or machine-only configuration edit does not
ship in ohmansy unless the shared implementation is also changed.

From another machine, use SSH with an explicit target, identity, port, and verified host key. Read
ignored local session notes if present; confirm the endpoint and running system.
The guest-dev defaults may describe an older builder. Never disable host-key
checking to get around a mismatch or assume the old personal VM still exists.

Sync into a new snapshot. Preserve installed owner, storage, and development
overlays when building an installed host. Factory/live targets are image outputs,
not replacements for the current guest configuration. Private development guests
opt in with the shipped `ohmansy-dev enable --public-key ...` command. The host's
`guest-dev.py bridge --state .local/VM --port PORT --public-key KEY.pub` updates
QMP, persists only the loopback port in local development.json, and prints the
guest command. `unbridge` removes the forward; guest `disable` removes managed
access. Older app bundles do not read that state setting. The manual
prepare-access generator remains available for custom flakes. The first activation
needs the owner's password in their own terminal. Never use terminal UI automation.

Image profiles import `nix/modules/image-policy.nix` and reject development markers,
SSH access or keys, extra owner accounts, and custom sudo rules during system
build evaluation. The standard live-console wheel rule is allowed. Source archives
exclude `tools/dev/` and `.local/`. Flake checks exercise rejected configurations;
Python tests cover generation and archive exclusion. These checks do not certify
arbitrary input disks passed to the packaging tools.

QMP is the lifecycle/control channel. Use an explicit state directory. The
gpu-probe `shutdown` action requests a clean shutdown; `stop` sends QEMU `quit`
and is a power cut if the guest is running. Confirm shutdown before quitting the
engine or deleting state. Never treat a PID file as proof of process identity.

## Validation and publication

Run Python tests with `python3 -m unittest discover -s tools/tests -p 'test_*.py'`.
Use make test when runtime behavior is affected. Check changed CLI entry points
with --help and test actual packaging when paths or bundle layout change.

Check host and guest disk headroom before image builds. Prefer the ARM CI runner
for full image assembly on a resource-constrained Mac. Do not overwrite or delete
a VM to make space. Use a disposable disk for installer tests.

This repository is public. Before an authorized push, inspect the exact changed
files for secrets and generated artifacts. Scan reachable history before first
publication or a history rewrite. Use redacted secret-scanner output and keep
reports under .local/. Do not push unless the current task authorizes it.

## Shine login session

Shine naming (2026-11-04): the experimental window manager/compositor is
named **Shine**. The login label is **Shine (experimental)**; compositor window
titles, demo content, CLI heading, package descriptions, and user guides use
Shine. The distribution remains ohmansy. Existing command names, package paths,
and session identifiers are retained for configuration compatibility.

The scrolling compositor is shipped from `nix/compositor/` through
`nix/modules/compositor-package.nix`. Keeping its Cargo sources under `nix/`
also includes them in the offline release source and source archives. Rust
dependencies have a fixed Cargo hash; runtime assets use a store path rather
than Cargo's temporary build directory.

`mise run compositor-session` previews the packaged nested session. Normal logins
now run Shine's DRM backend directly; Cage has been removed from the wrapper.
The installed module uses the configured terminal launcher and normal shell,
a normal-window Wofi app picker (Super+D), and confirmed sign-out
(Super+Shift+E). Confirmation disables Wofi config/history so Cancel remains
the default. Nested previews publish their Wayland socket only into a dedicated private
D-Bus session. Normal logins use the regular user bus and import their display
and SSH agent into D-Bus/systemd activation after the socket exists. Logout
clears display settings only if the user manager still points at that session.

Earlier Cage nested/headless trials passed normal terminal startup at
2x, app picking, canceled/confirmed logout, and preservation of parent windows
and activation variables. Native Firefox/GTK integration passed after promotion.
The initial development checks did not verify physical DRM login; see the
multi-monitor update below for subsequent user confirmation. See the
[session guide](../docs/compositor-development.md).

Shortcut profiles (2026-11-04): login sessions use Super and nested runs use
Super+Alt; `--mod-key super|super-alt` explicitly selects either. The session
wrapper passes Super normally and Super+Alt for `--nested`. Host matching
requires Alt to be absent, so child chords are forwarded. Eight Rust tests and
strict Clippy passed; a real two-compositor Wayland trial verified independent
terminal/scale actions, focus recovery, and original desktop preservation.
The browser/GTK native trial also passed using Super+Alt. Winit focus loss
releases the inner pressed keys because Smithay filters synthetic releases;
without this, switching to a host terminal left Super stuck in the child.
Trials now support an ohmansy host via its control socket as well as Niri.
Under the shipped Niri bindings, Super+Alt+L is reserved for locking; use the
arrow navigation alternatives. Existing installed processes keep their old
bindings until restarted with the updated build.

## Spatial window lab

For actual interactive Wayland clients, use `mise run compositor-desktop`, backed
by `nix/compositor/`. This Smithay 0.7 smallvil-derived nested compositor
opens isolated Firefox and GTK editor instances plus Foot on its own socket.
Columns retain their widths and scroll into view, with four workspaces,
fullscreen, client maximize requests, column resizing, popup grabs, and local
clipboard/primary selection support. Shortcuts use Super in login sessions and Super+Alt in nested demos/previews:
H/L focus, Enter starts a terminal, S cycles UI scale. Ctrl+Alt+function keys switch Linux virtual
terminals and must not be used as compositor shortcuts. Plain function keys remain application
input. `mise run compositor` retains the smaller terminal demo. See
[compositor development](../docs/compositor-development.md). The login session now uses Shine's native DRM backend; live 3D presentation
remains in the separate snapshot experiment.

The nested output uses `Scale::Custom` with `advertised_integer: 2` and a separate
fractional display scale, plus integer and fractional surface preferences of 2x.
Foot and GTK may use buffer_scale=1 with viewporter; compute density from buffer
pixels divided by logical surface size. Actual Foot, GTK, and Firefox density
was 2.0. GPU clients use DMA-BUF v4 feedback from the renderer's EGL device;
imports are validated before accepting the buffer.

`mise run compositor-check` passed formatting, six layout tests, and strict
Clippy. `mise run compositor-integration` passed with five live windows,
persistent widths, directional keyboard navigation, resizing/reordering,
workspaces/fullscreen, 150% display scale with 2x Firefox content, native GTK
popup grabs, Firefox subsurface menus and pointer selection, exact bidirectional
clipboard exchange, native document typing, and idle rendering on an empty
workspace. GPU imports had zero failures. Every original Niri window ID/PID was
preserved and the trial exited cleanly. A framebuffer image was visually checked.
No installed OS profile or desktop service was activated or replaced.

The private owner-only IPC socket supplies status, launch, layout actions, and
screenshots. Test key/pointer injection is enabled only by `--test-input`, which
ignores physical parent input. The test never types terminal commands and uses
fresh browser/editor state. Synchronize clipboard tests on selection publication,
and explicitly click the GTK document after testing its menu before typing.

Keep `flush_clients` in the event-loop callback even while rendering is idle;
otherwise new clients stall during registry negotiation. Never call geometry or
popup traversal inside `with_states` for the same surface: it recursively locks
surface state and deadlocks. Firefox HTML selects can use wl_subsurface rather
than xdg_popup, so test open state and chosen value rather than popup counts.
Client shadows also affect pointer coordinates; surface size and xdg geometry
are distinct. D-Bus and portal/session integration remain unfinished.

Cursor scaling (2026-11-04): preserve the pointer's physical pixel position
when changing UI scale, then convert back to logical coordinates and refresh
surface focus. Keeping old logical coordinates pushed the software cursor
outside the smaller logical output; the native regression reproduced this
before the fix. Refresh hit testing after asynchronous client resizes as well.

A destroyed cursor surface must trigger repaint and fall back to the default
named cursor. A live surface with no buffer is different: Firefox uses this
for CSS cursor:none, so it must remain hidden. Send frame callbacks to cursor
surfaces as well as normal windows. Status reports cursor kind/liveness,
rendered element count, and logical pointer position for diagnosis.

The real Firefox custom-cursor regression passed the full 100–200% scale cycle
with a stationary physical pointer, explicit hide/restore, and default-cursor
recovery when its owning browser exits. A framebuffer image confirmed the
custom cursor remained visible near the screen edge. Existing browser/GTK,
clipboard, and idle checks passed, preserving original host windows. Eight
Rust tests, formatting, and strict Clippy passed. This was tested nested inside
the running ohmansy desktop; no live desktop was replaced.

Named Wayland cursor failure (2026-11-04): inspect the outer Wayland cursor
separately from Shine's software cursor. In the live session, Shine reported a
named cursor at a valid pointer position while Winit repeatedly logged
"Failed to set cursor to Default". A passive wayland-cursor probe against Cage
confirmed that cursor-shape protocol was unavailable, theme "default" could
not load its arrow at 24/48 px, and Adwaita could load both. XCURSOR_THEME was
unset. Winit/SCTK therefore selected a missing default theme. This is a separate
failure from logical pointer coordinates during scaling; the earlier software
cursor regression did not cover parent Wayland theme loading.

The shared `cursor-theme.nix` helper packages Bibata Modern Classic with
default/index.theme inheritance, retains Adwaita icon assets, and supplies
theme/size defaults and the asset path. The Cage session,
standalone compositor wrapper, and spatial development shell source it; the
desktop installs its icon package. Explicit user theme/size/path settings remain
honored. The native cursor-theme flake check loads arrow, text, hand, and crosshair
images under both theme names at 24/48 px and checks preference preservation.
The session package and native customization check built successfully.

A temporary missing default-theme file was supplied to the running user's icon
path without overwriting existing settings. The exact live Wayland probe then
loaded default images and the repeated Winit errors stopped, without restarting
processes or moving the pointer. Private recovery details are in .local/SESSION.md.
The user confirmed that the cursor reappeared in the same running session.
A second live Wayland probe with a clean home and the packaged environment
also resolved both themes at 24/48 px, independently of the live fallback. The permanent fix is in reusable Nix
sources, not only that live repair.

GPU readback detail: Smithay's `map_texture` makes its EGL context surfaceless.
Mapping a screenshot before `backend.submit` caused an EGL allocation/present
failure under Zink/NVK. Queue the framebuffer copy while bound, present, then
map and save; the next render bind restores the surface. The native test passed
with this ordering. Test keys use normal Linux physical keycodes through the
private socket and the same key handler as Winit input.

The Rust and OpenGL experiment in `experiments/spatial/` runs inside the existing
Wayland desktop. `mise run spatial` launches it; `spatial-check` runs formatting,
perspective-picking tests, and Clippy. See [the lab guide](../docs/spatial-lab.md).
It displays refreshable Niri window captures, not live Wayland client surfaces.
Only generated test surfaces provide a known 2x source; existing windows retain
their captured resolution. No desktop service or installed profile is replaced.

Mise pins Rust, while `devShells.<system>.spatial` supplies native libraries and
NixOS's patched rustup. The generic rustup-init downloaded by mise cannot run
through NixOS's stub loader. The launcher bootstraps through the packaged rustup
and uses `mise link` to register the resulting toolchain. On a fresh checkout,
run `bash tools/dev/spatial.sh run` before mise can auto-install the Rust tool.
Keep Cargo's incremental cache in ignored `.build/spatial/`.

Niri's `screenshot-window --path` still changes the regular clipboard. The lab
preserves its advertised formats and restores them only when its own screenshot
remains selected. A separate source process serves the restored clipboard after
the preview exits; it naturally exits when the selection changes. Closing the
preview during capture waits for restoration. Do not replace this with a broad
process kill or a desktop restart.

Verified on 2026-11-04: native Rust build, two scene tests, formatting, and Clippy;
the Wayland preview rendered on an RTX 3060 Ti through Mesa Zink/NVK. Generated
surfaces and captures of six actual windows were visually checked. Integration
checks preserved all six original window IDs/PIDs and restored text, HTML, and
binary clipboard formats byte-for-byte, including after the capture process
exited. No OS build, activation, reboot, or live per-window streaming was tested.

CI actions are pinned. The AppArmor exception in .github/ permits user namespaces
only for the Nix unshare executable on disposable runners; do not replace it
with a global security disable. CI artifacts are not public GitHub releases.

Bibata default (2026-11-04): after the user tried and selected Bibata Modern
Classic, the shared helper, Niri desktop, greeter, session environment and
unlocked GTK defaults use Bibata-Modern-Classic at size 24. The native cursor
check loads the default alias, Bibata and Adwaita at 24/48 px and preserves
explicit environment preferences. Native customization and live-PC policy
checks passed, including greeter config validation and real dconf cursor
override/reset. The user preference and GTK settings were applied to the
installed account with original compositor and windows preserved. A running
compositor may retain its loaded cursor theme until login after an updated
system is installed. No system activation or login transition was tested.

## Shine multiple monitors (2026-11-04)

`native.rs` owns the primary GPU through libseat, DRM/KMS and GBM/EGL, with
libinput events and session pause/resume for VT switching. Each connected
connector gets its preferred mode and its own page-flipped scanout. The session
wrapper selects `--backend drm`; `--nested` keeps winit without Cage. No host
DRM device was acquired during development testing.

`desktop.rs` keeps independent scrolling layouts and four workspaces per output,
with output-local cropping in `scene.rs`. Outputs are horizontal in connector
name order; scales are per monitor, initially 125%, with client rendering still
2x. Mod+comma/period focuses a monitor, Shift moves a window. Removed monitor
windows migrate without losing column widths. Relative and absolute pointers
are clamped to the monitor union; scale changes preserve physical position.

`--outputs 2` simulates two actual Wayland outputs in one nested canvas. The
monitor trial passed independent workspaces/fullscreen, window movement and
mixed scales. Existing Firefox/GTK/cursor/clipboard integration, real nested
shortcut forwarding, and packaged session launcher/logout checks passed while
preserving parent windows and activation environment. Twelve Rust unit tests
and strict Clippy passed. The `compositor-drm` NixOS VM check booted two virtual
KMS outputs, moved real Foot clients between them, changed one scale, and
resumed rendering after a VT round trip. Headless QEMU needs a forced second
connector (`video=Virtual-2:1280x800@60e`) in the test guest only.

The user subsequently confirmed successful operation on physical monitors
(2026-11-04). Both displays work; automatic connector ordering does not match
their physical arrangement. The agent performed no installed OS activation or
reboot. Saved monitor configuration is implemented in the output-settings update below.
Multi-GPU rendering, rotation, and native framebuffer screenshots remain unsupported. See the session guide for commands.

The stronger native VM test also passed real libinput keyboard input,
Super+period monitor focus, Ctrl+Alt+F2, and page flips after returning to VT1.
The VM must enable polkit just like the shared desktop: logind's SwitchTo
request otherwise fails even though root chvt works. Keep VM waits bounded.

## Shine credential access (2026-11-04)

After the user logged into the native session, Git HTTPS used GitHub CLI's
credential helper, not SSH. The existing login keyring was locked on the regular
user D-Bus, while Shine applications inherited a private session bus. GitHub CLI
reported an invalid token with source `default` when keyring access failed; this
was not evidence that the stored token had expired. After the user unlocked the
standard graphical keyring dialog, the same token authenticated successfully
with the helper scoped to `DBUS_SESSION_BUS_ADDRESS=unix:path=$XDG_RUNTIME_DIR/bus`.
Both pending feature commits then pushed successfully.

The regular user bus activation environment lacked a Wayland display, so its
system prompter could not launch visibly. Running the packaged gcr-prompter on
the active display with that bus allowed the normal unlock dialog to work.
Secret Service Unlock and Prompt calls must share a persistent D-Bus connection;
a prompt disappears when its requesting client disconnects. Never read or print
secrets to diagnose this, or request passwords in chat. Check collection Locked
and service ownership instead. The GCR SSH socket existed, but SSH_AUTH_SOCK was
absent from Shine's inherited environment. The original normal-session bus/agent integration was incomplete. The wrapper
fix below addresses this while preserving isolation for nested previews.

Shine session-bus fix (2026-11-04): the normal login wrapper now explicitly
joins the regular user bus instead of creating a second bus. After socket
creation, its setup helper publishes WAYLAND_DISPLAY, desktop/session variables,
a cleared DISPLAY, and SSH_AUTH_SOCK for D-Bus/systemd activation. It preserves
an inherited agent; otherwise it reads a valid agent socket from the user
manager, with the standard GCR socket as fallback. The login supervisor clears
its display settings on exit only while the manager still names its display;
it forwards termination to its own compositor child and removes its runtime
state file. Nested previews retain their private bus and do not change manager
activation variables.

The updated `compositor-drm` VM check now boots the real session wrapper through
greetd with a disposable keyring. It passed child bus/display/agent inheritance,
real GCR SSH socket access, a graphical unlock of a deliberately locked fixture
keyring, two-output rendering, real keyboard and VT round trips, and activation
cleanup after logout with a lingering user manager. The packaged nested check
also passed private-bus/agent inheritance, launcher/logout behavior, and parent
activation environment preservation. This tests the wrapper in a VM and nested
preview; no installed OS activation or live session restart was performed.
Autologin still cannot unlock an encrypted keyring without its password; the
fix makes normal prompts available on the correct display.

## Shine output settings (2026-11-04)

`output_config.rs` defines strict TOML rules in `$XDG_CONFIG_HOME/shine/config.toml`
(default `~/.config/shine/config.toml`); `--config PATH` isolates development runs.
`output_control.rs` validates live IPC patches and file reloads. Supported rules
are name, optional stable ID, logical position, scale, primary, and optional
WIDTHxHEIGHT@HZ mode. EDID base-block checksums and serial descriptors/numbers
supply portable IDs; absent/invalid/duplicated identities fall back to connector
IDs. Save snapshots connected geometry while preserving disconnected rules.

The CLI supports output position/layout/scale/mode/primary/reset and config
save/reload. File edits are polled every 250 ms. Invalid schema, unsupported modes,
overlapping rectangles and disconnected pointer regions retain the last working
settings. Saves are atomic, reject managed symlinks and un-reloaded external
edits, and wait for a pending mode change. Hotplug may temporarily pack survivors
in saved spatial order when a missing monitor creates a gap. Original preferences
return on reconnect; migrated windows stay on the surviving monitor. The primary
selects startup focus and unplug fallback, without stealing existing focus.

Seventeen Rust tests and strict Clippy passed. The expanded two-output nested
trial passed atomic swaps, negative/vertical arrangements, primary, mixed scales,
physical pointer anchoring, save/reload, invalid-edit recovery, preservation of
disconnected rules, window identities and restart persistence. Real nested key
forwarding and packaged session/activation isolation checks also passed; the
Firefox/GTK/cursor/clipboard integration still passed.

The real-session DRM VM check passed live 1024x768 mode selection, saved reversed
positions/primary, virtual connector unplug/reconnect with both client identities
preserved, and a subsequent VT round trip. Linux sysfs connector force changes
do not emit their own hotplug event; the VM also emits a card change uevent.
That sequence exposed a VT race: the kernel may revoke DRM ownership before the
libseat pause callback. The timer now yields after a successful VT request and
retries transient inactive/permission failures rather than ending the session.
No physical compositor ownership, OS activation, or live desktop restart was
performed during implementation. A prepared personal configuration will take
effect after installing the updated compositor; later file edits apply live.
See [the compositor guide](../docs/compositor-development.md#monitor-configuration).

## Shine general TOML preferences (2026-11-04)

`preferences.rs` extends the same configuration with optional input.keyboard
(layout/variant/options), input.touchpad (tap/natural_scroll), layout (gap and
default_column_width), bindings, window_rules and animations. The complete
`nix/compositor/config.example.toml` is parsed by a unit test. Widths use either
pixels or proportion; window rules match exact app_id, with the last match
winning. Initial rule widths are applied before the initial xdg configure when
metadata is available, then left alone so manual widths survive reloads.

Custom bindings override the default chord, and action=none removes a default.
Mod expands to Super or Super+Alt for the running shortcut profile; exact
modifiers preserve nested forwarding. Typed actions validate required fields and
numeric ranges, launch argv directly, and reserve Ctrl+Alt+F1–F12 for native VT
switches. Intercepted releases are tracked across reloads. Keyboard changes are
compiled and broadcast to clients before preferences commit; invalid keymaps
retain the working configuration. Native libinput applies touchpad options on
reload and device arrival; missing options restore device defaults. Nested
previews leave physical host touchpads alone.

Scrolling uses cubic easing with an explicit duration; disabled/zero-duration
animations snap. Gap and animation edits apply to existing layouts, while
column-width defaults affect new windows. `ohmansy-compositor validate PATH`
checks a file without a Wayland session; connected output modes/geometry are
still checked on application. Status exposes effective preferences and native
input device settings. Output saves now use toml_edit to preserve comments,
unchanged output values and all handwritten preference sections.

Twenty-one Rust tests, strict Clippy and formatting passed. The new real-client
preference trial verified custom/disabled shortcuts, last-match app widths,
manual-width preservation, US/German keymap reload using data-only terminal
capture clients, layout/default-width updates, disabled animations, preserved
comments on save and bad-keymap recovery. Firefox/GTK/cursor/clipboard, saved
outputs/restart, real nested key forwarding and packaged session isolation tests
also passed. The DRM VM used a guest-only uinput touchpad to verify tap/natural
scroll on/off/reload, plus a real custom shortcut and app rule; existing mode,
hotplug, keyring, VT and logout checks passed. No installed OS activation or
physical input changes were performed. Existing personal output-only files remain
compatible; install the new build before adding these sections.

A long-lived agent can retain a dead Niri IPC path after login even while its
Wayland socket belongs to Shine. The test helper now falls back, after Niri IPC
fails, to a unique live Shine control socket matching the inherited Wayland
display. It never assumes the desktop label alone identifies the active server.

## Shine fine scale shortcuts (2026-11-04)

Default Mod+minus and Mod+plus/equal adjust the focused monitor by five
percentage points, clamped to 50–200%; Mod+S retains its 25-point cycle.
Shift+plus/equal supports layouts needing Shift for plus. Column resizing moves
to Mod+Ctrl+minus/equal. The configurable scale-adjust action takes a signed,
nonzero percentage point value. It uses the existing output configuration path
so neighbour positioning and pointer anchoring follow normal scale changes.
Rust tests (21), formatting and strict Clippy passed. The nested preference
trial verified US equal/Shift-plus, German plus/minus, both clamps, unchanged
column widths during scaling and the new resize chords, preserving parent
windows. The development binary was built; the live session was not replaced
or restarted. Install a new build before using the new action in live config.

## Shine Quickshell bar (2026-11-05)

Shine now provides layer-shell output mapping, rendering, pointer targeting,
frame callbacks and exclusive work areas. Layouts retain full monitor bounds
for pointer movement and fullscreen, while ordinary/maximized windows use the
remaining work area. Top panels are hidden below fullscreen; Overlay remains
above it. Keyboard-focused layer surfaces and layer popups are not implemented.

`nix/modules/shine-shell/shell.qml` supplies an independent Quickshell bar on
each output with four workspace buttons, Terminal and a clock, using shared
Ohmansy.Ui controls. Commands target the clicked output through Shine's private
IPC; panel clicks preserve application keyboard focus. No Niri state, theme
scripts or parent activation environment are used. The shell resolves relative
control-socket paths against the launcher's PWD. Its request queue removes
requests when sent, so an in-flight status poll cannot discard a button click.

`shine-shell.nix` packages the QML and shared UI. Both the packaged Shine session
and `mise run compositor-desktop` start it; the plain compositor demo remains
minimal. The development helper points OHMANSY_SHINE_QML at the checkout for
live QML reloads. Shared UI or Rust edits require rebuilding/restarting the
preview. No service is installed into the parent desktop for previews.

Twenty-two Rust tests, formatting and strict Clippy passed. The two-output
Quickshell trial verified rendering, reserved/released space, workspace and
terminal clicks on the correct monitor, preserved keyboard focus, fullscreen,
scale changes, relative socket paths, panel restart and shell exit when the
compositor closes. Existing preferences and Firefox/GTK/cursor/clipboard tests
passed. The final session package built and its nested launcher, canceled and
confirmed logout, 2x terminal and parent environment/window preservation trial
passed. An interactive desktop preview with the bar, Firefox, Text Editor and
terminal was running and visually checked at handoff; verify its live state.
No installed OS activation, physical DRM login, image build or boot was tested.

## Shine login keyring initialization (2026-11-05)

PAM unlock alone does not finish GNOME Keyring initialization. A normal Shine
login now runs `gnome-keyring-daemon --start --components=secrets,pkcs11` in its
setup helper, after publishing the session environment and before desktop
applications start. This completes the PAM login-mode daemon instead of relying
on a later D-Bus activation. The module follows services.gnome.gnome-keyring.enable;
nested previews skip the initialization and preserve the parent keyring.
GNOME documents this split in https://wiki.gnome.org/Projects/GnomeKeyring/RunningDaemon.

The observed installed login logged a successful PAM unlock, but later Secret
Service activation found no control socket and the login collection was locked.
The missing session initialization is consistent with that failure. No real
keyring files, passwords or stored secrets were read or changed to diagnose it.

The compositor-drm VM now seeds an encrypted disposable keyring before Secret
Service initialization, tests an explicit graphical unlock during autologin,
then logs out and signs in through agreety/greetd with a public fixture password.
It checks that Secret Service already has a bus owner without activating it,
that login is unlocked, that repeated requests retain the same owner, and that
no prompt window appears. The final VM check passed, including the existing
input, monitor mode/hotplug, VT and logout checks. The packaged nested trial
passed launcher/logout and parent environment preservation; all-system flake
evaluation passed. No installed OS activation or fresh physical login was done.

Fixture pitfall: creating a login collection with --unlock after the already
initialized service starts can leave its collection skeleton missing and make
the graphical test fail. Seed the VM-only file before starting the session.
Use /dev/vcs1 prompt checks for agreety; OCR requires a separate test dependency.