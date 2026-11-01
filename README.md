# ohmansy

**Ohmansy** is a NixOS desktop built around Niri. **try ohmansy** is its native
macOS host, with an accelerated guest display and a persistent private VM disk.

The app is independently implemented and inspired by
[Try Omarchy](https://github.com/omacom/try-omarchy). Development builds package a
pinned copy of its QEMU/VirGL engine. The official Ohmansy flake does not depend
on the separate, ignored `flakey/` reference repository.

## Repository layout

| Path | Responsibility |
| --- | --- |
| `app/Sources/`, `app/Tests/` | Swift app and tests; package manifest in `app/` |
| `app/native/` | Cocoa runtime adapter and Metal welcome animation |
| `app/resources/` | Icon Composer source, plists, and entitlements |
| `app/runtime/` | Python VM lifecycle code shipped inside the app |
| `app/legacy/guest/` | Guest integration for the original development backend |
| `nix/modules/` | Reusable desktop, VM, first-boot, and installer modules |
| `nix/profiles/` | Factory, live, and installer compositions |
| `tools/dev/` | SSH source transfer, guest builds, and isolated ISO tests |
| `tools/build/` | App bundling, engine staging, icons, and signing |
| `tools/release/` | Image packaging, manifests, and source archives |
| `tools/tests/` | Python tooling and guest-setup regression tests |
| `docs/` | Development workflows and architecture |
| `memory/` | Means collection of durable engineering findings and lessons |
| `.local/`, `.build/`, `dist/` | Ignored local state, build cache, and artifacts |

Keep accounts, keys, and disk identities out of reusable modules. Desktop assets
live beside their module, for example `nix/modules/desktop/niri.kdl`. The root
flake exports public modules and build outputs; profiles compose them without
embedding personal configuration.

## Build the Mac app

Use Apple Silicon, macOS 15 or later, Xcode with Swift 6 or later, Homebrew
Python 3, and Try Omarchy 1.2.0 (464) installed in `/Applications`. The engine is
checksum-pinned. Nix is not required on the Mac.

A packaged factory must already exist at `dist/factory-preview/`. See
[Ohmansy development](docs/ohmansy-development.md) to build and package it.

```sh
make test
make build
open dist/Ohmansy.app
```

`make run` builds and opens the same app. Shut down and quit it before replacing
its bundle. To validate a build while that app remains running:

```sh
make build APP_BUNDLE=dist/check/Ohmansy.app
```

Use `FACTORY_DIR=/path/to/package` to select another packaged factory. App builds
consume that artifact; they do not build NixOS or replace an existing guest disk.
Builds use local signing and are not notarized distribution builds.

## Build the OS

On ARM Linux, including the development VM:

```sh
make flake-check
make vm-image
```

The root flake also provides `.#iso` for a disposable live desktop and
`.#installer-iso` for the experimental installer. The primary app uses the
persistent factory disk, with first-boot owner setup and no preset credentials.
The installer still needs end-to-end validation.

Use SSH for guest commands and file transfer. Never type or paste commands into
terminal windows through computer automation. Development SSH access belongs to
a local guest overlay and is excluded from product images.

## Further reading

- [Agent instructions](AGENTS.md) and [engineering memory](memory/MEANS.md):
  session workflow and project knowledge. Start with `means list --path memory`.
- [Ohmansy development](docs/ohmansy-development.md): flake outputs, SSH builds,
  image packaging, and release work.
- [Graphics integration](docs/graphics.md): the accelerated runtime and input.
- [Original Virtualization backend](docs/legacy-virtualization.md): the retained
  `--original-vm` backend, including its clipboard integration.
- [Earlier guest setup](docs/guest-development.md): historical personal-builder
  configuration; not the official product.

GPU acceleration, Niri login, guest rebuilds, and cursor handling have been
verified in the development VM. Accelerated clipboard/audio, remote factory
updates, reproducible engine builds, and public Mac distribution remain work
in progress. The CI workflow builds factory artifacts but does not publish them.
