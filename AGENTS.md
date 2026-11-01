# try ohmansy

Native macOS host for an ARM NixOS desktop. The user-facing name is **try ohmansy**.
Act on implementation requests, build the result, and report what was verified.
Use `apply_patch` for source edits. Do not spawn subagents unless asked.
Use Conventional Commits. Do not push unless asked.

## Repository boundaries

- `flakey/` is an independent, ignored Git repository. Never stage it here.
  Read its own `AGENTS.md` and NixOS skill before changing guest configuration.
- `.local/` holds VM disks, SSH credentials, logs, and experiments. Keep it ignored.
  Never commit private keys, guest disks, downloaded runtimes, or generated bundles.
- Do not expose the host home directory to the guest. Transfer only requested files.

## Architecture

- `Sources/Ohmansy/RuntimeApp.swift` is the windowless coordinator for the default
  accelerated backend. `scripts/gpu-probe.py` manages QEMU and QMP.
- `macos/RuntimeChrome.m` adapts the pinned QEMU Cocoa view into one window with
  an inset guest card, toolbar, launcher, permission checks, and input capture.
- `macos/WelcomeCanvas.m` and `macos/Welcome.metal` render the welcome animation.
  Pause rendering when hidden or when Reduce Motion is enabled.
- `scripts/stage-runtime.py` bundles a checksum-pinned engine from the installed
  Try Omarchy app. Do not modify that source installation or silently change the pin.
- The original Apple Virtualization backend remains available with `--original-vm`.
  Keep its clipboard and display behavior distinct from the accelerated backend.
- `macos/Ohmansy.icon` is the icon source. Apple asset tools generate the modern
  assets and legacy icon; do not replace them with a manually rounded image.

## Build and validation

Run `make test` for Swift, Python, and native adapter regression tests.
Run `make build` to package `dist/Ohmansy.app`; `make run` builds and launches it.
The nested helper is `Contents/Helpers/try ohmansy.app`, with executable
`Contents/MacOS/try ohmansy`. Its bundle ID is `dev.hmans.ohmansy.runtime`.
The outer bundle ID is `dev.hmans.ohmansy`.

Use `scripts/signing.py` for stable local signing. Ad-hoc signing can invalidate
macOS Accessibility permission. Verify packaging with
`codesign --verify --deep --strict dist/Ohmansy.app`.
Do not overwrite a running helper with a full build. Arrange a clean shutdown
before rebuilding or restarting the app. A build does not update loaded code.

## Input and guest operations

- The stopped launcher must never capture Mac shortcuts. Clicking the running
  guest locks input; Control–Option–G and leaving the window release it.
  Permission polling must not lock input by itself.
- Keep one host window, free aspect-ratio resizing, the small inset, and its shadow.
- Use SSH for guest commands; see `docs/guest-development.md`. Never ask for a
  password in chat. Let the user enter sudo passwords in a terminal.
- Synthetic typing into the guest can drop keys or leave them repeating. Prefer
  SSH commands over typing long commands through the VM window.
- Prefer `nixos-rebuild boot` for login-manager changes to avoid terminating a
  live desktop. Distinguish built, selected for boot, and currently running systems.
- Use clean shutdown. Force stop is a power cut, not a routine restart mechanism.

## Current limits

The development guest uses the separate flakey ARM host, SDDM, Niri, and
Quickshell. Ghostty has a VM-only software-rendering wrapper because the current
VirGL backend does not expose its required OpenGL version. General folder sharing,
accelerated-backend clipboard/audio, and additional displays remain separate work.
See `docs/graphics.md` for renderer details and `docs/guest-development.md` for
guest setup. Keep those documents aligned with changes; preserve state versions,
disk identities, and user settings during guest work.
