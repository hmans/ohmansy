# Building Ohmansy

The root flake defines the official system. The ignored `flakey/` checkout is
reference material only. Its VM can serve as an ARM builder, but its accounts,
configuration, and disk are not inputs to the product.

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
username and password on the guest console, then starts SDDM. Passwords go
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
`.local/ssh/factory-known-hosts`. The older personal builder uses port 2222 and
`.local/ssh/known_hosts`. The factory forwarding currently comes from QMP and
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
Fetch refuses to overwrite artifacts. Once a remote exists, clone the repository
inside the guest for normal development. No host home share is needed.

For routine guest changes, build a local host configuration that imports the
shared modules and preserves the guest's owner and development overlay. Do not
activate the factory or live profile on an existing installation. Build the
system without sudo, then use password-protected sudo to select it for boot.
Use image builds to test provisioning and releases, not for every desktop edit.

## Package and boot on macOS

The normal app boots the official factory. Open `dist/Ohmansy.app` and click
**Start ohmansy**. On first launch it prepares a persistent disk; subsequent
launches reuse it. The old personal VM stays untouched. Development builds reuse
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
releases. Hosted CI has not run because this repository has no remote.

Verify account setup, login, restart persistence, guest rebuild and rollback,
input, resizing, and clean shutdown before release. The installer needs a separate
installation test. Mac distribution also needs a reproducible engine and its
source/license bundle, removal of the Homebrew Python dependency, download UI,
hardened-runtime validation, Developer ID signing, notarization, and clean-Mac testing.
