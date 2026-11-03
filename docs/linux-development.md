# Develop inside Linux

Use this workflow when the terminal or coding agent runs on the PC itself or
inside the macOS VM. Run commands locally. SSH and `ohmansy-dev enable` are only
needed when another machine must connect. The Mac app still requires macOS to
build; Linux can build and test the desktop and native images.

## Start a session

Clone the full repository onto persistent storage:

```sh
git clone https://github.com/hmans/ohmansy.git
cd ohmansy
git status --short
uname -sm
nix develop
```

`nix develop` opens Bash with Git, Python, ripgrep, Nix formatting/language tools,
and Niri. These commands work on both `x86_64-linux` and `aarch64-linux`.
Read `AGENTS.md`, `README.md`, and the relevant Markdown files in `memory/`.
Means is optional; it is not required to read the notes. Skills and tools from
another agent installation are not assumed to exist here.

Check `/etc/os-release`, `findmnt /`, and `/etc/nixos/flake.nix` if present to
identify the running system. A live ISO uses a temporary writable overlay.
Its home, Nix builds, and unpushed commits can disappear at shutdown. Use an
already mounted persistent filesystem for the checkout; do not format a disk
as part of setup. Ask before pushing, and use the user's normal Git credentials.
The source archive shipped with images contains only the build inputs; use a
full Git clone for tools, documentation, tests, and history.

Create ignored `.local/SESSION.md` for machine-local handoff notes when useful.
Record the checkout, running generation, test commands, and pending work. Do not
copy Mac-specific paths or credentials from another machine. Each agent must
verify the current state again.

## Check and preview small changes

Stage newly added Nix input files so the Git-backed flake includes them. Keep
private configuration and generated artifacts ignored.

```sh
nix flake check --no-update-lock-file
python3 -m unittest discover -s tools/tests -p 'test_*.py'
nix build --no-update-lock-file .#desktop-shell .#wallpaper .#greeter-preview
nix run .#greeter-preview
```

Run graphical previews as the logged-in desktop user, with that session's
Wayland and D-Bus environment. Do not use sudo. The greeter preview cannot
authenticate, reboot, or shut down the machine. `nix run .#first-boot-preview`
previews onboarding without creating accounts. The `ribbons` flake check tests
both desktop OpenGL and ES on a software renderer; it does not replace a GPU test.

For a desktop panel preview, build first, then temporarily replace only its
user service. Run this in the Bash shell opened by `nix develop`:

```sh
mkdir -p .local
nix build --out-link .local/desktop-preview .#desktop-shell
(
  trap 'systemctl --user start quickshell.service' EXIT
  systemctl --user stop quickshell.service || exit
  .local/desktop-preview/bin/ohmansy-quickshell \
    --path "$PWD/nix/modules/desktop/quickshell/shell.qml"
)
```

Stop the preview with Ctrl+C to restore the installed panel. Avoid running two
panels or two wallpaper processes on the same layer. A full OS rebuild is needed
for service definitions and installed defaults, not every QML edit. Inspect
`journalctl --user -b -u quickshell.service -u ohmansy-wallpaper.service` for
installed-service diagnostics. `make test` and `make build` are Mac app commands;
use the Linux checks above here.

## Test an installed system with local sources

This section is for an installed Ohmansy system, including the persistent VM.
It is not for the live USB. Inspect `/etc/nixos/flake.nix` first: the generated
configuration has an `ohmansy` input and a host named `ohmansy`. Custom host
configurations may use different names.

Keep its accounts, disk layout, hardware modules, state version, and local
preferences. Build with a temporary source override from the checkout:

```sh
sudo nixos-rebuild build --flake /etc/nixos#ohmansy \
  --override-input ohmansy "git+file://$PWD" --no-write-lock-file
```

Then, when ready to replace the running services:

```sh
sudo nixos-rebuild test --flake /etc/nixos#ohmansy \
  --override-input ohmansy "git+file://$PWD" --no-write-lock-file
```

This uses tracked working-tree changes without changing the installed release
pin or boot default. The Git URL excludes ignored VM disks and credentials;
do not replace it with a raw directory input that includes ignored files.
The owner enters any sudo password locally, never in chat. Agents use a direct
command tool and must not type commands through terminal UI automation.

To restore the selected system profile after a temporary test:

```sh
sudo /nix/var/nix/profiles/system/bin/switch-to-configuration test
```

Login-manager, kernel, and graphics-driver changes may require a planned boot
activation and restart. Agree on that before ending the user's session.
Never rebuild an installed system from the repository's `live`, `appliance`,
or installer configurations. See [updates](updates.md) for durable release changes.

## Build an image

Build for the machine's native architecture, or use its matching CI runner:

| Builder | Command | Artifact |
| --- | --- | --- |
| x86-64 PC | `nix build .#iso-nvidia` | `result/iso/*.iso` |
| x86-64 PC, generic graphics | `nix build .#iso` | `result/iso/*.iso` |
| x86-64 PC or ARM Linux | `nix build .#vm-image` | `result/*.raw.zst` |
| x86-64 PC or ARM Linux | `nix build .#installer-iso` | `result/iso/*.iso` |
| ARM Linux / macOS guest | `nix build .#iso` | `result/iso/*.iso` |

Check free disk space and RAM first. Avoid full image builds in a live session's
RAM-backed root; use CI or a configured persistent builder. An output link on
persistent storage alone does not move the Nix store out of RAM. Do not wipe a
guest, delete generations, or repartition disks to make room without authorization.
Also check the build workspace: repart image assembly temporarily needs both the
root filesystem and the final disk image. For a single-user Nix build on a host
with RAM-backed `/tmp`, put `TMPDIR` on persistent storage:

```sh
mkdir -p .local/nix-build
TMPDIR="$PWD/.local/nix-build" nix build --no-update-lock-file .#vm-image
```

Building an image does not install it. Report build, runtime, and physical GPU
test results separately. See [image packaging](ohmansy-development.md) for CI artifacts.

## Boot the setup wizard in a persistent VM

Use `.#vm-image` for the graphical first-boot wizard. It creates an owner on an
already installed system; the account and files live on the writable VM disk.
The normal live ISO uses a temporary autologin account. `.#installer-iso` instead
boots the experimental disk installer, which installs onto a separate blank disk.

On an x86-64 host with QEMU, KVM, and OVMF installed, build the factory and make
a private writable copy. Use a new state directory for each fresh setup test:

```sh
nix build --no-update-lock-file --out-link .local/factory-image .#vm-image
mkdir -p .local/setup-vm
zstd --decompress --keep .local/factory-image/*.raw.zst -o .local/setup-vm/disk.raw
chmod u+w .local/setup-vm/disk.raw
qemu-img resize -f raw .local/setup-vm/disk.raw 64G
cp /usr/share/edk2/x64/OVMF_VARS.4m.fd .local/setup-vm/OVMF_VARS.fd
qemu-system-x86_64 \
  -machine q35,accel=kvm -cpu host -smp 4 -m 8192 \
  -drive if=pflash,format=raw,readonly=on,file=/usr/share/edk2/x64/OVMF_CODE.4m.fd \
  -drive if=pflash,format=raw,file=.local/setup-vm/OVMF_VARS.fd \
  -drive if=virtio,format=raw,file=.local/setup-vm/disk.raw \
  -vga none -device virtio-vga-gl -display gtk,gl=on \
  -device qemu-xhci -device usb-tablet \
  -netdev user,id=network -device virtio-net-pci,netdev=network
```

The firmware paths above are for Arch-based hosts; use the matching OVMF code
and variables files supplied by your distribution. Run QEMU as the desktop user.
For later boots, repeat only the QEMU command with the same disk and firmware
variables. Shut down through the guest before closing QEMU. Never replace the
writable disk to update an installed guest; preserve its account and host flake.
The disk grows on first boot, and completed setup leads to the normal login screen.
