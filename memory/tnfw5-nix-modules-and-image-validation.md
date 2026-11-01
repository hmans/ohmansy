---
data:
  area: nix
  kind: workflow
  reviewed: "2026-11-01"
  status: current
id: tnfw5
title: Nix modules and image validation
---
# Official Ohmansy configuration

Build from the root flake. `flakey/` is reference material only, not an input.
`profiles/` composes factory, live, and installer systems. `modules/` contains
reusable modules, with implementation assets in matching subdirectories. Keep
the public `nixosModules` and package output names stable when moving files.
Keep the desktop module usable by people with different accounts and hardware.
Machine-specific storage and credentials belong to host configurations, not
`modules/desktop.nix` or `modules/vm.nix`.

Use the locked Nixpkgs source to verify module options and package names.
Do not update the lock file or state versions as a side effect of another task.
Do not add personal services, private keys, preset installed-user passwords,
or development SSH access to the live image.

Validate with `nix flake check --no-update-lock-file` on ARM Linux, then build
`nix build --no-update-lock-file .#vm-image`. Building an image does not prove it boots:
test it in a disposable VM and record what was observed.

The live account intentionally has local passwordless sudo and autologin.
SSH is disabled. Never activate the live host on an installed machine. Persistent
installation uses the appliance host with first-boot owner setup or a separate
host with explicit storage and users. Never add a default password to the factory.

For installed-system login-manager or hardware changes, use `nixos-rebuild boot`
and a planned reboot. Preserve the previous boot generation for recovery.
Use `apply_patch`, stage new referenced files for Git-backed flakes, and keep
build output and VM disks outside the tracked source tree.
