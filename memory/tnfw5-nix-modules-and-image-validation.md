---
data:
  area: nix
  kind: workflow
  reviewed: "2026-11-04"
  status: current
id: tnfw5
title: Nix modules and image validation
---
# Official Ohmansy configuration

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

The Quickshell user service must include standard system and per-user profile
bin directories in its path. A helper-only service PATH silently prevented
desktop entries with bare Exec names (nautilus and nixos-help) from starting.
Use systemd %h and %u specifiers, not account-specific paths. On 2026-11-02
the installed build passed, the new unit was hot-loaded, its process PATH
resolved both commands, and menu launches created Nautilus Home and Firefox
NixOS Manual windows. Updating QML alone cannot fix a service environment.

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
Pastel Powerline only sets segment backgrounds upstream, so its text inherited
black in light terminals. fish-style.nix now supplies explicit #f5f5f5 text for
all preset segments, preserving the user's preferred dark-mode look. Defaults
remain overridable and apply only when this preset is selected. Both actual
light/dark terminal previews verified consistent lettering after activation.

Module layering (2026-11-02): default.nix composes desktop.nix and software.nix.
The public flake exports default, desktop, software, and vm modules. Factory,
live, and newly generated installer hosts use the combined module. Direct
desktop imports now omit optional software; existing hosts wanting the full
bundle must import default instead. software.nix uses standard Firefox/Fish
enable options with mkDefault and a replaceable ohmansy.software.packages list.
Fish's login-shell preference applies only while enabled; first-boot setup
receives the configured shell instead of hardcoding Bash.

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
