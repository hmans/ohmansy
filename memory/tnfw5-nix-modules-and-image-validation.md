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

The greeter now includes Qt Quick 3D in its scoped package. The scene is
loaded through a QML Loader so missing 3D imports retain the original ribbons;
the software scene-graph backend and OHMANSY_GREETER_STATIC=1 also select the
static background. A failed Quickshell process gets one static retry. This
does not recover a broken compositor or driver. Pause motion stops continuous
rendering, and the login controls stay at native DPI over a bounded 3D texture.
The installed guest booted the scene on 2026-11-02. A visible preview reported
virgl (Apple M4 Max), OpenGL 4.1, and 108–111 fps over 15 seconds; hidden
windows were throttled to 1 fps. Both software and missing-module fallbacks
were visually verified. See docs/graphics.md and the greeter-preview flake
package. Keep the offscreen preview separate from the Wayland PanelWindow
entry point: merely declaring PanelWindow prevents headless configuration
loading. Animate vector subproperties separately from the other axes to
avoid replacing their whole-vector binding.
