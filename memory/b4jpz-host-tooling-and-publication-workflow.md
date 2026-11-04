---
data:
  area: tooling
  kind: workflow
  reviewed: "2026-11-04"
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

## Experimental login session

The scrolling compositor is shipped from `nix/compositor/` through
`nix/modules/compositor-package.nix`. Keeping its Cargo sources under `nix/`
also includes them in the offline release source and source archives. Rust
dependencies have a fixed Cargo hash; runtime assets use a store path rather
than Cargo's temporary build directory.

`mise run compositor-session` previews the packaged Cage-hosted session.
The installed module uses the configured terminal launcher and normal shell,
a normal-window Wofi app picker (Super+D), and confirmed sign-out
(Super+Shift+E). Confirmation disables Wofi config/history so Cancel remains
the default. A dedicated D-Bus session receives the inner Wayland socket via
dbus-update-activation-environment without importing it into the systemd user
manager. This preserves another running desktop during previews.

Packaged nested and headless session trials passed normal terminal startup at
2x, app picking, canceled/confirmed logout, and preservation of parent windows
and activation variables. Native Firefox/GTK integration passed after promotion.
Physical DRM login and reboot testing remain unverified. See the
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
[compositor development](../docs/compositor-development.md). The login session uses Cage for hardware display/input; there is no native DRM
backend or live 3D presentation in the Smithay compositor yet.

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
