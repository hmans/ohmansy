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

For a live browser, editor, and terminal with fixed 2x rendering, run
`mise run compositor-desktop`; see
[Shine development](compositor-development.md). The separate
[spatial lab](spatial-lab.md), launched with `mise run spatial`, explores 3D
presentation using window captures. Both run inside the current desktop without
rebuilding or activating the OS.
Shine is also available as **Shine (experimental)** in the updated
login screen. `nix run .#compositor-session -- --nested` previews that packaged
session, including its normal terminal, app picker, and sign-out confirmation.

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

Use `mise run display-ui` (or `nix run .#display-preview`) to preview display
controls with simulated monitors. It cannot change the current displays.
`nix build .#checks.x86_64-linux.displays-ui` checks the selection and
confirmation flow and renders wide, narrow, short, pending, empty, and error
states. The equivalent check is also available on `aarch64-linux`.

Implement shared OS and desktop changes in the repository's reusable modules,
packages, and defaults. This makes them part of ohmansy for future builds and
installations. Local activation tests those source changes on your machine;
editing only `/etc/nixos` or runtime files does not put a change into ohmansy.
Keep hardware, disks, accounts, and personal preferences in the machine's
configuration. Existing installations receive shared changes when rebuilt or
updated; activating this machine does not update other installations.

This section is for an installed Ohmansy system, including the persistent VM.
It is not for the live USB. Inspect `/etc/nixos/flake.nix` first: the generated
configuration has an `ohmansy` input and a host named `ohmansy`. Custom host
configurations may use different names.

Keep its accounts, disk layout, hardware modules, state version, and local
preferences. Build with a temporary source override from the checkout:

```sh
mise run os-build
mise run os-test
# Select for the next boot, keeping the current session running:
mise run os-boot
# Or activate immediately and select for future boots:
mise run os-switch
```

These tasks use `/etc/nixos#ohmansy` and override its `ohmansy` input with this
checkout. They leave the installed release pin and lock file unchanged. `os-build`
only builds; `os-test` activates without changing the boot default; `os-boot`
selects the build for the next boot without activating it now; `os-switch`
activates and changes the boot default. Reboot when ready after `os-boot`.
Test and switch may restart services.
Use a planned boot activation and restart for login-manager, kernel, or
graphics-driver changes, as described below.

Inspect a command without building or activating with `mise run os-test -- --dry-run`.
For a custom installed configuration, set `OHMANSY_SYSTEM_FLAKE`, for example:

```sh
OHMANSY_SYSTEM_FLAKE=/path/to/machine-config#my-host mise run os-build
```

Mise is optional: `bash tools/dev/os-rebuild.sh build` (or `test` / `boot` / `switch`)
runs the same helper. The equivalent build command is:

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

### Test the installer locally

The `Ohmansy images` CI workflow also builds the generic x86-64 offline installer.
Download `ohmansy-x86_64-installer-preview` from its completed `installer` job;
the artifact includes the ISO, source archive, manifest, lock file, and checksums.
CI verifies assembly and packaging; the VM procedure below verifies installation.

Build the installer on this host, then boot it with a new, isolated 64 GiB VM
disk. No CI job, USB stick, or host reboot is involved:

```sh
nix build --no-update-lock-file --out-link .local/installer-result .#installer-iso
python3 tools/dev/linux-iso-vm.py \
  --iso .local/installer-result/iso/*.iso --state .local/installer-test --no-network
```

The Linux launcher needs x86-64 QEMU, KVM, and OVMF. Its default firmware paths
match Arch-based hosts; pass `--firmware-code` and `--firmware-vars` on other
distributions. It refuses to create a disk in an existing state directory.
No host directories or host disks are shared with the VM.

In the live desktop, choose **Install ohmansy**. The graphical installer offers
the VM disk and asks for a computer name. Review the disk, tick the erasure
acknowledgement, then choose **Erase disk and install ohmansy**. The ISO contains
the complete prebuilt installed desktop and uses
`nixos-install --system`; installation and graphical account setup need no
network connection. `--no-network` removes the VM's network adapter entirely.
The build host still needs dependencies available locally or through a cache.

Shut down the guest when installation finishes. Boot the same disk without
the ISO:

```sh
python3 tools/dev/linux-iso-vm.py --state .local/installer-test --no-network
```

Complete the welcome wizard and log in. Later launches use this same command
and preserve the account and files. The installed configuration keeps its own
hardware settings, owner file, and pinned Ohmansy source under `/etc/nixos`.
Use `--rescue-iso path/to/image.iso` to boot installation media with an existing
VM disk without replacing it. For automated tests, `--headless` uses accelerated
graphics and a private `vnc.sock` in the state directory instead of a window.
The state directory also contains private QMP and serial sockets. Keep automated
installation tests separate from a VM someone is using interactively.

For repeatable launches or saved IDE actions, use `mise run installer-vm` and
`mise run installed-vm`. The installer VM task first runs `installer-iso`, which
builds `dist/installer/ohmansy-installer.iso`. Run `mise run installer-iso` to
build without launching QEMU. Mise checks the flake, lock file, `nix/` sources,
and build script against the ISO output and skips unchanged builds. Missing
outputs or changed sources trigger a build; Nix reuses its own cached outputs.
Use `mise run --force installer-iso` to force the task to run.

Without mise, first run `bash tools/build/installer-iso.sh`, then
`bash tools/dev/installer-vm.sh iso` (or `disk` for the installed system).
Both launch modes use `.local/installer-actions`
and disable networking. The ISO action creates the disk on first use and
preserves it on later launches. Shut down the guest before switching actions.
The disk action requires a completed installation before it can boot Ohmansy.

The repository's `t3.json` declares **Run installer ISO** and **Run installed VM**
for T3 Code. Project Actions settings also offer **Import from t3.json**.

The default ISO is `dist/installer/ohmansy-installer.iso`.
Set `OHMANSY_INSTALLER_ISO` to use another image and `OHMANSY_INSTALLER_STATE`
to use another VM directory. To launch an alternate image without building the
default one, use the shell launcher directly. The build publishes the ISO by
atomic replacement, so an already running QEMU keeps its open image. Restart
the VM to boot the new ISO. Existing VM disks are preserved.

Only one installer can run at a time. The graphical window shows real stages
and a selectable installation log. Closing it leaves installation running;
reopen **Install ohmansy** to recover progress. Errors stay visible, and the
installer refuses another erase after destructive work has started. The full
log is `/var/log/ohmansy-install.log` in the live session; save it before shutdown
if you need it for recovery. The command-line fallback is `sudo ohmansy-install`.

For UI work, use the **Preview installer UI** T3 Action or `mise run installer-ui`.
This opens a desktop window with simulated disks and installation progress;
it cannot erase disks or shut down the host. It reads installer QML directly
from the checkout so Quickshell can reload edits without an ISO build or VM.
The launcher supports native Nix and the existing local Nix Portable runtime.
The portable runtime defaults to software rendering for host-driver compatibility;
the animated ribbon background is disabled in that mode.

Start on a particular screen with `bash tools/dev/installer-ui.sh confirm`.
Other screens are `welcome`, `disks`, `progress`, `done`, and `failed`.
For a compact window, set `PREVIEW_WIDTH=640 PREVIEW_HEIGHT=540` before the command.
Shared UI components and compiled assets still come from Nix packages; restart
the preview after changing those. The standalone `nix run .#installer-preview`
uses a packaged snapshot unless `OHMANSY_INSTALLER_QML` is set by the launcher.

`nix build .#checks.x86_64-linux.installer-ui`
renders every screen at wide, compact, short, and narrow sizes, checks for QML
errors, and verifies that the fixed action buttons fit within the window.

Speech synthesis is disabled by default, avoiding the large MBROLA voice
collection. A host can opt in with `services.speechd.enable = true`.

The generic installer does not yet configure NVIDIA's proprietary userspace
driver. Physical NVIDIA installation needs a separate driver configuration.

Run `nix build .#checks.x86_64-linux.offline-installer` on the ISO builder too.
It checks boot/account policy and preservation of store symlinks during image
assembly. A local Nix Portable 2.20.6 sandbox dereferenced those symlinks, causing
hash mismatches during offline installation despite a successful ISO build.
Use a builder that passes the check; a per-command `--option sandbox false`
worked around that local environment issue. Do not disable sandboxing globally.

The initial system uses `OHMANSY_ROOT` and `OHMANSY_EFI` filesystem labels.
Installation refuses matching labels on another connected disk. Keep other
Ohmansy installation disks disconnected until a normal rebuild has switched
this system to its generated UUID-based hardware configuration. The chosen
hostname is written to `/etc/hostname` for the initial boot and to the installed
Nix configuration for future rebuilds. Updates and additional packages may need
internet; there is no mandatory download stage at first boot.

See [ISO redistribution](iso-redistribution.md) before publishing a binary image.

### Use a preinstalled VM image

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
