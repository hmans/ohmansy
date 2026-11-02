---
data:
  area: nix
  kind: workflow
  reviewed: "2026-11-02"
  status: current
id: tnfw5
title: Nix modules and image validation
---
# Official Ohmansy configuration

Build from the root flake. `flakey/` is reference material only, not an input.
`profiles/` composes factory, live, and installer systems. `modules/` contains
reusable modules, with implementation assets in matching subdirectories. Keep
the public `nixosModules` and package output names stable when moving files.
Keep the desktop module usable by people with different accounts and hardware.
Machine-specific storage and credentials belong to host configurations, not
`modules/desktop.nix` or `modules/vm.nix`.

The desktop panel uses Quickshell 0.3.0 from the locked Nixpkgs source. Its
QML lives in `nix/modules/desktop/quickshell/`; the user service starts and
stops with `niri.service`. This first migration ports flakey's panel, Niri
state, and audio controls. Fuzzel and Mako remain separate. The installer
module supplies `OHMANSY_INSTALLER` only to the live installer panel.
No runtime file or flake input points to the ignored reference checkout.

The migration passed ARM Linux flake checks and an installed-system build
on 2026-11-01. The generated private development overlay and panel were then activated in the
installed guest; the installed `quickshell.service` ran under Niri. This is not
proof of a factory-image build or a new boot. Quickshell uses comment pragmas
(`//@ pragma`), not a QML `pragma Quickshell` statement.

Use the locked Nixpkgs source to verify module options and package names.
Do not update the lock file or state versions as a side effect of another task.
Do not add personal services, private keys, preset installed-user passwords,
or development SSH access to the live image.

Validate with `nix flake check --no-update-lock-file` on ARM Linux, then build
`nix build --no-update-lock-file .#vm-image`. Building an image does not prove it boots:
test it in a disposable VM and record what was observed.

The live account intentionally has local passwordless sudo and autologin.
SSH is disabled. Never activate the live host on an installed machine. Persistent
installation uses the appliance host with first-boot owner setup or a separate
host with explicit storage and users. Never add a default password to the factory.

For installed-system login-manager or hardware changes, use `nixos-rebuild boot`
and a planned reboot. Preserve the previous boot generation for recovery.
Use `apply_patch`, stage new referenced files for Git-backed flakes, and keep
build output and VM disks outside the tracked source tree.

Boot-menu readability: `console-mode auto` passed build checks but the user
confirmed on 2026-11-02 that it did not solve the small text. EDK II renders a
fixed-size font in its graphics mode. `tools/dev/firmware-display.py` can set
its separate PlatformConfig resolution from inside the guest, with format
validation, backup, and readback. A 1024×768 preference was written to the
private development VM; the user confirmed improved readability on 2026-11-02.
Their screenshot also showed the host stretching the boot framebuffer. This per-VM
setting is not a default in the shipped firmware. See docs/graphics.md.

The login screen uses Quickshell under greetd in a separate Niri compositor.
`nix/modules/greeter.nix` configures PAM and GNOME Keyring, disables empty
password login on installed systems, and preserves live autologin. First-boot
setup runs before greetd; the greeter exits before the user desktop starts.
`greeter-package.nix` applies a scoped cancellation-reply fix to Quickshell
0.3.0; the desktop panel package is unchanged. The greetd protocol check
uses real Quickshell with a fake socket and covers retry, account switching,
delayed cancellation, extra prompts, session launch, and response-log redaction.
All ARM flake checks and the installed system build passed on 2026-11-02.
The first greeter version booted and its normal and compact layouts were
visually checked. Real password login, logout, and keyring unlock still need
user verification. No new factory or ISO image was built for this change.

The login background ports app/native/Welcome.metal to GLSL in
`nix/modules/greeter/ribbons/`, replacing the earlier Qt Quick 3D loop
prototype. The native Ohmansy.Welcome QML plugin uses QQuickFramebufferObject
and desktop OpenGL 3.3 or later. Keep ribbon paths, noise, lights, particles,
and per-ribbon depth prepasses aligned with the Metal source. Ribbons.qml
starts at 12 seconds and renders at 30 fps; motion advances at 60% of the
launcher speed. Standard password labels are hidden, while other PAM prompts
and the accessible field name remain available. The
framebuffer is capped at 2400 pixels wide. Pause preserves the animation phase.
The greeter wrapper supplies the plugin import path separately, so shader
changes do not rebuild Quickshell. Non-OpenGL backends, missing plugins, or
initialization failures use the static background.

On 2026-11-02 the GPU preview reported virgl (Apple M4 Max) and settled at
30 fps. The starting pose was visually compared to an offscreen render of
the original Metal shader at the same aspect ratio and time; this is not
a bit-identical cross-API claim. Earlier Qt Quick 3D previews measured
108–111 fps, but that renderer is superseded. Hidden windows can be throttled,
so measure visible previews. Keep the offscreen preview separate from the
Wayland PanelWindow entry point: merely declaring PanelWindow prevents
headless loading. See docs/graphics.md and the greeter-preview flake package.

Glass controls sample a shared half-resolution blurred background in
GreeterView.qml. GlassSurface.qml crops and rounds that texture, then adds
tint and a sharp half-point rim. Never include the form itself in that blur
source: labels and password input must remain separate. Form geometry and
scroll position invalidate sample coordinates. Keyboard focus brightens the glass rim, with no underline. Inter text and
64-point main controls provide a larger form. The account dropdown replaces
the separate alternate-account button. One power icon at the lower right opens a shared Restart/Shut down/Cancel
menu with eased page transitions; there is no motion toggle. The software backend uses an opaque fill. GPU preview and compact
software rendering passed on 2026-11-02; a short visible glass preview reported
112–115 fps at its test window size, not a same-size benchmark against the
earlier scene. The harmless full-screen preview accepts PREVIEW_KEYBOARD=1
for interaction checks; pair it with an automatic capture/exit deadline.
