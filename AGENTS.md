# try ohmansy

Native macOS host for an ARM NixOS desktop. The user-facing name is **try ohmansy**.
Act on implementation requests, build the result, and report what was verified.
Use `apply_patch` for source edits. Do not spawn subagents unless asked.
Use Conventional Commits. Do not push unless asked.

## Repository boundaries

- `flakey/` is an independent, ignored reference repository. Never stage it here
  or import it into the official flake. Do not change it for new Ohmansy features.
- The root `flake.nix` and `nix/` own the desktop, factory disk, and live/installer ISOs. Keep
  accounts, credentials, and disk identities out of reusable desktop modules.
- `app/` owns the Mac application, its shipped runtime scripts, native code, and
  resources. `tools/dev/`, `tools/build/`, and `tools/release/` own host tooling;
  these tools are not shipped as guest configuration. Keep module assets beside
  their modules and compose image variants in `nix/profiles/`.
- `.local/` holds VM disks, SSH credentials, logs, and experiments. Keep it ignored.
  Never commit private keys, guest disks, downloaded runtimes, or generated bundles.
- Do not expose the host home directory to the guest. Transfer only requested files.

## Architecture

- `app/Sources/Ohmansy/RuntimeApp.swift` is the windowless coordinator for the default
  accelerated backend. `app/runtime/factory-vm.py` provisions the bundled image;
  `app/runtime/gpu-probe.py` manages QEMU and QMP. Normal app launch must use the
  official factory, never silently import the old personal development VM.
- `app/native/RuntimeChrome.m` adapts the pinned QEMU Cocoa view into one window with
  an inset guest card, toolbar, launcher, permission checks, and input capture.
- `app/native/WelcomeCanvas.m` and `app/native/Welcome.metal` render the welcome animation.
  Pause rendering when hidden or when Reduce Motion is enabled.
- `tools/build/stage-runtime.py` bundles a checksum-pinned engine from the installed
  Try Omarchy app. Do not modify that source installation or silently change the pin.
- The original Apple Virtualization backend remains available with `--original-vm`.
  Keep its clipboard and display behavior distinct from the accelerated backend.
- `app/resources/Ohmansy.icon` is the icon source. Apple asset tools generate the modern
  assets and legacy icon; do not replace them with a manually rounded image.

## Build and validation

Run `make test` for Swift, Python, and native adapter regression tests.
On ARM Linux, run `nix flake check` and `nix build .#vm-image` for the factory disk.
See `docs/ohmansy-development.md` for the VM build and preview release workflow.
Run `make build` to package `dist/Ohmansy.app`; `make run` builds and launches it.
The Swift package is in `app/`; use the root Makefile to retain the shared
`.build/` cache. `make build APP_BUNDLE=dist/check/Ohmansy.app` validates packaging
without replacing a running bundle. `FACTORY_DIR` selects the input artifact.
The nested helper is `Contents/Helpers/try ohmansy.app`, with executable
`Contents/MacOS/try ohmansy`. Its bundle ID is `dev.hmans.ohmansy.runtime`.
The outer bundle ID is `dev.hmans.ohmansy`.

Use `tools/build/signing.py` for stable local signing. Ad-hoc signing can invalidate
macOS Accessibility permission. Verify packaging with
`codesign --verify --deep --strict dist/Ohmansy.app`.
Do not overwrite a running helper with a full build. Arrange a clean shutdown
before rebuilding or restarting the app. A build does not update loaded code.

## Input and guest operations

- The stopped launcher must never capture Mac shortcuts. Clicking the running
  guest locks input; Control–Option–G and leaving the window release it.
  Permission polling must not lock input by itself.
- Keep one host window, free aspect-ratio resizing, the small inset, and its shadow.
- Use SSH for guest commands; see `docs/ohmansy-development.md`. Never ask for a
  password in chat. Let the user enter sudo passwords in a terminal.
- Never use computer use to type or paste commands into a terminal, including
  the guest terminal. Synthetic input drops key releases and leaves keys repeating.
  Do not retry with slower typing, individual keys, or another UI input method.
- Run guest commands and transfer files through SSH or an explicit non-UI command
  channel. If no such channel exists, establish one before continuing guest work;
  do not fall back to terminal UI automation. Use computer use only for visual
  checks and normal graphical controls.
- The current factory development VM uses localhost SSH port 2223, identity
  `.local/ssh/id_ed25519`, and host-key file `.local/ssh/factory-known-hosts`.
  Port 2222 and `.local/ssh/known_hosts` belong to the old personal builder.
  The factory's forwarding was added through QMP and must be restored after the
  host engine restarts. Guest SSH is declared only in its local
  `/etc/nixos/development.nix`, never in the shipped factory configuration.
- Prefer `nixos-rebuild boot` for login-manager changes to avoid terminating a
  live desktop. Distinguish built, selected for boot, and currently running systems.
- Use clean shutdown. Force stop is a power cut, not a routine restart mechanism.

## Current limits

The current factory development guest uses the independent flake with Niri,
SDDM, Foot, and Waybar. The old flakey ARM guest remains a separate reference
and optional builder. In that old guest, Ghostty has a
VM-only software-rendering wrapper because the current
VirGL backend does not expose its required OpenGL version. General folder sharing,
accelerated-backend clipboard/audio, and additional displays remain separate work.
See `docs/graphics.md` for renderer details and `docs/guest-development.md` for
guest setup. Keep those documents aligned with changes; preserve state versions,
disk identities, and user settings during guest work.
