# Building Ohmansy

The root flake defines the official system. The ignored `flakey/` checkout is
reference material only. Its old personal VM has been deleted. Use the official
development guest, a native Linux PC, or matching CI runner for builds; personal
configuration is not a product input. For a coding agent or terminal running
directly on Linux, start with [Linux development](linux-development.md).

## Clean local artifacts

Run these commands from the repository root:

```sh
mise run clean --dry-run
mise run clean
```

The task removes `.build/`, old `dist/Ohmansy-before-*.app` and
`dist/Ohmansy.before-*.app` bundles, `dist/*-check`, `dist/*-update`,
`dist/check/`, `dist/releases/`, and `dist/images/`. These release and image
directories are local build outputs; move any artifacts you need to retain
elsewhere first. The current `dist/Ohmansy.app`, `dist/factory-preview/`, all
VM state, SSH keys, source, and personal configuration remain in place.
The next build recreates the build cache.

To permanently remove a retired factory VM, select its directory name explicitly:

```sh
mise run clean --dry-run --retire-vm OLD-VM
mise run clean --retire-vm OLD-VM
```

`OLD-VM` must be directly under `.local/`. This deletes that VM's accounts and
files as well as its disk. Repeat `--retire-vm` to select more than one VM.
Routine cleanup never selects VM disks automatically.

The tool checks process paths, open files, and VM locks. It skips artifacts in
use and fails if process inspection is unavailable. Do not start builds or
launch the selected VMs during cleanup. Symlink targets are not accepted.
Allocated totals can exceed the space recovered because APFS clones and
snapshots can share blocks. The task reports the host free-space change too.
It does not run guest Nix garbage collection or change system generations.

Without mise, use `python3 tools/dev/clean.py` with the same arguments.

## Shared system and image targets

| Output | Purpose |
| --- | --- |
| `nixosModules.default` | Desktop plus optional software defaults |
| `nixosModules.desktop` | Niri, Quickshell, desktop services, and terminal integration |
| `nixosModules.software` | Optional Firefox, Fish, and command-line tools |
| `nixosModules.vm` | Virtio, shutdown, display scale, and software cursor |
| `nixosModules.development` | Opt-in SSH and sudo rules for an existing owner |
| `nixosConfigurations.appliance` | Persistent VM with first-boot account setup |
| `packages.aarch64-linux.vm-image` (default) | Compressed raw UEFI factory disk |
| `packages.aarch64-linux.iso` | Disposable live desktop without an installer |
| `packages.aarch64-linux.installer-iso` | Experimental whole-disk installer |
| `devShells.{aarch64,x86_64}-linux.default` | Git, Nix tools, Python, ripgrep, and Niri |
| `packages.{aarch64,x86_64}-linux.desktop-shell` / `wallpaper` | Desktop wrappers for local iteration |
| `packages.{aarch64,x86_64}-linux.greeter-preview` / `first-boot-preview` | Safe graphical previews |

PC live images are separate from the ARM VM and installer:

| Output | Purpose |
| --- | --- |
| `packages.x86_64-linux.iso` | Generic Intel/AMD PC live desktop |
| `packages.x86_64-linux.iso-nvidia` | PC live desktop with NVIDIA drivers for Turing and newer GPUs |

The NVIDIA image uses the open kernel module and matching proprietary
userspace driver from locked Nixpkgs. The RTX 3060 Ti is in this supported
hardware generation. Physical GPU operation still requires a boot test;
configuration checks and an ISO build do not prove that it works on a PC.
Neither PC image imports the VM clipboard service, 200% VM scale, or
software-cursor setting. Both use the same desktop and software modules as the VM.
The PC live profile defaults to dark mode through an unlocked dconf database.
Its `ohmansy-live-scale` user service sets all connected displays to 125% once
at session startup through Niri IPC, before the panel and wallpaper start.
The bar can still switch to light mode. Display scale can be changed for the
session with `niri msg output DP-1 scale 1.5` (use names from `niri msg outputs`).
Displays attached later retain Niri's automatic scale; rerun
`systemctl --user restart ohmansy-live-scale.service` to set all to 125% again.
These defaults belong to the PC live image and do not alter installed users or VM scaling.

On an x86-64 Linux builder:

```sh
nix build --no-update-lock-file .#iso-nvidia
python3 tools/release/package-iso.py --iso result/iso/*.iso \
  --output dist/live-pc --architecture x86_64-linux --kind live --graphics nvidia
```

The `pc-live` CI job builds this NVIDIA variant and uploads the
`ohmansy-x86_64-nvidia-live-preview` artifact with a seven-day retention period.
It contains the ISO, SHA256 checksums, source archive, lock file, and manifest.

### Try the PC image from USB

1. Download and extract the CI artifact. Verify the ISO against `SHA256SUMS`.
2. Write the ISO as a disk image to a USB drive. This erases that USB drive;
   copying the ISO into an ordinary filesystem is not sufficient.
3. Boot the USB through the PC's one-time UEFI boot menu. This preview is not
   Secure Boot signed, so Secure Boot must be disabled to boot it.
4. The local `nixos` live account opens the desktop automatically. Try display
   resolution, keyboard shortcuts, the launcher, Firefox, audio, networking,
   and shutdown. `nvidia-smi` can confirm the NVIDIA driver sees the GPU.

This is a disposable live session: changes are lost on restart. There is no
Ohmansy installation action and no automatic internal-disk installation.
Internal disks can still be accessed manually through ordinary Linux tools.
Remove the USB after shutdown to return to the existing OS. Persistent PC
installation is a separate milestone; the current installer remains ARM-only.

The primary product follows Try Omarchy's [factory-disk model](https://github.com/omacom/try-omarchy/blob/main/docs/architecture.md):
ship a preinstalled system and keep a private writable disk between launches.
App updates must not replace that disk. The guest owns its OS updates.

The factory has no preset owner or enabled SSH service. First boot opens a
Quickshell setup flow with the shared ribbons and glass controls. It asks for a
display name, username, and confirmed password, then returns to the login screen.
The UI runs as the unprivileged greeter. A socket-activated root service checks
the peer identity, validates the request, and passes the password to `chpasswd`
through standard input. Passwords are not stored in Nix source or command arguments.
Setup resumes a pending account after interruption. The owner has
password-protected sudo. Boot status messages stay out of the setup screen.

Use `nix run .#first-boot-preview` on either Linux architecture for a standalone visual preview
that does not create accounts. `PREVIEW_PAGE` selects `welcome`, `identity`,
`password`, or `done`; `PREVIEW_WIDTH` and `PREVIEW_HEIGHT` set its size.

The factory seeds editable configuration in `/etc/nixos`. After setup:

```sh
sudo nixos-rebuild switch --flake /etc/nixos#ohmansy
```

New installations import a pinned Ohmansy release with local machine, owner,
hardware, and preference modules, not the image builder or setup service.
See [Updating Ohmansy](updates.md) for release preparation and boot selection.
For physical hardware, import the default module with the machine's
hardware configuration and accounts; do not import the VM disk layout.
See [Customizing Ohmansy](customization.md) for package, shell, and terminal choices.

The live ISO has a separate disposable `nixos` account with autologin and local
passwordless sudo. Never activate `.#live` on an installed system. The experimental
installer asks for explicit whole-disk erase confirmation and needs networking.
It is not yet an end-to-end verified installation product.

## Shared Quickshell components

The default desktop wallpaper is bundled at
`nix/modules/desktop/wallpapers/twilight-cat.png`. The desktop module installs
it as `/etc/ohmansy/wallpaper.png`, so factory and ISO builds include it without
a download. `ohmansy-wallpaper.service` runs swaybg with aspect-preserving fill
and follows the Niri session. Override the file's NixOS `source` option to use
another image. Fill may crop the edges to fit the display.

`nix/modules/ui/` is the `Ohmansy.Ui` QML module. It supplies shared theme
values, GlassSurface, GlassButton, GlassField, IconButton, FadeSwitch, and
StaggeredEntrance. Keep authentication, power commands, and desktop service
state in their consumers. The small greeter wrappers preserve local control
names while using the shared implementations.

`quickshell-ui.nix` packages the module. Both `greeter-package.nix` and
`desktop-package.nix` add it to `QML_IMPORT_PATH`; use their wrappers when
running a shell or preview. `nix build .#desktop-shell` builds the desktop
wrapper without an OS image build. Import components with `import Ohmansy.Ui`
or use an alias when the consumer has its own Theme type.

`Ui.ColorPalette` supplies semantic desktop colors: surface, text, secondary
text, borders, focus, hover, and selection. Surfaces use white in light mode and
`#202020` in dark mode, both at 85% opacity. It follows `Qt.styleHints.colorScheme`
(unknown falls back to light); consumers can set `dark` explicitly for previews.
The desktop shell defaults to Qt's `xdgdesktopportal` platform theme so the guest
appearance preference and live changes reach Qt. The bar and launcher use
these tokens. Pass `colors` to shared GlassSurface and GlassField;
their existing login-screen defaults remain available when no palette is passed.

The menu bar's sun/moon icon toggles Light and Dark directly. It saves
the current user's `org.gnome.desktop.interface color-scheme` preference through
a packaged GSettings helper. An unset preference is shown as Light. One
shared AppearanceState monitors external changes and supplies the selected option
to every bar. Supporting applications, shell surfaces, and Foot update live.
The speaker icon toggles mute; scrolling over it or using the inline slider
adjusts volume. Neither control opens a popup. Device selection remains under
Desktop Controls → Sound. The date has no hover tooltip.
The transparent bar uses the `onWallpaper` palette: its text and icons fade with
the animated wallpaper between light and dark modes. Menus retain the system palette.
`Ui.Appearance` supplies the shared 150 ms InOutCubic transition. The desktop
ribbons use muted blue-gray light backgrounds, advance at 15% of the original
launcher speed, and target 15 FPS. During appearance transitions they briefly
target 60 FPS. The login scene keeps its separate 30 FPS and 60% motion defaults.

Window outlines follow the same appearance preference. Quickshell writes the
selected `desktop/niri-light.kdl` or `desktop/niri-dark.kdl` palette atomically to
`~/.local/state/ohmansy/niri-appearance.kdl`. The system Niri configuration includes
that file optionally and reloads when it changes. Light mode uses dark slate
outlines; dark mode uses pale translucent outlines. Custom Niri configurations
must include the generated file to use this integration.

The menu bar uses GlassSurface with no sheen and a half-point rim. The shared
surface exposes tint and sheen independently of its default button styling.
Niri 26.04 supplies background blur through the
`ohmansy-bar` and `ohmansy-launcher` layer rules in `desktop/niri.kdl`.
The bar uses cached wallpaper blur (`xray true`). The launcher uses `xray false`
so underlying windows remain visible, but this path still produces no visible
blur in the virgl guest. QML BackgroundEffect.blurRegion explicitly follows each
glass surface, including rounded menu corners. Do not blur
the launcher's full-screen transparent click catcher.
Only the surface is translucent;
text and icons stay opaque. The greeter instead supplies a shared blurred
texture to GlassSurface because it owns its ribbon background. Do not capture
desktop windows into the QML surface to simulate compositor blur.

The application launcher lives in `desktop/quickshell/Launcher.qml` and uses
the same GlassSurface and GlassField. It reads installed desktop entries,
filters names, descriptions, and keywords, and passes desktop-entry IDs to
GTK's `gtk-launch` (GIO). GIO handles D-Bus activation, Exec field codes, and
working directories. `xdg-terminal-exec` selects terminal applications, with
Foot as the system default; users can override `xdg-terminals.list`. Keep the
standard profile paths in the shell service so bare Exec names resolve.
The packaged helper starts an independent systemd user scope so shell restarts
do not terminate launched apps. It routes app output to the journal (`ohmansy-app-launch`)
instead of QProcess pipes that close when the launcher exits. The menu reports
launch-request failures; a successful request cannot guarantee the app will
not crash later. The bar button and Mod+Space toggle it through the shell's `launcher`
IPC target. Its overlay takes keyboard focus only while open; Escape and an
outside click dismiss it. A layer surface is required here: a grabbing popup
cannot reliably open from IPC without a recent input event on its parent.

Foot uses dark gray and white background palettes at 85% opacity, opaque text,
and 16×14 padding. New terminals read the appearance portal before starting;
dark selects the dark palette, while light or no preference selects light.
Quickshell sends Foot's theme-switch signals to the current user's terminals
when the desktop preference changes and when the shell starts. Foot servers
also update their clients. Ctrl+Shift+T provides a manual override until the
next desktop preference change or shell restart.
Foot requests native blur, and its Niri window rule selects cached wallpaper
blur (`xray true`), including when floating above another window. Configure the
palettes and the compositor rule in `terminal.nix`. These settings and the theme
signals apply only when the selected terminal package is Foot.

## Login screen

`nix/modules/greeter.nix` configures greetd and a separate Niri compositor for
the Quickshell login screen. This compositor has no desktop shortcuts or user
panel services. It exits after greetd accepts the authenticated session; the
user's `niri-session` then starts the desktop and its services.

PAM handles authentication and unlocks GNOME Keyring. The greeter clears its
response field after submission, failure, or account changes. It supports
additional PAM prompts and cancels the previous conversation when switching
accounts. Installed systems reject empty passwords. Only disposable live
profiles enable autologin and permit their passwordless live account.

First-boot setup must complete before `greetd.service` starts on tty1. The VM
module applies scale 2 and Niri's composited cursor to the greeter as well as
the desktop. Physical systems retain their own output scaling.

For appearance changes, run this preview inside a graphical guest session:

```sh
nix run .#greeter-preview
```

The preview cannot authenticate or perform power actions. Set `PREVIEW_WIDTH`
and `PREVIEW_HEIGHT` to test small windows. With `QT_QPA_PLATFORM=offscreen`
and `PREVIEW_IMAGE=/absolute/path.png`, it saves a screenshot and exits.

The background ports the macOS launcher's `app/native/Welcome.metal` animation
to OpenGL/VirGL. `greeter/ribbons/` contains the native `Ohmansy.Welcome` QML
plugin and GLSL shaders. Keep its ribbon paths, noise, lighting, particles,
and depth prepasses aligned with the Metal source. `scene/Ribbons.qml` starts
at the same 12-second pose and renders at 30 fps, with motion at 60% of the
launcher's speed. Its render texture is limited
to 2400 pixels wide while preserving aspect ratio; controls retain native DPI.
Authentication stops animation without resetting its phase. The login screen
has no motion toggle; the preview can still freeze motion for visual checks.
The greeter wrapper adds the plugin's QML import path, so shader changes build
the small plugin without recompiling Quickshell. The desktop package is unchanged.

`GlassSurface.qml` supplies the fields, buttons, and account menu. One shared
half-resolution blur samples only the background scene; each control crops and
masks that texture to its rounded shape. Labels and password input are never
part of the blur source. Translucent tint and a half-point rim that brightens on focus
keep the glass subtle and the controls readable. The software backend uses a
more opaque fill. Sample coordinates update with form layout and scrolling.

`StaggeredEntrance.qml` shares one startup timeline across the form elements.
`FadeSwitch.qml` fades out the current page before switching to the requested
page and fading it in (180 ms sine exit, 360 ms quintic entrance). Controls are
disabled during the transition, but their visual dimming is independent of
that input lock: inherited disabled styling would cause a brightness jump at
the end of the fade. One lower-right power icon opens a menu with Restart,
Shut down, and Cancel. The menu focuses Cancel; returning to login restores
field focus. Only the two explicit power actions can start systemctl. Static mode
skips both animations. Use `PREVIEW_TRANSITIONS=1` with the preview package to
exercise the dialog and return path without real power actions.

Set `OHMANSY_GREETER_STATIC=1` to use the static ribbon drawing. Non-OpenGL
scene-graph backends, a failed plugin import, and renderer initialization errors
also retain that fallback. The native renderer requires desktop OpenGL 3.3;
the greeter explicitly selects Qt's OpenGL backend.
If Quickshell exits with an error, the greeter launcher retries once with the
static background. This does not recover from a broken compositor or driver.
Qt's shader cache lives in the greeter's runtime directory.

For visible GPU measurements, use `PREVIEW_FULLSCREEN=1 PREVIEW_STATS=1
nix run .#greeter-preview` in a Wayland session. The full-screen preview has
no authentication or power actions. Set `PREVIEW_IMAGE` and `PREVIEW_DELAY`
(milliseconds) to capture and exit automatically; set `PREVIEW_MOTION=0` to
check the paused state. Hidden windows can be throttled by the compositor,
so their frame-rate readings do not represent visible rendering performance.
Set `PREVIEW_KEYBOARD=1` for keyboard checks in the full-screen preview; use
an automatic capture deadline so it releases keyboard focus when the test ends.

`nix flake check --all-systems` includes real Quickshell-to-greetd protocol
tests against an isolated test socket. These cover account switching, failed
password retry, additional prompts, response-log redaction, and session launch.
They do not replace a real password login, logout, and keyring check. Use boot
activation for login-manager changes and retain the previous generation.

The greeter uses a scoped Quickshell 0.3.0 patch in `greeter-package.nix`.
It tracks greetd request replies so a cancellation acknowledgement cannot be
mistaken for successful authentication. A new conversation waits for that
acknowledgement; the protocol test deliberately delays it. The desktop panel
continues to use the unmodified package. Recheck this patch when updating
Quickshell, and remove it when the upstream version passes the same tests.

## Build on ARM Linux

```sh
nix develop
nix flake check --no-update-lock-file
nix build --no-update-lock-file .#vm-image
```

The result is `result/*.raw.zst`. systemd-repart builds it without nested
virtualization. Allow at least 25 GiB free for image assembly in addition to
Nix dependencies. Use `path:.#vm-image` outside Git; add new files to the index
inside Git. Keep the lock file unchanged unless deliberately updating Nixpkgs.

Build `.#iso` or `.#installer-iso` for an ISO under `result/iso/`. Use distinct
`--out-link` names to retain multiple outputs.

To preview Niri changes in a Wayland session, run
`niri --config ./nix/modules/desktop/niri.kdl`. Do not add `--session`, which changes the
parent session environment. Boot tests remain necessary for system services.

## Use the current VM as a builder

SSH must already work with a verified host key. No builder credentials are shipped.
Use SSH for commands and file transfer; never use computer automation to type or
paste into a guest terminal. Keep the development account and SSH configuration
in the guest's local overlay, outside the reusable product modules.

The current factory development VM forwards localhost port 2223 and uses
`.local/ssh/factory-known-hosts`. Port 2222 and `.local/ssh/known_hosts` are legacy
tool defaults for the deleted personal builder; do not use them for this guest.
Check ignored `.local/SESSION.md` for local handoff details, if present.
The `bridge` command below updates a running VM through QMP and saves the
forward for later launcher starts. Older app bundles need an update before
they can read the saved setting.

For the current factory VM, pass `--port 2223 --known-hosts
.local/ssh/factory-known-hosts` to each command below. Replace `USER` with the
guest owner. The default key is `.local/ssh/id_ed25519`; use `--identity` for a
different key. These files are ignored and never included in source archives.

```sh
python3 tools/dev/guest-dev.py sync --host USER@127.0.0.1
python3 tools/dev/guest-dev.py check --host USER@127.0.0.1 --directory /GUEST/PATH
python3 tools/dev/guest-dev.py build --host USER@127.0.0.1 --directory /GUEST/PATH
python3 tools/dev/guest-dev.py fetch --host USER@127.0.0.1 --directory /GUEST/PATH --output dist/images
```

Use the absolute path printed by `sync`. Each sync sends only `flake.nix`,
`flake.lock`, and `nix/` into a new writable snapshot. Guest edits are not replaced.
Use `--target iso` or `--target installer-iso` on both build and fetch for an ISO.
Fetch refuses to overwrite artifacts. For normal development, clone
`https://github.com/hmans/ohmansy.git` inside the guest. No host home share is needed.

For routine guest changes, build a local host configuration that imports the
shared modules and preserves the guest's owner and development overlay. Do not
activate the factory or live profile on an existing installation. Build the
system without sudo, then use sudo to select it for boot. The private development
overlay below permits unattended activation; shipped installations require a password.
Use image builds to test provisioning and releases, not for every desktop edit.

### Opt in to development access

Ohmansy ships `ohmansy-dev`, but development access starts disabled. Update an
older installation before using the command. The command supports the installed
`/etc/nixos` flake generated by Ohmansy. Custom flakes can use the module directly.

On the Mac, select the existing VM state directory and your Ed25519 public key:

```sh
python3 tools/dev/guest-dev.py bridge \
  --state .local/YOUR-VM --port 2223 --public-key .local/ssh/id_ed25519.pub
```

This binds SSH forwarding to `127.0.0.1` and prints the complete command to run
once in the guest. It stores the port in the private VM's `development.json`.
The public key is not stored there. No directory share or guest disk is created.

Run the printed command in your guest terminal:

```sh
sudo ohmansy-dev enable --public-key 'ssh-ed25519 YOUR_PUBLIC_KEY'
```

The command uses the account that invoked sudo. Add `--user USER` to select
another existing normal user, or `--require-password` to retain sudo prompts.
By default, the selected key can connect over SSH and administer the guest
without another password prompt. Password SSH and root SSH remain disabled.

The command adds a marked import and `/etc/nixos/development.nix`. It builds a
candidate configuration before changing the live files, then activates it
without a reboot. It preserves the owner, storage, preferences, and release pin.
Build failures leave the current system alone. Activation failures restore the
saved files and attempt to restore the previous running system and boot selection.
Backups remain in `/var/lib/ohmansy/development`. The command refuses to replace
a manually created or edited development overlay. It shares the release updater's
lock so the two tools cannot change the configuration at the same time.

Compare the printed SSH host-key fingerprint with the key presented by your
first Mac SSH connection before trusting it. Keep strict host-key checking for
later connections. Check status or remove the managed access with:

```sh
ohmansy-dev status
sudo ohmansy-dev disable
```

Disable from the guest terminal because it stops SSH. Remove the Mac forward
separately with `python3 tools/dev/guest-dev.py unbridge --state .local/YOUR-VM`.
Normal release updates preserve the local overlay and use the development module
from the selected release. Updating the Mac app does not enable guest access.

### Configure the module manually

`ohmansy.nixosModules.development` is an optional module. Importing it alone
does nothing. Enable it only in the installed development machine's local
configuration, with an existing owner and your public key:

```nix
{ ohmansy, ... }:
{
  imports = [ ohmansy.nixosModules.development ];
  ohmansy.development = {
    enable = true;
    user = "YOUR_EXISTING_USER";
    authorizedKeys = [ "ssh-ed25519 YOUR_PUBLIC_KEY" ];
    passwordlessSudo = true;
  };
}
```

Keep this file at `/etc/nixos/development.nix`, imported beside `./owner.nix`
in the installed flake. The flake must pass `specialArgs = { inherit ohmansy; };`
to `nixosSystem`, as the current installation template does. Its pinned Ohmansy
release must export `nixosModules.development`. To disable access, set `enable`
to `false` and rebuild; keep the existing owner and storage modules.

The module enables key-only SSH for that owner and, by default, passwordless
sudo. Set `passwordlessSudo = false` to retain password prompts. It creates no
account and changes no disk settings. Anyone with the configured private key
can administer a guest with passwordless sudo enabled.

Generate the local configuration from an existing owner and Ed25519 public key:

```sh
python3 tools/dev/guest-dev.py prepare-access \
  --guest-user USER --public-key .local/ssh/id_ed25519.pub
```

This writes `.local/development-access.nix` with mode 0600 and refuses to replace
an existing file. `--access-output` can select another path under `.local/`.
The generator supplies the local values and imports the shared development module;
it does not contain a second implementation of the SSH and sudo rules.

Transfer the file through an existing trusted SSH connection. Install it as
`/etc/nixos/development.nix` and include `./development.nix` in the installed
host's flake modules beside `./owner.nix`. Preserve any other local settings
when replacing an older development overlay. The first activation requires
the owner's password in their own terminal; never send that password to an agent.
After activation, verify `sudo -n true` over SSH. Later builds and activations
can run unattended. QML preview changes do not need sudo.
For a custom flake without SSH access, activate the local configuration once in
the guest with `sudo nixos-rebuild switch --flake path:/etc/nixos#ohmansy`.
The Mac's loopback forward is separate from the guest module; use `bridge` above.

Development access stays outside the image pipeline:

- The reusable module lives under `nix/modules/development.nix` and is exported
  by the flake, but no product profile imports or enables it. The default module
  ships the inert `ohmansy-dev` command. The host generator and template live
  under `tools/dev/`. Personal account/key configuration lives
  under ignored `.local/`, then on the private guest.
- `sync` and release source archives contain only the root flake, lock, and
  `nix/`. They include the inert module definition but exclude the template and
  generated overlay. No developer identity or key is included in release source.
- Factory, live, and installer image profiles assert that no development marker,
  SSH keys, extra owner accounts, enabled SSH service, or custom sudo rules
  are present. Direct image builds enforce these assertions too. The live
  account's standard local wheel sudo rule remains allowed.
- `nix flake check` tests the disabled module, required owner/key configuration,
  SSH restrictions, and optional sudo grant. It also enables the real module
  in each image profile and requires the image policy to reject it, alongside
  direct-setting rejection tests. Python tests check generation, archive exclusion,
  managed-file ownership, rollback, and the loopback forward's lifecycle.

Build release images from the official image targets. Never package a private
development VM disk as a factory. These checks protect configuration builds;
they do not inspect an arbitrary disk supplied to the packaging tools.

## Package and boot on macOS

The normal app boots the official factory. Open `dist/Ohmansy.app` and click
**Start ohmansy**. On first launch it prepares a persistent disk; subsequent
launches reuse it. Development builds reuse
an existing `.local/factory-preview` VM; otherwise the app creates
`~/Library/Application Support/Ohmansy/FactoryVM`. The selected path is saved
under the separate `factoryVMDirectory` preference.

To build the image bundle and package the Mac app:

```sh
python3 tools/release/package-factory.py --image dist/images/ohmansy-0.1.0-aarch64-linux.raw.zst --output dist/factory-preview
make build
open dist/Ohmansy.app
```

The root Makefile drives `app/Package.swift` and keeps the Swift build cache in
the root `.build/`. `make test` runs Swift, Python, and native adapter tests.
To check packaging without replacing a running app, use
`make build APP_BUNDLE=dist/check/Ohmansy.app`. `FACTORY_DIR` selects a packaged
factory directory; it defaults to `dist/factory-preview`.

Package from the same source used for the image build. The output includes the
image, source archive, manifest, and checksums. Use a new directory per release.
Checksums detect corruption; public downloads also need a trusted release channel
or signed manifest.

The app bundles the factory, graphics helper, and decompressor. It checks the image digest, decompresses sparsely into a new
state directory, and expands the disk to 64 GiB. The guest grows its filesystem
at boot. Later launches reuse the disk. No personal disk or host folder is
attached. SSH forwarding is disabled. Click **Start ohmansy** to boot.

For isolated development tests, use `app/runtime/factory-vm.py --factory
dist/factory-preview --state .local/ANOTHER-VM`. This is optional; users open the app.
Downloading images from a release server is pending; the current app embeds one.
Each new VM is decompressed separately; a shared APFS factory cache is future work.

## Pipeline and release work

`.github/workflows/images.yml` checks and builds the factory on ARM Linux and
the NVIDIA live ISO on x86-64 Linux, then uploads the packaged artifacts.
Actions are pinned; the workflow does not publish
releases. Runs are available in the repository's GitHub Actions tab. A successful
image build still needs a separate boot test.

Verify account setup, login, restart persistence, guest rebuild and rollback,
input, resizing, and clean shutdown before release. The installer needs a separate
installation test. Mac distribution also needs a reproducible engine and its
source/license bundle, removal of the Homebrew Python dependency, download UI,
hardened-runtime validation, Developer ID signing, notarization, and clean-Mac testing.
