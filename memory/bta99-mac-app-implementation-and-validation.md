---
data:
  area: app
  kind: workflow
  reviewed: "2026-11-02"
  status: current
id: bta99
title: Mac app implementation and validation
---
# Mac application

Read [root instructions](../AGENTS.md) and [graphics documentation](../docs/graphics.md).
Use the root Makefile; the Swift package is app/Package.swift.

## Ownership and boundaries

- Sources/Ohmansy/RuntimeApp.swift coordinates the accelerated helper process.
  The helper owns the single window. Keep bundle IDs, preferences, and existing
  VM directory selection stable unless a task explicitly changes them.
- native/RuntimeChrome.m adapts a specific pinned QEMU Cocoa implementation.
  Check the engine's actual selectors and locking rules before changing hooks.
  A runtime upgrade requires explicit pin, compatibility, and license review.
- runtime/ contains shipped lifecycle code. It must work inside the signed
  bundle as well as from the checkout; do not import tools/ at runtime.
- Sources/Ohmansy/OhmansyApp.swift and VirtualMachine.swift implement the original
  backend. legacy/guest/ supports that backend and historical experiments.
  Do not route new factory work through it or claim its clipboard works in QEMU.

## Interaction invariants

- Keep one window, free resizing, the small inset, rounded guest card, and shadow.
- The welcome screen must leave Mac shortcuts alone. Entering the visible running
  guest in the active window locks input. Leaving it or Control–Option–G releases
  it. Hover must not prompt for permission or capture behind a sheet/popover.
- Input capture has no toolbar lock icon and keeps the title `try ohmansy`.
  Permission setup remains under VM Controls → Keyboard Shortcuts….
- Balance cursor hide/unhide calls and release held keys when unlocking.
  Permission polling must never capture input. Do not automate terminal input.
- Keep HiDPI scaling separate from guest pixel resolution. Check resizing and
  movement between displays; do not restore aspect-ratio constraints.
- Preserve GPU acceleration. A software cursor is not full software rendering.
  Do not silently apply a whole-session software-rendering workaround.
- Native welcome rendering must pause when hidden and honor Reduce Motion.
  Use the Icon Composer asset and Apple's compiler for icon treatment.

## Verification

Run make test from the root for Swift and native adapter coverage. For a running
app, build to a separate APP_BUNDLE and verify its code signature. Do not replace
loaded executable code. An alternate bundle uses the same application identity
and preferences, so it is not automatically an isolated VM test environment.

Visual changes need a normal GUI check. Input changes need lock/unlock, focus
loss, stopped-state shortcuts, and cursor checks. Do not claim tests prove those
interactive behaviors. State which bundle was built and which app is running.


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

## Boot framebuffer aspect ratio

The adapter fits every framebuffer inside the black guest well. Both firmware
and desktop use texture scanouts in the pinned engine, so scanout kind cannot
distinguish boot from desktop. Use exported console dimension functions under
BQL; release BQL before changing AppKit geometry.

During updateUIInfoLocked, the guest frame getter reports the full well size
using a thread-local guard. Outside that call, it reports the real fitted frame.
This lets Linux adopt the full window resolution without stretching fixed boot
pixels or changing input coordinates. No private struct offsets are required.

On 2026-11-02, make test passed (6 Swift, 25 Python, native checks), including
wide/tall fitting and full-area display negotiation. The signed app was installed
after clean shutdown. Its boot menu retained proportions when changed to wide
and tall windows through the native Window menu.
