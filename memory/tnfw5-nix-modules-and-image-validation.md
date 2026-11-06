---
data:
  area: nix
  kind: workflow
  reviewed: "2026-11-06"
  status: current
id: tnfw5
title: Nix modules and image validation
---
# Official Ohmansy configuration

## Shine ScreenCast portals (2026-11-06)

Portal restarts in session setup must use `systemctl --user --no-block`.
The compositor synchronously waits for setup before entering its Wayland event
loop. A blocking restart of a portal that needs Wayland replies deadlocks a
relogin before the terminal and shell start. The initial portal change made
this mistake: the installed system's previous-boot journal showed portal
startup stuck immediately after logout/login, while rebooting with no retained
portal services avoided it. The current physical login exposes ScreenCast.
The DRM VM check now keeps a Type=notify portal fixture alive across logout;
its restart waits for a real Wayland round trip before readiness. Password
relogin must start both the portal and shell. This passed with nonblocking
restarts. Do not use a newly-created socket alone as proof that login is ready.

After the user rebuilt and relogged, the physical NVIDIA session was verified
running the nonblocking setup. Both monitor bars and wallpapers were mapped,
rendered-frame counts kept advancing, and all portal services were active with
the current Wayland/session variables. Live ScreenCast, FileChooser and Settings
introspection passed. Direct wlr-screencopy captures succeeded on both physical
outputs (3440x1440 and 2560x1440); rendering continued afterward. The private
picker selection/cancellation trial passed again. A full Chatto/PipeWire stream
was not started, in keeping with the requested cancellation-only portal trial.

Shine is Smithay-based, not Niri or wlroots. A portal package alone could not
fix capture: it previously exposed no screen-copy protocol. `screencopy.rs`
now supplies wlr-screencopy v3 with XRGB shared-memory full-output frames,
optional embedded cursors, size/range checks and disconnected/resized-source
failure. Both DRM and nested render paths use the existing screenshot renderer.
Regions, individual windows and DMA-BUF capture buffers are unsupported.

`compositor.nix` enables the wlr portal and declares `ohmansy-portals.conf`:
ScreenCast uses wlr, general portals retain GTK, and secrets use GNOME Keyring
when enabled. Niri retains its separate GNOME portal selection. The login
wrapper imports Wayland/session variables into D-Bus and systemd before
reconnecting active portals; nested previews retain a private bus.

Pinned xdg-desktop-portal-wlr 0.8.2 calls `xdpw_gbm_device_create(NULL)` when
software rendering has no DMA-BUF device feedback, then dereferences it.
The version-scoped `portal-wlr-shm.patch` allows its existing shm path instead.
The private test bus now uses an explicit config because application sandboxes
may expose an unusable `/etc/dbus-1/session.conf` stub.

The native compositor, session, patched backend and customization check built;
36 Rust tests, strict Clippy and the full screenshot/clipboard/Satty regression
passed. The real private-display application
trial passed ScreenCast introspection, retained FileChooser, a 1920x1200 shm
image, picker Escape cancellation and accepting a display then closing the
session before Start. No portal stream was started. See the repeatable trial
in `docs/compositor-development.md` and `tools/tests/compositor_portals.py`.
This is nested runtime evidence, not an installed-system activation or physical
GPU streaming test. The running login compositor and user portals were preserved.
Installing the new compositor requires logout/login; service restarts alone
only suffice for later portal configuration changes. No reboot is required.

## Ribbon shader cost and runtime fidelity (2026-11-06)

The background skips its 27 particle candidates when proximity is below
0.0001. Even all candidates at maximum intensity contribute less than one
8-bit channel step there. The haze and gradient still render. Ribbon normals
use the exact derivative of the quadratic cross-section for the v direction,
including id-0 z flattening, reducing full shape evaluations from five to three
per vertex. A static 16-bit index buffer shares the 257x13 vertices while
retaining the original 256x12 grid, triangle order/winding and two-pass drawing.

RibbonScene exposes particleLayers (0–3) and particleMotionDetail (finite 0–1)
as live properties, synchronized into background-shader uniforms. Layers are
dropped faintest/smallest first; zero motion detail bypasses the four curl-noise
samples while retaining two-noise drift. Positive motion detail scales curl
strength and still performs those samples. Native defaults retain 3 layers and
full motion, including in the greeter.

The shared WallpaperQuality QML singleton supplies desktop defaults of .75
render scale, 2 layers, full motion and the existing 66 ms cadence. Its
`wallpaper` IPC target provides quality(high|balanced|low), configure(scale,
layers,motion), status and pause(bool). High selects 1/3/1, balanced .75/2/1,
low .5/1/0. Validation rejects the entire request before changing settings.
Controls cover all outputs in one shell and reset at shell restart. They are
available in Shine and the Niri wallpaper process. See the compositor guide.

Desktop GL and ES checks passed live uniform/size changes, rendered differences
at reduced particle detail, exact full-fidelity restoration and GL error checks.
Twelve baseline scenes (three poses, dark/light, two aspect ratios) found culling
differences at most 1/255 and analytic-normal differences at most 2/255. Indexed
and unindexed renders were pixel-identical in all twelve. Balanced-vs-full
particle comparisons retained almost all pixels; changes are confined to the
faint layer. Physical NVIDIA paired samples found a useful particle-culling
power reduction; indexing lowered core clocks but had little additional board
power saving. Do not infer a 5.5x whole-scene speedup from shared vertex counts.
Machine-specific measurements remain in ignored artifacts.

The final session built, and the private headless shell trial passed runtime
presets/validation/pause/resume, animation, transparent blending, image override,
software fallback, two-output controls and clean shutdown. Only Quickshell was
replaced live; compositor and app window IDs were preserved. No OS activation
or login compositor restart.

## Desktop ribbon render resolution (2026-11-06)

`WallpaperWindow.qml` now sets RibbonScene.renderScale to 0.75, independently
of the 66 ms desktop animation cadence. The scale multiplies both dimensions
after the renderer's existing 2400-pixel width cap, giving a desktop maximum
near 1800 pixels wide and about 44% fewer shader pixels. The greeter retains
renderScale 1; 4x MSAA, shaders, mesh, animation speed and output geometry stay
unchanged. Smooth texture sampling is explicitly enabled.

The native property accepts finite values clamped to 0.25–1.0. synchronize()
invalidates the FBO when it changes; renderSize reports actual target pixels
through a queued update. The expanded ribbons check verifies target sizes at
100/75/50%, unchanged window size, exact restoration of the full-resolution
image, dark/light palettes, motion, resize and GL errors under desktop GL and ES.
Both passed. Full-size 3440x1440 dark/light captures at a fixed pose were
visually compared; 75% was chosen over 50% to retain finer contour detail.

Repeated physical NVIDIA samples at the same 15 FPS and stable app window IDs
showed materially lower GPU board power at 75%. GPU clocks dropped too, so
GPU busy percentages alone hid much of the saving. Machine-specific numbers
and raw data remain in ignored local artifacts. The private headless shell
trial passed animation, transparency, image override, software fallback,
two-output controls, scale and clean shutdown. The updated session built and
only Quickshell was gracefully replaced live, preserving the login compositor
and app windows. No installed-system activation or image build.

## Source Sans browser font defaults (2026-11-06)

Dconf database settings are raw GVariant values: keep font-name as a plain
string there. Nesting lib.mkDefault inside that raw settings attrset leaves an
override attrset for the serializer and breaks full system evaluation with
"Cannot construct GVariant value from an attribute set". User preferences still
override the unlocked database default. The live-pc-policy check now builds
the actual databases and verifies font read, user override and reset across
the live/installed/factory configurations. It and the native customization
check passed after the fix, and the full reusable NVIDIA system drvPath
evaluated successfully. The user confirmed the corrected os-boot workflow
works. No installed system activation was performed by the agent.

Source Sans 3 is the accepted browser/application system-ui default, replacing
the Inter defaults from `6dd3bf1`: desktop.nix adds source-sans
3.052 and changes Fontconfig/GTK/dconf defaults to Source Sans 3 (GTK size 11).
The QML shell retains Inter. The user approved the Source Sans 3 trial.
Native customization check passed. Real Chromium on the private Wayland test
display reported SourceSans3-Regular for system-ui via CDP platform fonts;
its separate sans-serif preference still reported Liberation Sans. The user
trial has the same defaults, with Inter settings backed up first. No browser
restart or system activation was performed during verification.

## Earlier Inter browser interface defaults (2026-11-06)

Before Source Sans 3, `desktop.nix` defaulted Fontconfig sans-serif to Inter, aliased system-ui to
Inter, and supplies Inter 11 through GTK 3/4 settings and the dconf interface
font default. Chromium/Electron system-ui follows GTK; `fc-match system-ui`
alone does not prove a browser rendered that family. Browser-specific generic
sans-serif preferences can still select Arial/Liberation Sans, and websites'
explicit font families remain intact.

Native customization check passed. A real Chromium Wayland instance on the
private headless display reported Inter-Regular through CDP
CSS.getPlatformFontsForNode for system-ui text. Its separate sans-serif sample
reported Liberation Sans. The user trial updated GTK/dconf and user Fontconfig
with backups; fc-match returned Inter for sans-serif/system-ui while serif and
monospace stayed DejaVu. No browser windows were restarted or OS activated.

## Shine monitor controls (2026-11-06)

Shine's bar has a Displays button opening the existing DisplayView/DisplayState
in a floating window. `quickshell-ui.nix` exports their shared source as the
Ohmansy.Displays QML module; Niri retains its existing controller and helper.
`shine-shell.nix` supplies the Shine helper and a transient systemd user-service
relay so the preview worker survives shell reloads. Relative control sockets
are made absolute before launching that service.

`desktop/shine-displays.py` reads Shine IPC and previews per-monitor scale and
refresh rate at the current resolution. Keep uses the compositor's validated,
comment-preserving save-config path; it does not write Niri's displays.json.
Revert restores all matching monitors' original positions, scales, primary
selection and modes because scaling may reposition neighbours. Native rollback
restores the requested mode even when hardware already fell back. Replacement
monitor identities are excluded. EOF, timeout, interrupted preview and failed
saves revert without persisting. Nested outputs omit unchanged mode requests
because their resolution is controlled by the host window. UI presets stop at
Shine's 200% scale limit.

23 combined Niri/Shine backend tests passed, including exact rate choices,
partial failure, timeout/EOF/interruption, save conflicts and replacement
monitor rollback. Headless real-client trials passed scale preview/revert/keep,
configuration comment retention and opening the populated UI from the bar.
The displays-ui check, session package and native DRM VM check passed too.
The shell was gracefully replaced in the running installed session and both
physical monitors were enumerated read-only; no physical scale or mode change
was applied. Login compositor and application windows were preserved. Source
changes still require an installed-system rebuild for persistence across login.

## Shine universal clipboard shortcuts (2026-11-06)

Shine defaults Mod+C/V to typed copy/paste actions. Ordinary apps receive
Ctrl+C/V; exact terminal app IDs receive Ctrl+Shift+C/V. Incoming chords are
customizable through `[bindings]`, with `action="none"` removing a default.
`[clipboard]` configures the four outgoing chords and replaces the terminal
app-ID list. All use the existing validated live TOML reload; effective settings
appear in IPC status. See `nix/compositor/config.example.toml` and the compositor
guide for configuration and the default terminal IDs.

`clipboard.rs` resolves target keys through the seat's current XKB keymap,
falling back to another configured layout for Latin shortcut symbols. It sends
explicit modifiers, a paired key down/up, then the original serialized modifiers
to the actual focused client's wl_keyboard resources. This does not mutate
physical XKB or pressed-key state, inject a virtual keyboard, or intercept
ordinary Ctrl+C. A target key already forwarded as held is left alone. Existing
shortcut release tracking handles focus changes and binding reloads. Terminal
copy uses the terminal selection, not a TUI editor's internal selection.

The native dev binary and Nix compositor package built; the packaged binary
validated the full example TOML. All 36 Rust tests, formatting and strict Clippy
passed.
The full Firefox/GTK integration passed Super clipboard round trips. The focused
Foot/Qt trials passed both Super and Super+Alt profiles, custom incoming/outgoing
mappings, preserved raw Ctrl+C and typing, invalid-config recovery, no synthetic
repeat, and releases across focus changes/reloads. Existing real Wayland nesting
and preference trials passed too; final trials preserved parent window IDs.
Shine currently does not assign keyboard focus to layer-shell panels; panel text
entry was not verified and is not added by this change. Shift+Insert in Foot
pastes PRIMARY, not CLIPBOARD, unless the terminal binding is customized.
No installed OS activation or login compositor restart was performed.

Super+Tab column cycling (2026-11-05): Shine's `focus-next-wrap` action and
default Mod+Tab binding advance in the active workspace's column order, wrapping
from last to first. Mod+Right remains clamped. Niri's shared Mod+Tab now uses
`focus-column-right-or-first` instead of overview. Defaults, example, guides and
regressions are updated. 34 Rust tests, formatting and strict Clippy passed;
the real nested preferences trial exercised repeated Tab wraps, unchanged Right
behavior, output/workspace retention and preserved parent windows. Niri's
generated configuration passed the native customization check.

The running installed Shine predates this action. A local Launch override uses
a private IPC compatibility helper to apply the same behavior without restarting
the compositor; its socket follows the launching process. Effective live config
loaded without error and retained all application window identities. The user
confirmed the live shortcut. Remove the local override after updating the
installed compositor to use its native default. No OS activation or restart.

btop appearance (2026-11-05): the optional software bundle wraps the selected
Nixpkgs btop package through `nix/modules/btop-package.nix`, retaining NVIDIA
package overrides. Fresh configs select `ohmansy` and `theme_background = false`;
existing and explicit configs are preserved. `btop-theme.py` atomically switches
the managed user theme symlink and sends SIGUSR2 for live reload. A user service
monitors GNOME color-scheme in both desktop sessions. Light/dark palettes follow
Foot's colors. `ohmansy.btopStyle.enable = false` restores plain btop; replacing
the software bundle without the wrapper omits the watcher.

Native package build, four config-ownership tests and the customization check
passed. A real btop on a PTY and private D-Bus rendered both palettes, reloaded
live, retained terminal-default background escapes, and exited cleanly. Set
XDG_CONFIG_HOME before starting the private bus: its dconf writer inherits the
bus environment, not each client's environment. Applied the managed theme and
transparent background to the existing installed user's btop and started a
transient watcher; original process survived. No OS activation or reboot.

Official NVIDIA driver (2026-11-05): `nix/modules/nvidia.nix`, exported as
`nixosModules.nvidia`, selects the stable official driver with NVIDIA's open
kernel module for Turing and newer GPUs, modesetting, and a package-scoped
unfree allowance. The NVIDIA live profile reuses it. The x86 installer bundles
generic and NVIDIA installed systems, selects NVIDIA using PCI display IDs and
the pinned driver's `supported-gpus.json` (`kernelopen` feature), and persists
the module import in the host configuration. Unsupported or mixed legacy/modern
NVIDIA cards retain the generic payload. ARM retains only the generic payload.
Selection checks the chosen payload before erasing and installs its prebuilt
closure without a target evaluation or network. See `docs/customization.md`.

The module also overrides btop with `cudaSupport = true`. In pinned Nixpkgs,
this adds the driver runtime search path without a CUDA toolkit dependency.
`BTOP_GPU=ON` alone did not let btop load NVML: the default package lacked
`/run/opengl-driver/lib` in its RUNPATH and rendered no GPU. Both a temporary
library-path override and the corrected package rendered RTX 3060 Ti in a
separate terminal smoke test with a temporary config. Check GPU tools outside
the agent sandbox: device isolation made nvidia-smi fail despite a working GPU.

Installer/backend tests (19), NVIDIA support metadata build, generic/NVIDIA
offline policy checks, and targeted ARM/x86 evaluation passed. PCI detection
selected NVIDIA for the physical RTX 3060 Ti. The final NVIDIA installed payload
including the corrected btop package built successfully. An all-system
evaluation was interrupted by the owner's reboot and is not a completed check
for these installer changes. No new ISO or physical automated installation
was tested. After the manual driver setup and reboot, nvidia-smi confirmed
595.71.05 with Shine and Quickshell using the GPU. This confirms the running
driver, separately from the new installer automation.

Shine Files shortcut (2026-11-05): `Mod+E` launches Nautilus through the existing
launch action. Login sessions use Super+E; nested demos use Super+Alt+E.
Defaults and example TOML live in `nix/compositor/`; the shortcut is documented
in `docs/compositor-development.md`. Both modifier profiles have unit coverage.
Formatting, 33 Rust tests and strict Clippy passed. The equivalent local TOML
binding was confirmed loaded in the running installed compositor with no config
error and Nautilus present. No key injection, app launch or session restart was
performed; the shared default ships on rebuild.

Keychron Launcher HID access (2026-11-05): `desktop.nix` packages
`70-ohmansy-keychron.rules`, tagging USB vendor 3434 hidraw devices with
`uaccess` before systemd seat-late applies active-seat ACLs. This supports
Launcher without world-writable devices or input-group membership. A live
receiver was enumerated but its HID nodes denied the desktop user's read/write
access, consistent with Launcher's "Failed to open the device" error. The rule
package built, `udevadm verify` and native customization passed. Sudo required
a password, so no rule was applied to the running system and no browser
connection or remapping was verified. K2 HE configuration uses Keychron
Launcher over USB; edit Mac Layer 0 to replace Screenshot with Print Screen.
See `docs/linux-development.md`.

Shine relative workspace moves (2026-11-05): `Mod+Shift+Up/Down` moves the
focused window to the previous/next workspace on its monitor, wrapping between
1 and 4 and retaining the current workspace. Configurable/IPC actions are
`move-workspace-prev/next`; they reuse `Layout::move_to_workspace` to preserve
column width and destination focus. Formatting, 33 Rust tests (including wrap,
empty workspace, width/focus and both shortcut profiles) and strict Clippy
passed. No installed activation or live shortcut verification was performed.

Shine scale reset (2026-11-05): `Mod+0` restores the focused monitor to 100%
using the existing `scale` action. Nested previews use Super+Alt+0. The default
binding lives in `preferences.rs`; custom bindings can override it. Formatting,
all 32 Rust tests and strict Clippy passed. No installed activation or live
shortcut verification was performed.

Chrome web apps (2026-11-05): `software.nix` includes Chatto, WhatsApp, and
Bluesky desktop entries in `ohmansy.software.packages`. They run
`google-chrome --app=https://…/` and use `TryExec=google-chrome`; Chrome is
separately installed by the user. The three native desktop-entry packages
built and passed Nixpkgs' desktop-file validation. Their generated files were
installed in the current user's application directory without OS activation.
No browser windows were launched or sign-ins tested.

Terminal tools (2026-11-05): the optional software bundle now includes tig,
lazygit, tmux, fzf, ripgrep, eza, and bat alongside the existing wget and curl.
All nine requested tools evaluated as included in all seven ARM/x86 image
configurations. The native customization check passed. Hosts can still replace
`ohmansy.software.packages`. No installed-system activation, image build, or
runtime tool launch was performed.

Chromium (2026-11-05): the shared software module defaults
`programs.chromium.enable` to true and explicitly adds `pkgs.chromium` when
enabled. The pinned NixOS Chromium module only configures policies; enabling
it alone does not install a browser. Hosts can opt out with
`programs.chromium.enable = false`. Firefox and user browser profiles remain
unchanged. All seven ARM/x86 image configurations evaluated with Chromium
included. The native customization check passed default inclusion, desktop-only
scope, and opt-out assertions. The native Chromium 155.0.8059.84 package was
fetched, its version command passed, and its desktop entry was inspected.
No graphical launch, installed-system activation, image rebuild, or boot was
performed. See `docs/customization.md` for app-window invocation.

XCB and keyboard runtime libraries (2026-11-05): the shared nix-ld library
list includes `libxcb` and `libxkbcommon`. The latter package provides both
`libxkbcommon.so.0` and `libxkbcommon-x11.so.0`; there is no separate
libxkbcommon-x11 package in the pinned Nixpkgs. Native customization passed.
The native library environment built, and all three shared libraries loaded
successfully with Python ctypes using only a command-local library path.
No installed-system activation, image build, or boot was performed.

Code editors (2026-11-05): the optional software bundle now includes
`pkgs.neovim`, `pkgs.vscodium`, and `pkgs.zed-editor`. Commands are `nvim`,
`codium`, and `zeditor`; settings and extensions remain user-owned. The existing
Vim package remains available. Hosts can replace `ohmansy.software.packages`.
All seven ARM/x86 image configurations evaluated with the three packages in
their defaults. The native customization check passed, all three native
packages were fetched from the Nix cache, and their version commands passed
(Neovim 0.12.4, VSCodium 1.116.02821, Zed 1.3.6). No graphical editor launch,
installed-system activation, image rebuild, or boot was performed.

Flatpak (2026-11-05): the shared software module enables the standard NixOS
Flatpak service by default. `flatpak.nix` supplies a GTK portal fallback and a
user service that registers Flathub from a checksum-pinned repository file.
The remote belongs to each user; no applications are installed automatically.
The standard module supplies user/system export paths for launcher discovery.
Setting `services.flatpak.enable = false` omits the setup service too.
Existing installations need a rebuild and a new login for the user service
and launcher paths. Avoid shell-init network setup or activation-time downloads.

The native customization check passed real, repeated remote registration
in an isolated build home without network access, plus module/portal/export
path and opt-out assertions. Flatpak warns when optional remote metadata cannot
be fetched, but registers the remote successfully. All-system flake evaluation
passed for ARM and x86, including all seven image configurations. No installed-system
activation, desktop app launch, or image boot was performed.

Nix-ld (2026-11-04): `nix/modules/software.nix` enables nix-ld and
supplies GTK 3 with its supporting GLib, rendering, font, audio, D-Bus, and X11
libraries. Adding GTK alone does not expose its dependencies to downloaded
binaries that lack Nix RPATHs. Packages installed in the desktop are not
automatically available through nix-ld. Extend `programs.nix-ld.libraries`
for additional application requirements; do not set a global LD_LIBRARY_PATH.

All-system flake evaluation and the native customization check passed.
The native x86 library environment built, and all 26 binaries/shared libraries
in the downloaded Zen distribution
resolved without missing libraries. Zen returned its version using only the
built NIX_LD_LIBRARY_PATH override. This was a loader/version check, not a
browser UI test. No OS activation or image rebuild was performed; installed
systems need a rebuild. ARM runtime remains untested.

Desktop appearance defaults (2026-11-04): keep the unlocked dconf dark default
in `nix/modules/desktop.nix`, not `profiles/live-pc.nix`. The live-only setting
made the installer look dark while freshly installed owners started light.
The shared setting covers the installed payload and factory desktops too;
explicit user choices still override it. The `live-pc-policy` check exercises
the actual live, installed-base and factory dconf databases: fresh default,
light override, then reset to dark; all passed on the native x86 builder.
Existing ISO artifacts retain their old
defaults until rebuilt; source changes alone do not update installed guests.

Graphical installer (2026-11-04): `installer.nix` provides a Quickshell window
and a live-only root socket service. Only the live user's UID can connect;
the service owns the shared CLI lock and installation worker. Closing the
window must quit its process so reopening can recover service state. Never tie
worker lifetime to the UI. The graphical confirmation page uses an unchecked
erasure acknowledgement followed by an explicit install button. Acknowledgement
resets on page changes, disk selection changes, and submission. The UI supplies
the backend's disk-specific confirmation string; users do not type it. The CLI
retains typed confirmation. Disk identity is rechecked before erasure.
Interrupted or failed destructive work cannot be automatically
restarted. Logs and state persist only within the live session. Include the
configured Nix package in the service PATH: `nixos-install` needs `nix-env`,
which an interactive shell previously supplied implicitly. Preview with
`nix run .#installer-preview`; `installer-ui` checks all six pages at two sizes.
Use a short temporary runtime directory for Qt's Unix sockets and a private
build home to avoid contaminating unsandboxed Nix Portable's empty root.

Lessons from the graphical VM tests:

- Keep primary and back/return actions outside the installer's Flickable.
  Its viewport ends above the bottom action bar. Compact layouts reduce heading
  size and spacing based on width and height, rather than only stacking columns.
  Preview render checks assert button bounds and label fit at four window sizes.

- In `nix/modules/installer/shell.qml`, use `onClosed: Qt.quit()`. Closing a
  Quickshell FloatingWindow alone hid it but left the process holding the UI
  lock, preventing relaunch. Verify close/reopen during actual copying, not
  just before starting.
- Test through the real compositor as well as offscreen previews. Niri's
  default half-width column overrode the requested window width. The live-only
  installer rule in `nix/modules/installer.nix` opens it at full width; compact
  layouts still need keyboard and scrolling checks.
- With nested scroll views, reveal the containing log viewport, not the full
  text area's height, and clamp the outer scroll offset. Focusing a long log
  otherwise scrolled the whole installer beyond its content. See `reveal()` in
  `nix/modules/installer/InstallerView.qml`. Static screenshots did not catch it.
- Exercise the privileged service through the actual UI. Mocked backend tests
  and successful ISO builds missed the missing `nix-env` dependency. Keep
  installer copy plain and direct, including headings, buttons, and stages;
  preserve actionable errors and logs when the worker fails.

Graphical verification (2026-11-04): an isolated x86 VM with no network adapter
passed GUI installation, window close/reopen during copying, graphical shutdown,
disk-only boot, first-boot owner creation, and password login. The final log
scroll correction was then tested against that guest's real installation log.
The rebuilt final ISO passed checksums and booted to its graphical installer;
that exact final artifact was not run through another disk installation. Six
native flake checks, 16 installer/backend tests, two packaging tests, and twelve
wide/compact screen renders passed. Artifact identities and VM inventory belong
in ignored `.local/SESSION.md`. Physical hardware and ARM runtime remain untested.

Offline installer verification (2026-11-04): the final generic x86 ISO built
locally, passed packaged checksums, installed onto a fresh 64 GiB QEMU disk with
`--no-network`, then booted with no ISO. Graphical owner setup and password login
passed, including another password login after a clean restart. No network
adapter or host shares were attached. EFI mount permissions
are 0077 during installation and in the prebuilt system; the generated hardware
configuration retains the equivalent fmask/dmask options. The chosen hostname
and UUID configuration were verified. Native flake checks, the store-symlink
regression, and installer/packaging tests passed. The broader Python suite passed
66/67; the existing Mac GPU-probe `cp -c` test remains unsupported on Linux.
Physical hardware and ARM installer runtime remain unverified. Public binary
distribution needs the work described in `docs/iso-redistribution.md`; the project
source tarball is not a full dependency corresponding-source bundle.
The user confirmed the earlier terminal installer works. The graphical interface
is now implemented and has the separate verification evidence above.

Local x86 installer verification (2026-11-03): the installer now composes the
PC live profile and generates a host importing the exported `firstBoot` module.
It creates no owner itself; graphical setup creates the account after disk-only
boot. Explicit `mount -t ext4` and `mount -t vfat` are required: auto-detection
failed immediately after formatting during the first real installation test.
Successful completion syncs and unmounts the target.

Only one installer may run at a time, guarded by an exclusive `/run` file lock
before selection. The former terminal launcher kept its window open for
completion and errors; the current GUI uses the service described above.
Overlapping interactive and agent installation attempts on one VM
left a partial target and a stale UEFI entry; keep automated checks in a separate
headless VM and do not reboot a VM while someone is using its installer.
The lock's exclusion and release were tested in Python and inside the live ISO;
the retained error window was also visually verified.

NixOS's graphical desktop default enables Speech Dispatcher, whose default
eSpeak dependency brings all MBROLA voices. A binary-cache metadata audit of the
original installation's 732.3 MiB download found 553.49 MiB of voices, 85.03 MiB
of GCC, and 45.3 MiB of Nixpkgs source. Ohmansy now disables `services.speechd`
at priority 900; a host's ordinary `services.speechd.enable = true` opts in.
The earlier online installer fetched approximately 164 MiB including Nixpkgs
source. The offline installer now bundles `profiles/installed-base.nix` through
`isoImage.storeContents` and installs with `nixos-install --system`. It includes
the complete default desktop and first-boot service; no mandatory download stage
is deferred to onboarding. Future rebuilds may still fetch inputs and packages.

The initial generic system boots by OHMANSY_ROOT/OHMANSY_EFI filesystem labels.
The installer checks other disks for duplicates before erasing the selected disk.
Keep other Ohmansy disks disconnected until a rebuild uses the generated UUID
hardware configuration. The payload leaves networking.hostName empty so the
installer-written /etc/hostname works immediately; configuration.nix records the
same name declaratively. Never use the VM-specific factory layout for this payload.

Offline testing exposed a local portable Nix 2.20.6 sandbox issue: a top-level
store symlink was presented to builders as a directory. Nix's man output then
failed its NAR hash during installation. The same regression passed outside that
sandbox, and unmodified mksquashfs preserved source symlinks. No squashfs overlay
or global sandbox change is needed. The offline flake check exercises a real
store symlink through assembly and extraction to detect affected builders.

The final ISO was built and packaged locally with verified checksums. A fresh
64 GiB test disk installed successfully, booted without the ISO, completed the
real graphical owner wizard, and logged into the desktop. After a clean restart,
the account remained available and password login succeeded again. Native flake
checks and five installer tests passed. The broader Python suite passed 64 of 65 tests;
the existing Mac GPU-probe copy test uses `cp -c` and fails on Linux.
The Linux launcher and workflow are documented in
[Linux development](../docs/linux-development.md#test-the-installer-locally).
Physical installation and ARM installer boot remain unverified.

Persistent Linux VM setup (2026-11-03): both architectures now export `vm-image`
and `installer-iso`. The factory selects the matching UEFI fallback loader and
root partition type; serial console and the generated installed flake also follow
the target platform. The native x86 flake checks and factory build passed; ARM
factory platform assertions evaluated successfully. A fresh writable x86 factory
copy booted under QEMU/KVM with VirtIO GL to the graphical first-boot welcome,
including ribbons. Account creation and persistence across a reboot were not
exercised in that check. See the persistent VM section in
[Linux development](../docs/linux-development.md). The factory wizard provisions
an already installed disk; the separate installer ISO installs onto a blank disk.
At that point the new x86 installer output had only evaluated; see the later
installer build and boot verification above.

The first x86 factory inherited the Mac VM's hardcoded 2x display scale, making
setup too large. `ohmansy.vm.displayScale` now defaults to 1 on x86 and retains 2
on ARM, and generates both desktop and greeter/setup output settings. Native
flake checks passed, including assertions for both output configurations; ARM
platform assertions evaluated with scale 2. A corrected fresh x86 factory was
built and visually verified at the welcome screen at scale 1. The initial disk
was retained; the user confirmed setup had not yet created an account.

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
state, and audio controls. Mako remains separate. The installer
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

Validate with `nix flake check --no-update-lock-file` on the native Linux architecture. Build `.#vm-image` on ARM or `.#iso-nvidia` / `.#iso` on x86-64 when an image is needed. Building an image does not prove it boots:
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

Shine naming (2026-11-04): the experimental window manager/compositor is
named **Shine**. The login label is **Shine (experimental)**; compositor window
titles, demo content, CLI heading, package descriptions, and user guides use
Shine. The distribution remains ohmansy. Existing command names, package paths,
and session identifiers are retained for configuration compatibility.

Login sessions (reviewed 2026-11-06): the shared desktop imports
`compositor.nix`, which offers **Shine (experimental)** alongside
**ohmansy (Niri)**. `desktop.nix` defaults to Shine's existing `ohmansy`
session ID with `lib.mkDefault`, covering the greeter and live autologin.
Setting `ohmansy.compositor.enable = false` restores the Niri default;
`services.displayManager.defaultSession = "niri"` keeps both sessions and
defaults to Niri. The native customization check passed the shared default,
generated greeter JSON, disabled-Shine fallback and explicit host override.
All-system flake evaluation passed for ARM and x86 outputs and policies.
No installed-system activation or login restart was performed.
The session is also registered with
`services.displayManager.sessionPackages`. It runs Shine's native DRM/KMS and libinput backend directly, with independent
workspaces on connected outputs of the primary GPU. Cage has been removed. Niri's panel and services
remain scoped to Niri. The terminal module exposes its launcher internally so
the alternative session honors terminal customization.

The greeter reads system-generated `/etc/ohmansy/greeter-sessions.json`; the
selected entry supplies both the executable and XDG desktop/session variables.
Selection is disabled while submitting authentication and clears typed responses.
PAM, keyring handling, auth retry, account switching, and live autologin policy
remain in the existing path. The default session setting drives autologin too.
Additional system-defined entries use `ohmansy.greeter.sessions`.

The package built on x86-64. The greeter's three isolated greetd protocol flows
passed, including selecting the experimental session across auth retry. Six
wide/compact/narrow preview images and the selection/busy-state flow passed.
All-system flake evaluation, native customization checks, six layout tests,
strict Clippy, and nine development/archive tests passed. Packaged Cage sessions
passed under nested Wayland and headless backends, including normal terminal
startup, app picker, Cancel and confirmed sign-out, and parent desktop/activation
environment preservation. Native Firefox/GTK integration still passed.
These are build/runtime checks, not a physical DRM login or a rebooted image.
No installed system, greetd service, or running desktop was activated/restarted.

The login background ports app/native/Welcome.metal to GLSL in
`nix/modules/greeter/ribbons/`, replacing the earlier Qt Quick 3D loop
prototype. The native Ohmansy.Welcome QML plugin uses QQuickFramebufferObject
and desktop OpenGL 3.3 or later. Keep ribbon paths, noise, lights, particles,
and per-ribbon depth prepasses aligned with the Metal source. Ribbons.qml
starts at 12 seconds and renders at 30 fps; motion advances at 60% of the
launcher speed. Standard password labels are hidden, while other PAM prompts
and the accessible field name remain available. The
framebuffer is capped at 2400 pixels wide. Pause preserves the animation phase.
As of 2026-11-05, the shared renderer requests 4x MSAA for ribbon silhouettes
and depth-tested folds. Qt resolves the multisample target and clamps samples
to driver support. Desktop GL explicitly enables multisampling; ES uses its
implicit multisample rasterization. This also covers Niri and Shine wallpaper.
The native x86 `ribbons` check passed desktop GL and ES through llvmpipe,
including dark/light palettes, motion, framebuffer resize and GL error checks.
The resolution cap and animation cadence are unchanged. GPU memory/bandwidth
increase; hardware performance and installed activation remain unverified.
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
GreeterView.qml. The shared ui/GlassSurface.qml crops and rounds that texture, then adds
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

The shared Ohmansy.Ui module in nix/modules/ui supplies glass surfaces, controls,
icons, theme values, and transitions. Copy and button-role rules live in
`docs/design-system.md`. The display name is
always lowercase **ohmansy**; preserve case-sensitive code identifiers.
`GlassButton.actionRole` selects primary (muted purple glass), secondary (slate
glass), or return (subtle slate glass). Bright lavender fills and nearly invisible
return buttons were rejected; preserve the existing glass treatment.
Explicit fallback tints preserve
these roles under software rendering; previously all buttons fell back to
the same surface color. The legacy `primary` property remains compatible.
quickshell-ui.nix packages it; both shell
wrappers set QML_IMPORT_PATH. Greeter wrappers preserve local control names.
The desktop menu bar uses the same glass with no QML backdrop; Niri 26.04
provides cached wallpaper blur through its layer rules (xray true). Bar, launcher,
and audio popup declare explicit BackgroundEffect.blurRegion regions. The launcher
region follows its rounded glass, not its full-screen transparent click catcher.
The earlier xray false rules produced tint without visible blur in the virgl guest.
An A/B check on 2026-11-02 showed xray true visibly blurring the wallpaper while
text and icons stayed sharp. This mode does not sample application windows behind
the glass. The non-xray failure is a runtime observation, not a diagnosed GPU bug.
On 2026-11-02 both wrapper builds, flake checks (including authentication),
Niri validation, and the installed-system build passed. Shared greeter QML was
previewed; the normal desktop panel service was hot-updated and visually checked
without ending the user session. The new system generation was not boot-tested.

The application launcher now uses shared glass controls and DesktopEntries in
Launcher.qml. The bar and Mod+Space toggle its launcher IPC target. Use an
overlay layer with exclusive keyboard focus while open: native grabbing popups
failed when opened through IPC without a recent parent input event. Forward
unhandled Keys.onPressed events so TextField still handles Enter and editing.
Installed build and Niri validation passed on 2026-11-02. Search, empty results,
Enter launch, and outside-click dismissal were checked in the live desktop.
The new generation was staged and its QML hot-loaded; no reboot or ISO build.

The Quickshell user service must inherit the session PATH so desktop entries
with bare Exec names can find system, profile, and user tools. A helper-only
service PATH previously prevented nautilus and nixos-help from starting.
The initial 2026-11-02 fix listed profile paths in the service and passed live
menu-launch checks. It was replaced on 2026-11-06 by `enableDefaultPath = false`
and removal of the explicit service path list, following NixOS's Niri service.
Panel helpers use explicit package paths. Updating QML alone cannot fix a
service environment; see the desktop tool discovery verification below.

Launcher activation delegates desktop IDs to gtk-launch/GIO through the packaged
OHMANSY_APP_LAUNCHER helper. Do not run DesktopEntry.command manually: GIO
handles D-Bus activation, field codes, and working directories. xdg-terminal-exec
chooses terminals with a system Foot default and user overrides. The helper uses
an independent systemd user scope and journal streams. This prevents shell
restarts killing apps and avoids closed QProcess pipes breaking terminal startup.
Build and live Files, Manual, and Vim-in-Foot checks passed on 2026-11-02; the
menu-launched terminal survived a shell restart and an invalid desktop ID returned
nonzero. The QML Process displays request failures; later app crashes are separate.

Desktop light/dark colors live in Ui.ColorPalette: white or #202020 surfaces
at 85% opacity, plus semantic text, secondary, border, focus, hover, and selection
tokens. Desktop Theme delegates to this palette; GlassSurface and GlassField
accept an optional colors palette, retaining greeter defaults when omitted.
Qt.styleHints.colorScheme follows the guest preference, with unknown using light.
The desktop shell must default QT_QPA_PLATFORMTHEME to xdgdesktopportal: the
plain Niri Qt platform theme did not react to the portal preference. On 2026-11-02,
the installed build passed; dark mode and live return to light were visually
verified, then the original guest preference was restored. No reboot or ISO build.
The launcher now uses xray false to show underlying windows; its blur remains
unresolved on virgl. Bar and audio popup retain cached wallpaper blur.

Desktop shortcut migration (2026-11-02): all 58 active reference Niri bindings
are present; see docs/keyboard-shortcuts.md for the current map. The packaged
desktop helper (named `ohmansy-desktop`) supplies fixed actions and Quickshell
menu modes; it never evaluates history content or window titles as commands.
Cliphist runs as a Niri user service, Mako retains notification history, and
Swaylock uses PAM with a forking service to establish the lock before suspend.
Quickshell IPC uses `openMenu`: a `show` method collides with its CLI subcommand.
SSH IPC must use the same WAYLAND_DISPLAY as the desktop. Set the IconTheme
Adwaita comment pragma to resolve symbolic menu icons with the portal platform
theme. The installed build, Niri validation, seven targeted tests, live window
picker, and power confirmation passed. Final icon loading had no warnings.
Real unlock, physical media keys, and multiple monitors remain untested.

Shortcut help uses ShortcutPanel.qml and the shared desktop glass palette.
`desktop/shortcuts.json` is the source for both generated Niri bindings and
the installed help data; custom bindings outside it are not displayed.
Firefox launch (2026-11-04): shared `Mod+Shift+Return` spawns `firefox` and
appears in shortcut help. Native x86 customization check validated the generated
bindings and Niri configuration; no installed-system activation was performed.
Numbered workspaces (2026-11-04): shared `Mod+1` through `Mod+9` use Niri's
`focus-workspace` with numeric indices on the current monitor. Native x86
customization check passed; installed-system activation remains pending.
Mod+Shift+Slash opens the searchable panel. Super+T and Super+B were removed
at the user's request; Super+Return still opens Foot. Keep JavaScript compatible
with Qt's engine: Array.flatMap passed Node tests but failed in Quickshell 0.3.0;
use map/join for search text. Runtime loading must supplement pure Node tests.

The first shared-shortcut migration missed vm.nix's desktop.kdl include, leaving
the VM with zero bindings after reload/reboot. Niri validate still passed: empty
bindings are valid. Fixed by generating desktop.kdl in desktop.nix for all
profiles and making both entry points include it. The VM overrides only the
entry text for output settings. The niri-config flake check now reads packaged
entry/include sources for appliance, live, and installer, checks all actions
against shortcuts.json, and validates the resolved KDL. It passes and rejects
the previous raw include. Live activation reloaded all 60 intended bindings.

Fish styling (2026-11-03): software.nix imports fish-style.nix. When Fish and
ohmansy.fishStyle.enable are enabled, use the standard NixOS Starship integration
with its packaged pastel-powerline preset. Bundle JetBrainsMono Nerd Font and
select it in Foot. Personal ~/.config/starship.toml takes precedence; hosts can
override programs.starship settings/presets or disable the Fish style module.
Fish keeps its standard syntax colors and greeting; the custom vendor config
and rejected inverse-block prompt were removed to keep this integration simple.
Customization checks cover enabled/disabled styling, Fish opt-out, individual
Starship style overrides, and alternate presets without leaked colors. Installed
build passed; actual light/dark Foot previews confirmed separators and icons.
Existing Fish/Foot processes need restart to load prompt/font changes.
Local commands (2026-11-04): software.nix defaults
`environment.localBinInPath = true` with mkDefault. NixOS's generated environment
prepends each user's `~/.local/bin` to PATH, including through Fish's foreign-env
integration. This is independent of prompt styling. A host can disable it with
`environment.localBinInPath = false`. Native x86 customization check passed;
default/override evaluation and an isolated Fish process loading the built
set-environment confirmed the setting and PATH order. No installed-system
activation was performed. Log out and back in after rebuilding to refresh the
session environment.

Pastel Powerline only sets segment backgrounds upstream, so its text inherited
black in light terminals. fish-style.nix now supplies explicit #f5f5f5 text for
all preset segments, preserving the user's preferred dark-mode look. Defaults
remain overridable and apply only when this preset is selected. Both actual
light/dark terminal previews verified consistent lettering after activation.

Process utilities (2026-11-04): software.nix includes `pkgs.psmisc` in the
optional utility bundle to provide `killall`. The evaluated x86 factory defaults
include it; the pinned package's `killall --version` and native customization
check passed. No image rebuild or installed-system activation was performed.

Build tools (2026-11-04): `software.nix` includes `gcc`, `gnumake`, `python3`,
and `pkg-config` in the default utility bundle passed to
`environment.systemPackages`. Python 3 was already included. Hosts can still
replace the bundle through `ohmansy.software.packages`. All seven public
NixOS image configurations evaluated with all four tools on their respective
ARM/x86 platforms; the native x86 customization check passed. No image build,
boot test, or installed-system activation was performed.

Mise packaging (2026-11-04): `nix/modules/mise-package.nix` packages upstream
2026.11.0 musl release archives with separate SHA-256 pins for x86 and ARM.
The shared overlay supplies the optional software bundle and both development
shells; `.#mise` exposes the same package. Keep updates in the package's version
and hashes, not the OS Nixpkgs pin. Self-update is disabled in the package.
The generic glibc download previously hit NixOS's stub loader; the musl binary
runs directly. Task execution does not require shell activation.

Shell activation (2026-11-05): `software.nix` activates mise in interactive
Fish, Bash, and Zsh when `ohmansy.software.packages` contains `pkgs.mise`.
Replacing the bundle without mise removes these hooks. Codex is absent from
the system defaults; users can install it with `mise use --global codex@latest`.
The native customization check passed, including activation and omission
assertions. Direct Fish and Bash activation checks passed; Zsh was evaluated
only. No OS activation, image build, or boot was performed.

Desktop tool discovery (2026-11-06): when the optional bundle includes mise,
`software.nix` also adds `$HOME/.local/share/mise/shims` to
`environment.sessionVariables.PATH`. This reaches PAM logins and the systemd
user environment. Niri's Quickshell service disables the default service PATH
and supplies no replacement. Its wrapper preserves the inherited PATH and
exports explicit Niri, configured terminal, and nmtui executable paths to QML.
Shine's shell also preserves the inherited environment. Keep interactive activation too;
the shims let graphical apps resolve tools without running shell prompt hooks.
The native customization check passed for inclusion, omission, PAM HOME
translation, environment.d output, and absence of a panel service PATH override.
Both wrappers built and passed private D-Bus/offscreen Quickshell tests with a
PATH containing only a test command directory. Both the shells and their child
commands retained that exact PATH. A clean non-interactive environment also
resolved the Codex shim and returned its version. The old sessionPath wrapper
parameter and PATH reconstruction were removed.
No OS activation, graphical app relaunch, or login-session verification was
performed. Existing processes need a relaunch from the updated environment;
rebuild and log in again for the full desktop to inherit the change.

Both archive hashes matched upstream GitHub release metadata. The native x86
package built and returned 2026.11.0; an isolated task verified environment
variables and shell execution. Native customization and factory metadata
checks passed. All-system flake evaluation passed, and both architectures'
development shells evaluate to 2026.11.0.
ARM runtime, OS activation, and image rebuild remain untested.

Avoid the v2026.11.0 upstream source flake for routine packaging: its release
build is followed by an all-features test compilation, taking over 20 minutes
on this builder. It then failed eight tests (3335 passed), including process
tracking and archive tests. The binary package avoids this compilation and
does not add another Nixpkgs input; the root lock remains unchanged.

Herdr packaging (2026-11-04): the default software bundle includes terminal
herdr from the upstream `herdrdev/herdr` flake at `v0.9.5`. Keep its upstream
Nixpkgs and Rust overlay pins; ohmansy's Nixpkgs release pin is unchanged.
The root flake exports the package on both Linux architectures and a narrow
overlay exposing `pkgs.herdr`. The public default/software modules and internal
image configurations apply that overlay. Replacing `ohmansy.software.packages`
with an empty list still omits herdr; desktop-only imports do not install it.
The customization check now exercises the public modules.

Nested inputs introduced a lock-generation requirement: follows paths in
`installation-package.nix` must be prefixed with `ohmansy` when placing the
release under the generated host flake. The factory-platform check resolves
every generated input reference. Native customization/factory-platform checks,
all-system flake evaluation, offline metadata inspection of the generated host
flake, and six factory/ISO Python tests passed. The x86 package built and ran
`--version` and `--help`; ARM was evaluated, not built or run. No image rebuild,
boot test, or installed-system activation was performed.

Module layering (2026-11-02): default.nix composes desktop.nix and software.nix.
The public flake exports default, desktop, software, and vm modules. Factory,
live, and newly generated installer hosts use the combined module. Direct
desktop imports now omit optional software; existing hosts wanting the full
bundle must import default instead. software.nix uses standard Firefox/Fish
enable options with mkDefault and a replaceable ohmansy.software.packages list.
Fish's login-shell preference applies only while enabled; first-boot setup
receives the configured shell instead of hardcoding Bash.

Foot title bars (2026-11-05): `terminal.nix` sets `[csd] size=0` so Foot
hides its client-side title bar even when the compositor requests client
decorations. The generated x86 configuration passed `foot --check-config`;
the native customization check passed. No installed activation or visual
runtime check was performed. Existing windows need to be reopened after rebuilding.

terminal.nix coordinates ohmansy.terminal.package and desktopEntry, installs
`ohmansy-terminal`, and supplies xdg-terminals.list.
Shortcuts, network controls, and installer launchers use xdg-terminal-exec;
per-user lists still override the system default. Only a selected Foot package
receives the wrapper, palette, compositor rule, and theme signals. Standard
Foot/Kitty/Alacritty/Ghostty IDs are inferred; other packages need an entry ID.
See docs/customization.md. Full ARM flake checks and the installed-system build
passed. The customization check exercises disabled Firefox/Fish, Bash fallback,
Zsh, an empty utility bundle plus an added package, and actual Kitty terminal
command resolution. The default guest was live-activated and resolves Foot;
no new image was built or booted.

Session handoff logging (2026-11-02): the guest VT contained the Niri startup
warning about import-environment without variable names. greeter.nix now wraps
niri-session with systemd-cat, identifier ohmansy-session, for both authenticated
login and autologin. This retains diagnostics in the journal without printing
them on the VT between compositors. Installed-host build and journal routing
smoke check passed; selected for next boot, visual handoff not yet verified.

Inline bar controls (2026-11-02): Bar.qml uses symbolic sun/moon and speaker
buttons. Appearance toggles the shared light/dark preference directly; speaker
click toggles mute, wheel adjusts volume, and a compact inline slider sets it.
AudioPopup.qml and AppearancePopup.qml were removed. Device selection remains
in Desktop Controls → Sound. Date hover tooltip is disabled. Installed host
build and live QML loading passed; no QML component errors were logged.
The transparent bar uses Theme.onWallpaper and forwards it into QuietButton;
this fixes text, icons, slider, and hover colors independently of light/dark
mode. Tray images are rendered white. Other surfaces retain the system palette.

Display controls (2026-11-04): Desktop controls → Displays opens DisplayPanel.qml
and DisplayView.qml. DisplayState.qml talks to the packaged Python helper
desktop/displays.py. The helper queries Niri outputs and offers exact refresh
rates at the current resolution plus fractional UI scales. Preview changes
revert after 15 seconds, on Revert, or on closing the panel. The worker runs in
a transient user service outside Quickshell's lifetime; EOF and timeout restore
the previous mode and scale. A simulated-worker test killed the relay and
verified rollback without any real display commands. Keep writes user-owned
XDG_CONFIG_HOME/ohmansy/displays.json atomically, preserving other saved outputs.
The ohmansy-displays user service restores saved choices at login only when the
connector and monitor identity match. Reconnecting during a session may require
applying again. No personal hardware settings are stored in reusable modules.

`mise run display-ui` / `nix run .#display-preview` uses simulated monitors.
The displays-ui check runs the UI flow and renders wide, narrow, short,
confirmation, empty, and error states, asserting action bounds. Native x86
builds of the shell, preview, customization check, and displays-ui check passed;
13 backend tests plus four desktop helper tests passed. A hidden panel loaded
in the active Wayland session and real monitor enumeration passed read-only.
No installed-system activation or physical mode/scale changes were performed.
Qt offscreen cannot load layer-shell panel types; verify those under Wayland.
The broader Python suite had sandbox socket errors and a Mac-only /bin/cp test;
automatic approval review rejected an elevated rerun of the full suite.

Firefox styling (2026-11-02): software.nix imports firefox-style.nix. Packaged
AutoConfig registers a USER_SHEET scoped to browser.xhtml, without writing user
profiles or replacing userChrome.css. Compact density and hidden bookmarks are
user-overridable defaults; ohmansy.firefoxStyle.enable disables the integration,
use ohmansy.browserStyle.enabled=false in
about:config to disable only the stylesheet after restart. The css option replaces
the stylesheet. The selected Firefox wrapper retains existing extraAutoConfig.
Only the AutoConfig sandbox is disabled for the privileged stylesheet service;
the web-content sandbox is unchanged. Firefox 158 uses .urlbar-background rather
than the older ID, so both selectors are covered. Internal chrome CSS is version
sensitive. Installed-host build, customization check, and isolated Marionette
light/dark computed-style checks passed; a blank-profile screenshot was inspected.
The guest was test-activated, with a separate visible preview profile; existing
Firefox processes need restart. No new ISO or boot validation was performed.

Firefox refinement: 28px tabs with 4px corners, quieter selected fill, compact
16px toolbar glyphs, no toolbox separator, and a single address-field focus
border. The Firefox 158 searchmode-switcher uses moz-button shadow DOM: override
its --button-background-color-muted family to remove the inner pill; generic
button colors and ::part did not change its rendered fill. Native control focus
remains. Final packaged browser checks confirmed transparent picker fill, no
extra field outline, and both theme colors; a blank-profile screenshot was
visually checked. Installed configuration test-activated, not boot-tested.

Firefox suggestions-open focus: the urlbar-input-container adds an inner blue
outline independently of the outer background. Remove that container outline
only while focused; retain the outer 1px focus border and child control cues.
An isolated Firefox 158 query reproduced the duplicate; packaged fix verified
with suggestions open and a screenshot. Tab corners are now 6px by request.

Wallpaper parallax investigation (2026-11-02): wallpaper.qml derived horizontal
drift from the active window column and vertical drift from workspace index.
It is not viewport tracking. Live Niri 26.04 reports null tile_pos_in_workspace_view
for tiled windows and no workspace viewport field. Upstream PR #4147 remains
open and proposes resting scrolling_view_pos destinations, not continuous
animation frames (https://github.com/niri-wm/niri/pull/4147). True gesture-aligned
parallax needs compositor support; focus smoothing cannot correct the input.
Alternatives presented: animated ribbons without simulated drift (recommended),
vertical workspace-only drift, or a deliberate compositor patch investigation.
The user initially chose to leave the wallpaper unchanged. On 2026-11-03,
removing QML vertical drift alone did not stop scrolling: Niri also moves
background-layer surfaces with each workspace. The wallpaper layer rule now
sets `place-within-backdrop true`, and layout uses a transparent background.
This keeps one wallpaper behind
the workspace stack, including the overview. The surface must remain on the
background layer and ignore exclusive zones. Built, live-activated, and verified
with screenshots before, during, and after a workspace switch; the window moves
while the ribbons remain in place. Original workspace restored.
See https://niri-wm.github.io/niri/Overview.html#backdrop-customization.
Overview uses `workspace-shadow { off; }`, with no workspace frames or tint.
Individual window shadows remain enabled. The user rejected both padded tinted
frames and a thin-line version. Do not restore that experiment: Niri cuts out
the workspace interior, hardcodes square corners, and scales spread with output
height. Filled, rounded overview-only cards need compositor support;
layout.background-color also affects the normal desktop.
The user then requested vertical parallax within that stationary layer, and
increased its range after trying the subtle version. The workspace-index offset
is now `-64 * atan((index - 1) * 0.55)`, eased over 650 ms with OutCubic:
about 32 logical pixels from workspace 1 to 2, bounded below 101 pixels overall
within the 112-pixel overscan margin. Horizontal drift is unchanged. This is destination
tracking, not continuous gesture tracking; keep the compositor backdrop rule.

Graphical first boot (2026-11-02): first-boot.nix provides a greeter-owned mode-0600
Unix socket and socket-activated root backend. greetd selects first-boot/shell.qml
until the provisioned marker exists, then uses the normal login screen. The
shared glass controls, FadeSwitch, and ribbons render under the unprivileged
greeter. Backend checks SO_PEERCRED, bounds requests, validates account input,
and feeds chpasswd through stdin. No passwords enter argv, Nix, or logs. Root-owned
pending state permits retry only for the same account; owner.nix and completion
marker use atomic replacement. The state directory must be traversable by the
greeter (0755) so the shell can stat the marker; state files remain 0600.
Diagnostics go to the journal and factory boot status output is quiet.

Preview uses a fake controller and cannot create accounts. Defer its initial
page selection until component completion to avoid FadeSwitch binding loops.
Installed ribbon URLs must use /etc/ohmansy/greeter/scene/Ribbons.qml: relative
paths from the separately stored first-boot source worked in preview but failed
after installation. Fallback wallpaper worked; corrected accelerated preview
reported virgl and rendered ribbons. ARM flake checks, full factory build, five
Linux backend tests (including real socket peer rejection), and compact/software
previews passed. First fresh boot reached graphical welcome and status replied;
The corrected factory was also booted fresh and visually verified with ribbons,
glass controls, and no console text over the welcome screen. User completed owner
creation; a clean restart reached the normal login screen with the new account.
The final setup button incorrectly called Quickshell.quit(); corrected to Qt.quit().
This correction is source-only until the factory is rebuilt; direct button
handoff with the correction still needs runtime verification.

Release updates (2026-11-03): new factory and installer configurations use a
pinned ohmansy input, with nixpkgs following its lock. installation-package.nix
ships a minimal exact-source flake snapshot and a precomputed lock for offline
first boot, including dirty development sources. The installed configuration
retains ohmansy.outPath through system.extraDependencies. Machine hardware,
accounts, preferences, and system.stateVersion are local installation files.
persistent-vm.nix no longer owns stateVersion; the factory and generated host do.

The default module installs ohmansy-update prepare/apply. Preparation builds a
private copy; apply verifies fingerprints, registers the exact system through
nix-env, selects boot with switch-to-configuration, and promotes only the pin
and lock. Errors attempt to restore the preceding profile and boot selection.
Prepared closures remain GC-rooted; retention cleanup is not implemented.
Symlink-managed configurations use nixos-rebuild directly. Older copied-module
installations need the explicit one-time migration in docs/updates.md. No disk
reset, impermanence, automatic release channel, or automatic reboot is involved.

Verification: all ARM flake checks passed; generated bootstrap evaluated offline
with --no-update-lock-file and built a full installed system. An isolated clone
booted local release fixture A, prepared/applied B with the real updater, booted
B, then booted A through nixos-rebuild boot --rollback. Password/account state,
provisioning marker, a home file, local package override, hardware configuration,
and stateVersion survived. Fixtures used local flake inputs instead of publishing
GitHub releases; remote release delivery was not tested. Host tests: 42 total,
41 passed and one Linux peer test skipped. No fresh factory/ISO image or current
user guest was replaced for this task.

Fresh factory verification (2026-11-03): the updater-enabled factory image was
built, packaged, embedded into the stopped app, and its code signature verified.
A new guest booted to the graphical first-boot welcome screen with ribbons.
The user then confirmed account creation and successful login. No credentials
were entered by the agent.
The image includes the Qt.quit final-button fix and the pinned installation
configuration. This is a dirty-source local build, not a published release.

Light ribbon palette (2026-11-03): Ui.Appearance supplies a 150 ms InOutCubic lightMix blend from the portal-backed Qt preference. Desktop wallpaper imports the UI module and the xdgdesktopportal platform theme. Ribbons.qml samples targetLightMix with motion; the shader blends backdrop, material lighting, particles and vignette in one scene. Desktop motion now advances at 0.15 speed with a 66 ms timer, temporarily 16 ms during appearance fades. The greeter retains 0.6 speed, 33 ms pacing, and lightMix zero. On-wallpaper Theme text/control colors and tray icon brightness follow the same blend; the earlier always-white bar rule is superseded. Popups retain their existing immediate palette changes.

Plugin/desktop packages built, ARM flake checks passed, and initial dark/mid/light GLSL frames were rendered with llvmpipe and visually inspected. QML checks passed startup endpoint, intermediate blend, no-jump reversal and final endpoints. Offscreen Qt ignores a forced colorScheme in the test backend, so interpolation was tested directly. Later timing and light-background refinements were built and test-activated in the installed guest over SSH; this does not select them for the next boot. No factory image rebuilt.

Niri window outlines now follow appearance through an optional home-relative include of ~/.local/state/ohmansy/niri-appearance.kdl. The shell writes the selected packaged light/dark KDL palette atomically at startup and on preference changes; identical content does not trigger a write. This uses Niri's include watcher, not compositor restarts. Both palettes and the complete config validated, and real GSettings dark/light toggles selected each palette in the live guest. Keep colors in desktop/niri-{light,dark}.kdl, and preserve the default border when the optional file is absent.

The VM entry point initially omitted this include, so its palette file updated
without changing the visible borders. Fixed desktop/vm.kdl to include the palette
after desktop.kdl. The niri-config check now requires that include and ordering
for every image profile. The check, installed system build, and live validation
passed; a guest screenshot confirmed dark slate light-mode borders, with a
stronger active rim and softer inactive rim.

Portable ribbons (2026-11-03): physical NVIDIA live-USB logs showed OpenGL ES 3.2 with hardware rendering. The original QOpenGLFunctions_3_3_Core initialization failed before shader compilation, producing empty shader logs and the static fallback. RibbonScene now uses QOpenGLExtraFunctions, context-specific GLSL headers, glClearDepthf, and guards desktop-only FRAMEBUFFER_SRGB state. Shared shader bodies are unchanged. The ribbons flake check renders through desktop GL and ES in an isolated Xvfb display with llvmpipe, checking context type, dark/light frames, motion, and GL errors. Both passed on ARM Linux; NVIDIA runtime validation and a new ISO remain pending.

PC live defaults (2026-11-03): profiles/live-pc.nix composes the generic live image; both x86 ISO variants import it. An unlocked dconf user-profile database defaults color-scheme to prefer-dark. The oneshot ohmansy-live-scale user service follows niri.service and precedes panel/wallpaper startup; it discovers output names through Niri IPC and sets all connected displays to 1.25. Niri 26.04 has no wildcard output matching. Later hotplugged displays retain automatic scaling unless the helper is restarted. Installed defaults and ARM VM 2x scaling are unchanged. All-system evaluation passed. The PC policy check was executed with native ARM packages: Niri configs, scale-script syntax, and real dconf dark default, light override, and reset passed. No new ISO or physical PC boot yet.

AppImage defaults (2026-11-04): `nix/modules/software.nix` enables the
standard `programs.appimage.enable` and `programs.appimage.binfmt` options
with mkDefault, installing appimage-run and registering type 1/type 2 executable
signatures. This ships through the default and software modules; desktop-only
imports do not enable it. Hosts can disable support with
`programs.appimage.enable = false`, or keep explicit appimage-run invocation
by disabling only `programs.appimage.binfmt`. See
[AppImage usage](../docs/customization.md#appimages).

The native customization check verifies default scope, package inclusion,
both registrations, and opt-out. All-system flake evaluation passed. The exact
x86 runner package built and successfully extracted/executed a locally compiled
type-2 AppImage containing an AppRun script; an argument with spaces arrived
intact. Test cache/artifacts stayed under ignored .local/. No live binfmt
registration or OS activation was performed, and ARM runtime was not tested.
Apps must match the machine architecture; this does not add CPU emulation.

Shine multi-monitor update (2026-11-04): `compositor-drm` is an x86-64 NixOS VM
check with two virtio GPU outputs. It booted Shine through greetd, rendered real
clients, moved windows, changed a single output scale, and resumed after a VT
round trip. The packaged nested session retained terminal/launcher/logout and
parent environment preservation. The user subsequently confirmed both physical monitors working
(2026-11-04), with the automatic horizontal arrangement in the wrong order.
This is user-confirmed hardware behavior, separate from the VM checks above.
Saved output positioning is now implemented; see the output-settings update below.

The stronger native VM test also passed real libinput keyboard input,
Super+period monitor focus, Ctrl+Alt+F2, and page flips after returning to VT1.
The VM must enable polkit just like the shared desktop: logind's SwitchTo
request otherwise fails even though root chvt works. Keep VM waits bounded.

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
