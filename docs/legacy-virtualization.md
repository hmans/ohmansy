# Original Apple Virtualization backend

This is a retained development backend, selected with `--original-vm`. It is
separate from the default factory/QEMU app. These instructions and verification
notes describe the earlier installation workflow; they do not configure the
current Ohmansy development guest.

## Install NixOS

For a new installation in this backend, quit the app, then run
`open dist/Ohmansy.app --args --original-vm`. The default launcher uses its own
factory VM and does not import this disk.

1. Download the **graphical, 64-bit ARM** ISO from [NixOS](https://nixos.org/download/).
2. Select **Choose Installer ISO**, then **Start with Installer**.
3. Use the NixOS installer inside the VM. Install to the 64 GiB virtual disk.
   The app does not expose your Mac's physical disks to the guest.
4. Shut down NixOS after installation. Select **Eject**, then **Start NixOS**.

The installer selection is temporary. Each app launch starts with no ISO attached.
An empty virtual disk cannot boot until NixOS is installed. If EFI opens its boot
manager, choose the attached installer. Select a basic desktop for the initial
installation; accelerated Hyprland is a separate development milestone.

Use **Shut Down** for a clean shutdown. **Force Stop** is a power cut and can lose
unsaved changes. A clean shutdown returns to **Start NixOS** in the same window.
Closing the window or quitting prompts for a clean shutdown, then exits.
The accelerated runtime reuses saved CPU and memory preferences; resource
selection is not yet exposed in its new launch screen.

### Retina displays

The controls in this section apply to the original Virtualization backend.
The accelerated backend publishes display size through Virtio GPU EDID; guest
scaling and resize synchronization still need integration testing.

While the VM runs, **Retina** requests one guest pixel per macOS backing pixel.
The requested resolution follows window resizing and moves between displays with
different pixel densities. For example, a 1000 × 700 point guest view on a 2×
Retina screen requests 2000 × 1400 pixels.
The guest view rounds down to whole macOS points. This keeps both Retina pixel
dimensions even, as GNOME requires for 200% scaling; a fractional layout remainder
is left as a black edge instead of stretching the guest image.

Set the Linux desktop's display scale to **200%** on a 2× screen to keep text sharp
and controls readable. Display options are in the toolbar's monitor menu.
The app requests a resolution; the guest desktop must accept it and apply its own
UI scale. There is no automatic guest UI scaling integration yet.

For an installer with small controls, select **Larger UI**. This requests one
guest pixel per macOS point, making a desktop at 100% scale readable at the cost
of Retina sharpness. Both modes can be changed while the VM runs.

### Keyboard and clipboard

Clipboard instructions here apply to the original Virtualization backend.

Click inside the guest to send keyboard input to Linux. The **Focus Keyboard** toolbar icon also
returns keyboard focus to the guest after using the host toolbar.

The app connects Apple's SPICE clipboard attachment through a named Virtio
console port. Enable `services.spice-vdagentd.enable = true;` in NixOS, rebuild,
and log in again so the desktop clipboard agent starts. Use Linux shortcuts
inside the guest: Ctrl+C / Ctrl+V in applications and Ctrl+Shift+C / Ctrl+Shift+V
in GNOME Terminal. Mac Command shortcuts are not translated to Linux shortcuts.

The app bundles `app/legacy/guest/clipboard.nix` and a bootstrap `app/legacy/guest/configuration.nix`
wrapper. These are available in the guest through the read-only VirtioFS tag
`ohmansy`; no host home directory is shared. The wrapper imports the existing
`/etc/nixos/configuration.nix` and enables the clipboard service. For ongoing
use, import the clipboard module from your own configuration. Rebuilding only
the original configuration will remove the service unless you add that import.

The development VM has these files installed at `/etc/nixos/ohmansy/`. Until
the module is imported by its main configuration, rebuild this VM with:

```sh
sudo nixos-rebuild switch --include nixos-config=/etc/nixos/ohmansy/configuration.nix
```

## VM storage

Files live in `~/Library/Application Support/Ohmansy/VM/`:

- `disk.raw`: a 64 GiB sparse disk. Physical storage grows as the guest writes data.
- `efi-vars`: persistent EFI variables.
- `mac-address`: the guest's persistent network identity.
- `lock`: an exclusive process lock to prevent two writers.

App rebuilds do not replace these files. There is no automatic reset or disk
migration. Stop the VM before copying its directory for a backup.

For isolated development, launch the executable with another storage directory:

```sh
OHMANSY_VM_DIRECTORY="$PWD/.local/vm" dist/Ohmansy.app/Contents/MacOS/Ohmansy --original-vm
```

## Verification

Verified on an Apple Silicon Mac with macOS 27.0.1 and Swift 6.4:

- Release app builds, and its local code signature passes verification.
- Three storage tests pass: persistent data and locking, empty-disk rejection,
  and symbolic-link rejection.
- Display geometry tests cover even Retina dimensions, resize rounding, and
  wide, square, and tall window proportions.
- The app opens and starts a VM. With no bootable media, the VM stops and the
  launcher becomes available again.
- The installed NixOS 26.05 guest boots with the SPICE console and read-only
  integration share. Its clipboard module evaluates, builds, and activates.
- Text copied in macOS TextEdit pastes into GNOME Console. A different string
  copied through GNOME Console's context menu pastes back into TextEdit.
- Direct keyboard events reach the guest after raising the host window and using
  **Focus Keyboard**. Automated modifier-key combinations are not yet reliable;
  clipboard verification used the guest context menu.

The user's running GNOME guest was inspected. Its odd-height custom mode hid the
Scale control; selecting an even-dimension mode restored it, including 200%.
Backing up GNOME's saved `monitors.xml` and logging in again removed the black
bars. The desktop now follows host resizing. Keeping 200% scale across all sizes
is still under verification; the guest's global scaling-factor is set to 2.
Guest audio and clipboard startup after another login have not been
verified by the agent.
