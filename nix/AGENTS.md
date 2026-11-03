# NixOS

Read Means note `tnfw5` (Nix modules and image validation) before changes:
`means show tnfw5 --path memory` from the repository root.
For guest iteration, also read `1kxxv`. Preserve the lock file and state versions
unless the task explicitly changes them. Never activate live profiles on an
installed guest.

Both x86_64-linux PCs and aarch64-linux guests support local development.
See [Linux development](../docs/linux-development.md) for native checks, previews,
and temporary installed-system overrides. Image outputs are architecture-specific;
shared desktop preview packages and dev shells are available on both.
