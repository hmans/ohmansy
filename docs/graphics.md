# Accelerated Linux graphics

The main app now launches an app-owned QEMU helper with `virtio-gpu-gl-pci`,
VirGL, and native macOS OpenGL. It follows the graphics architecture described by
[Try Omarchy](https://github.com/omacom/try-omarchy/blob/main/docs/architecture.md).

This is an independent launcher. `scripts/stage-runtime.py` packages a pinned
engine from the locally installed Try Omarchy app under
`Ohmansy.app/Contents/Helpers/OhmansyVM.app`. Its binaries and libraries stay in
ignored build output. The source app is not modified. Local builds include its
MIT license, credits, and firmware licenses. A distributable release still needs
a reproducible runtime build and complete third-party source/license compliance.

## Main app integration

`RuntimeApp` is a windowless coordinator that starts the helper with saved CPU
and memory preferences. The helper owns the only window, including its launch
screen. QEMU starts paused (`-S`); **Start NixOS** resets and resumes it. With
`-no-shutdown`, guest shutdown stops emulation and returns to the launch screen
in that same window. Closing or quitting requests shutdown before exiting.
The accelerated disk location is saved under `acceleratedVMDirectory`; the
existing `.local/gpu-vm` copy is adopted in this development checkout. A fresh
installation defaults to `~/Library/Application Support/Ohmansy/AcceleratedVM`.
The original Apple Virtualization disk remains separate.

The helper loads our `OhmansyChrome.dylib` in its own process. The adapter wraps
the pinned runtime's Cocoa guest view in a rounded inset, provides native
toolbar controls, and names the window **try ohmansy**. **VM Controls** offers
the VM files and force-stop action. Frames stay on the
accelerated renderer; there is no screenshot or VNC transport.

Input starts unlocked. Mac Command shortcuts stay with macOS until the user
clicks inside the running guest or clicks **Lock input** in the toolbar. **Control–Option–G**, the unlock
button, switching away from the window, or stopping the guest releases input.
The stopped launcher never captures shortcuts. Permission checks do not lock input.
**Keyboard Shortcuts…** in VM Controls or the app menu opens the
setup panel; the stopped-VM launcher also offers a setup button. **Open Settings**
requests macOS Accessibility access for the helper process and opens its privacy
settings page. macOS may label this permission **Device Control and Data Access**.
The user must grant access. If the toggle is already on but the app still lacks
access, remove the stale entry and re-add the outer app revealed by **Show App**.
The launcher is the responsible process for the helper's permission requests.
The app checks permission and enables the event tap only while input is locked.
After granting access, use the lock button to connect capture without restarting
the guest. **Retry** refreshes permission status. Automatic checks never display
permission prompts.

Builds use the sole available Apple Development signing identity, or the identity
specified in `OHMANSY_SIGN_IDENTITY`. This preserves a certificate-based identity
across rebuilds. If no unique development identity is available, signing falls
back to ad-hoc with a warning: hash-based permissions can become stale after a
rebuild. Moving from ad-hoc to certificate signing requires reauthorizing the app
once. The build does not select a Developer ID distribution identity automatically.

QEMU assumes its guest view fills the content area. The adapter prevents its
`resizeWindow` method from resizing the outer window after wrapping; otherwise
each guest mode change subtracts the inset again. A native regression test
exercises 100 repeated resize requests and checks the unwrapped startup path.
The adapter also overrides QEMU's aspect-ratio resize delegate, clears content
resize constraints, and allows a 480 × 360 point minimum. Regression checks
cover both wide and tall resize requests. The frame draws a soft shadow around
the clipped guest area with a 10-point gutter.
QEMU's forced host cursor is disabled so it does not duplicate the guest cursor.
The adapter is specific to the pinned runtime and must be reviewed on upgrades.

The standalone GPU harness below remains a development diagnostic, not the
normal entry point. `make run` starts the main app.

## Run the experiment

Requirements: Apple Silicon, macOS 15 or later, Try Omarchy installed under
`/Applications`, Homebrew Python 3 at `/opt/homebrew/bin/python3`, and an ARM
graphical NixOS ISO. The tested Try Omarchy version is 1.2.0 (464), with QEMU
11.1.1. Later versions have not been tested.

```sh
make gpu-probe
open 'dist/ohmansy GPU test.app'
```

Choose the ISO and select **Start live GPU test**. The live session has no hard
disk; its installer will report that there are no partitions. Close the
installer to use the desktop. The test window is owned by QEMU and is separate
from the main app's inset VM view.

**Inspect live guest GPU** connects to the ISO's serial shell, runs `eglinfo`,
and starts Niri with an empty configuration for 15 seconds inside GNOME. It uses
`nix-shell` and may download packages into the live session's temporary storage.
It does not install a new system generation or load `flakey`. Niri's timeout
exit code of 124 is expected; check the preceding log for successful startup.

Logs are under `.local/gpu-probe/`:

- `launcher.log`: runtime validation and launch failures.
- `qemu.log`: host graphics initialization and runtime messages.
- `guest-gpu.log`: guest renderer details and the Niri startup test.
- `launch.json`: the exact QEMU arguments.

The CLI equivalent is:

```sh
python3 scripts/gpu-probe.py start --iso /path/to/nixos-aarch64.iso
python3 scripts/gpu-probe.py diagnose
python3 scripts/gpu-probe.py shutdown
```

The launcher verifies the installed runtime's signature before use. In a
restricted agent sandbox, macOS trust checks or local Unix socket connections
may fail even when the native harness works. Do not disable signature checks
to work around this; run the native harness in the normal app context.

## Test a copy of the installed VM

Shut down the original VM cleanly, then select **Start accelerated copy**.
The harness creates an APFS copy-on-write clone of
`~/Library/Application Support/Ohmansy/VM/disk.raw` in `.local/gpu-vm/disk.raw`.
It takes the original VM's disk lock during the copy and refuses to copy an
active VM. The original disk is never attached to QEMU.

The copy has a separate 64 MiB QEMU EFI variable store. Apple's existing EFI
variables are not compatible and are not reused. Later launches reuse the copy;
they do not import subsequent changes from the original VM. Changes in either
VM stay independent. The probe does not copy the original MAC address.

```sh
python3 scripts/gpu-probe.py start-copy --state "$PWD/.local/gpu-vm"
python3 scripts/gpu-probe.py shutdown --state "$PWD/.local/gpu-vm"
```

The live-guest diagnostic button is specific to the installer ISO's serial
autologin. It does not attempt to log in to the installed VM. Clipboard sharing,
audio, and dynamic display scaling are not yet implemented for this QEMU path.
The main app's existing integrations still belong to its Virtualization backend.
**Read copy boot log** captures the installed copy's serial console and QEMU
runtime status in `boot-console.log` and `runtime-status.json`. It does not enter
a username or password.

## Verified on 2026-10-31

On an Apple M4 Max, with the NixOS 26.05 graphical ARM installer:

- QEMU initialized host OpenGL 4.1 with renderer `Apple M4 Max`.
- The live GNOME desktop booted with no attached hard disk.
- Guest Mesa 26.1.8 reported `virgl (Apple M4 Max)` through GBM, Wayland,
  surfaceless EGL, and the primary EGL device.
- The accelerated device exposed OpenGL 4.1 and OpenGL ES 3.0. EGL also listed
  a separate software fallback device; that does not negate the VirGL results.
- Niri 26.04 started its nested `winit` output and Wayland socket, stayed alive
  for the 15-second smoke test, and handled SIGTERM. Its minimal test environment
  lacked xwayland-satellite and a cursor theme.
- Five Python tests cover the read-only live ISO, app-owned engine arguments,
  refusal to clone an active disk, independent copies, and symlink rejection.
- The installed NixOS disk was cloned after the original VM stopped. Its QEMU
  copy reached the serial login prompt, and the user confirmed the desktop was
  visible. QEMU reported `running`, and its VirGL log recorded guest 3D texture
  transfers on the Apple M4 Max. The installed guest's own renderer string has
  not been queried; the `eglinfo` results above belong to the live ISO.
- The bundled helper loaded the native window adapter and booted the installed
  desktop with the M4 Max renderer. The inset window remained at normal size
  through boot and guest mode changes after the resize feedback fix. The main
  app's single-window launch screen starts the guest in that same window.
- The native resize regression test passes alongside six Swift and five Python
  tests. The host-cursor setting is disabled; pointer behavior across screen
  changes still needs broader interactive testing.

Not yet verified: a full Niri login session,
the `flakey` desktop configuration, Vulkan, or long-running graphics stability.
Try Omarchy documents Vulkan as unavailable in its current runtime.

The next milestones are a full Niri login session, and porting clipboard and
audio to the accelerated path. Dynamic guest resolution, scale preservation,
keyboard shortcuts, and screen transitions need further runtime validation.
