# Building Ohmansy

The root flake defines the official system. The ignored `flakey/` checkout is
reference material only. Its old personal VM has been deleted. Use the official
development guest or ARM CI for builds; personal configuration is not a product input.

## Shared system and image targets

| Output | Purpose |
| --- | --- |
| `nixosModules.desktop` | Shared Niri desktop without accounts or disks |
| `nixosModules.vm` | Virtio, shutdown, display scale, and software cursor |
| `nixosConfigurations.appliance` | Persistent VM with first-boot account setup |
| `packages.aarch64-linux.vm-image` (default) | Compressed raw UEFI factory disk |
| `packages.aarch64-linux.iso` | Disposable live desktop without an installer |
| `packages.aarch64-linux.installer-iso` | Experimental whole-disk installer |
| `devShells.aarch64-linux.default` | Git, Nix tools, Python, and Niri |

The primary product follows Try Omarchy's [factory-disk model](https://github.com/omacom/try-omarchy/blob/main/docs/architecture.md):
ship a preinstalled system and keep a private writable disk between launches.
App updates must not replace that disk. The guest owns its OS updates.

The factory has no preset owner or enabled SSH service. First boot asks for a
username and password on the guest console, then starts the Quickshell greeter. Passwords go
directly to `passwd`, not into Nix source. Setup can resume after interruption.
The owner has password-protected sudo.

The factory seeds editable configuration in `/etc/nixos`. After setup:

```sh
sudo nixos-rebuild switch --flake /etc/nixos#ohmansy
```

This imports `persistent-vm.nix` and `owner.nix`, not the image builder or setup
service. For physical hardware, import the shared desktop with the machine's
hardware configuration and accounts; do not import the VM disk layout.

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
appearance preference and live changes reach Qt. The bar, launcher, and audio
popup use these tokens. Pass `colors` to shared GlassSurface and GlassField;
their existing login-screen defaults remain available when no palette is passed.

The menu bar's Appearance popup selects Light or Dark. It saves
the current user's `org.gnome.desktop.interface color-scheme` preference through
a packaged GSettings helper. An unset preference is shown as Light. One
shared AppearanceState monitors external changes and supplies the selected option
to every bar. Supporting applications, shell surfaces, and Foot update live.

The menu bar uses GlassSurface with no sheen and a half-point rim. The shared
surface exposes tint and sheen independently of its default button styling.
Niri 26.04 supplies background blur through the
`ohmansy-bar` and `ohmansy-launcher` layer rules in `desktop/niri.kdl`.
The bar uses cached wallpaper blur (`xray true`). The launcher uses `xray false`
so underlying windows remain visible, but this path still produces no visible
blur in the virgl guest. QML BackgroundEffect.blurRegion explicitly follows each
glass surface, including rounded menu corners and the audio popup. Do not blur
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
palettes in `desktop.nix` and the compositor rule in `desktop/niri.kdl`.

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
The factory forwarding currently comes from QMP and
must be restored if the host engine exits; a guest reboot preserves it.

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

Generate an overlay for an existing guest owner and an Ed25519 public key:

```sh
python3 tools/dev/guest-dev.py prepare-access \
  --guest-user USER --public-key .local/ssh/id_ed25519.pub
```

This writes `.local/development-access.nix` with mode 0600 and refuses to replace
an existing file. `--access-output` can select another path under `.local/`.
The overlay enables key-only SSH for that account and passwordless sudo. The
account and anyone with its SSH key can administer this development VM.
It does not create an owner or change storage.

Transfer the file through an existing trusted SSH connection. Install it as
`/etc/nixos/development.nix` and include `./development.nix` in the installed
host's flake modules beside `./owner.nix`. Preserve any other local settings
when replacing an older development overlay. The first activation requires
the owner's password in their own terminal; never send that password to an agent.
After activation, verify `sudo -n true` over SSH. Later builds and activations
can run unattended. QML preview changes do not need sudo.

Development access stays outside the image pipeline:

- The generator and template live under `tools/dev/`. Generated account/key
  configuration lives under ignored `.local/`, then on the private guest.
- `sync` and release source archives contain only the root flake, lock, and
  `nix/`. They exclude both the template and generated overlay.
- Factory, live, and installer image profiles assert that no development marker,
  SSH keys, extra owner accounts, enabled SSH service, or custom sudo rules
  are present. Direct image builds enforce these assertions too. The live
  account's standard local wheel sudo rule remains allowed.
- `nix flake check` includes negative tests that inject development settings
  and require the image policy to reject them. Python tests check generation
  and archive exclusion.

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

`.github/workflows/images.yml` checks and builds the factory on ARM Linux, then
uploads the packaged artifacts. Actions are pinned; the workflow does not publish
releases. Runs are available in the repository's GitHub Actions tab. A successful
image build still needs a separate boot test.

Verify account setup, login, restart persistence, guest rebuild and rollback,
input, resizing, and clean shutdown before release. The installer needs a separate
installation test. Mac distribution also needs a reproducible engine and its
source/license bundle, removal of the Homebrew Python dependency, download UI,
hardened-runtime validation, Developer ID signing, notarization, and clean-Mac testing.
