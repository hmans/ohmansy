# ohmansy

**ohmansy** is a NixOS desktop built around Shine. **try ohmansy** is its native
macOS host, with an accelerated guest display and a persistent private VM disk.

Quickshell supplies a shared launcher for Shine and Niri. Press Mod+Space or
click **ohmansy** in the bar to search open windows, applications and desktop commands together.
Matching open windows appear first; selecting one switches to that window,
including on another workspace or monitor.
Search accepts abbreviations, with exact names and prefixes ranked first. Use
arrows and Enter to open a result; Escape, Mod+Space, or an outside click closes
the launcher. The first commands open Displays or a terminal and select light or
dark appearance. Its internal providers contribute items to one shared search;
external extensions and nested views are not implemented yet. Search for
**Notifications** to open notification history and Do Not Disturb.

Quickshell supplies the per-monitor panel, workspace buttons, clock, audio
controls, network status, and system tray. Its QML files are in
`nix/modules/desktop/quickshell/`. The shared launcher source is in
`nix/modules/launcher/`, using the existing `Ohmansy.Ui` design system.
`nix/modules/notifications/` supplies notifications, history, and Do Not Disturb
for both shells with the same shared components. The panel runs as a user
service tied to the Niri session.

Fish is the default interactive shell. Hosts and individual accounts can
override the shell through the standard NixOS user options.

Quickshell also supplies the login screen, backed by greetd and PAM. It runs
in a separate Niri greeter session, then starts the selected user's desktop.
The greeter source is in `nix/modules/greeter/`.
Its session picker defaults to **Shine (experimental)**, with **ohmansy (Niri)**
also available. See
[compositor sessions and development](docs/compositor-development.md).
Both shells share the `Ohmansy.Ui` components in `nix/modules/ui/`, including
glass surfaces, controls, icons, and transitions. Niri supplies background
blur behind the desktop popups. The menu bar has a transparent background.
The desktop wallpaper currently reuses the login screen's animated ribbons,
displayed by a separate Quickshell user service in Niri and by Shine's
Quickshell shell in the experimental session.
In Niri, the ribbons ease sideways when the active window column changes and shift
vertically when the active workspace changes. Niri keeps the wallpaper
in a stationary backdrop, so it does not slide with the workspace itself.
This parallax follows focus destinations,
not continuous touchpad gesture positions.
The image in `nix/modules/desktop/wallpapers/` is the fallback when the ribbon
renderer cannot run.

The app is independently implemented and inspired by
[Try Omarchy](https://github.com/omacom/try-omarchy). Development builds package a
pinned copy of its QEMU/VirGL engine. The official Ohmansy flake does not depend
on the separate, ignored `flakey/` reference repository.

## Repository layout

| Path | Responsibility |
| --- | --- |
| `app/Sources/`, `app/Tests/` | Swift app and tests; package manifest in `app/` |
| `app/native/` | Cocoa runtime adapter and Metal welcome animation |
| `app/resources/` | Icon Composer source, plists, and entitlements |
| `app/runtime/` | Python VM lifecycle code shipped inside the app |
| `app/legacy/guest/` | Guest integration for the original development backend |
| `nix/modules/` | Reusable desktop, VM, first-boot, and installer modules |
| `nix/profiles/` | Factory, live, and installer compositions |
| `tools/dev/` | SSH source transfer, guest builds, and isolated ISO tests |
| `tools/build/` | App bundling, engine staging, icons, and signing |
| `tools/release/` | Image packaging, manifests, and source archives |
| `tools/tests/` | Python tooling and guest-setup regression tests |
| `nix/compositor/` | Shine, the experimental scrolling Wayland compositor |
| `experiments/` | Spatial rendering prototypes |
| `docs/` | Development workflows and architecture |
| `memory/` | Means collection of durable engineering findings and lessons |
| `.local/`, `.build/`, `dist/` | Ignored local state, build cache, and artifacts |

Keep accounts, keys, and disk identities out of reusable modules. Desktop assets
live beside their module, for example `nix/modules/desktop/niri.kdl`. The root
flake exports public modules and build outputs; profiles compose them without
embedding personal configuration.

## Build the Mac app

Use Apple Silicon, macOS 15 or later, Xcode with Swift 6 or later, Homebrew
Python 3, and Try Omarchy 1.2.0 (464) installed in `/Applications`. The engine is
checksum-pinned. Nix is not required on the Mac.

A packaged factory must already exist at `dist/factory-preview/`. See
[Ohmansy development](docs/ohmansy-development.md) to build and package it.

```sh
make test
make build
open dist/Ohmansy.app
```

`make run` builds and opens the same app. Shut down and quit it before replacing
its bundle. To validate a build while that app remains running:

```sh
make build APP_BUNDLE=dist/check/Ohmansy.app
```

Use `FACTORY_DIR=/path/to/package` to select another packaged factory. App builds
consume that artifact; they do not build NixOS or replace an existing guest disk.
Builds use local signing and are not notarized distribution builds.

Use `mise run clean --dry-run` to preview local artifact cleanup, then
`mise run clean` to remove unused build outputs. VM disks and the current app
are preserved. See [cleanup options](docs/ohmansy-development.md#clean-local-artifacts)
for explicitly retiring old test VMs.

## Build the OS

For development directly on a Linux PC or inside the macOS VM, see
[Linux development](docs/linux-development.md). Both architectures provide
`nix develop`, desktop previews, and native flake checks; no Mac host or SSH
bridge is needed when commands already run inside Linux.

On ARM or x86-64 Linux, including a development VM:

```sh
make flake-check
make vm-image
```

The root flake also provides `.#iso` for a disposable live desktop and
`.#installer-iso` for the experimental installer. The primary app uses the
persistent factory disk, with first-boot owner setup and no preset credentials.
The x86-64 installer bundles a prebuilt desktop for offline installation. It has
been built locally and tested through disk installation, UEFI boot, graphical
owner setup, and desktop login in QEMU with no network adapter. See
[local installer testing](docs/linux-development.md#test-the-installer-locally).
Physical hardware installation remains unverified.

For an Intel/AMD PC, the x86-64 outputs are `.#iso` and `.#iso-nvidia`
(NVIDIA Turing and newer, including RTX 3060 Ti). These are disposable live
USB desktops with no Ohmansy installation action. See
[PC live images and USB testing](docs/ohmansy-development.md#try-the-pc-image-from-usb).
For the setup wizard and a persistent account in a Linux VM, use `.#vm-image`;
see [persistent VM setup](docs/linux-development.md#boot-the-setup-wizard-in-a-persistent-vm).

Use SSH for guest commands and file transfer. Never type or paste commands into
terminal windows through computer automation. Development SSH access belongs to
a local guest overlay and is excluded from product images.

## Further reading

- [Agent instructions](AGENTS.md) and [engineering memory](memory/MEANS.md):
  session workflow and project knowledge. Start with `means list --path memory`.
- [Ohmansy development](docs/ohmansy-development.md): flake outputs, SSH builds,
  image packaging, and release work.
- [Keyboard shortcuts](docs/keyboard-shortcuts.md): navigation, layout, desktop
  menus, screenshots, and media controls.
- [Customizing Ohmansy](docs/customization.md): module selection, optional software,
  and terminal and shell defaults.
- [Updating Ohmansy](docs/updates.md): pinned releases, local configuration,
  update preparation, and recovery.
- [Graphics integration](docs/graphics.md): the accelerated runtime and input.
- [Original Virtualization backend](docs/legacy-virtualization.md): the retained
  `--original-vm` backend, including its clipboard integration.
- [Earlier guest setup](docs/guest-development.md): historical personal-builder
  configuration; not the official product.

The accelerated app shares plain text with the logged-in guest desktop. Copy
normally on the Mac, then use **Ctrl+V** in guest apps or **Ctrl+Shift+V** in Foot.
Command remains the desktop modifier. Images and files are not shared. Both the
app and guest need the clipboard integration; replacing the app alone does not
update an existing guest. See [clipboard details](docs/graphics.md#text-clipboard).

GPU acceleration, Niri login, guest rebuilds, and cursor handling have been
verified in the development VM. Accelerated audio, remote factory
updates, reproducible engine builds, and public Mac distribution remain work
in progress. The CI workflow builds factory artifacts but does not publish them.
