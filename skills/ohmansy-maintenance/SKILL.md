---
name: ohmansy-maintenance
description: Maintain an ohmansy installation, including system configuration, software, updates, rollback, and desktop service diagnostics.
---

# Maintain ohmansy

ohmansy is a NixOS desktop. System packages and services come from NixOS
modules; machine configuration belongs to the installation, while application
settings and personal files belong to each user.

## Identify the installation

Read `/etc/os-release`, `uname -m`, and `findmnt /`. Inspect `/etc/nixos/flake.nix`
and its local module imports when present. A live ISO has temporary writable
storage; preserve work on persistent storage before shutdown.

An installed system normally has a pinned `ohmansy` flake input and local
`configuration.nix`, `hardware-configuration.nix`, `preferences.nix`, and
`owner.nix`. Inspect the actual files rather than assuming that layout.
Keep disk settings, accounts, the release pin, and `system.stateVersion` intact
unless the task specifically changes them. The state version is not the OS
release number. Never apply a factory or live-image profile to an installed OS.

Run commands directly through shell tools when inside the target system.
For another machine, use SSH or another explicit command channel.

## Configure software and services

Use local NixOS modules for persistent system changes. New installations import
`preferences.nix` for customization. Add packages with
`environment.systemPackages`; assigning `ohmansy.software.packages` replaces
the optional default bundle. Account and hardware settings stay machine-local.
User-owned Flatpak apps use `flatpak install --user flathub APP_ID`.

For the standard host layout, validate configuration changes with
`sudo nixos-rebuild build --flake /etc/nixos#ohmansy`, using the actual host
output if different. Build success does not activate anything. Select `switch`
for immediate activation or `boot` for next boot according to the requested
change. Plan session-disrupting changes with the user before activating them.

When developing ohmansy in its checkout, include new source files in the
Git-backed flake with `git add -N PATH` and build the affected Nix package before
reporting it ready. Cargo or preview success does not verify shipped packaging.
Keep private files and generated artifacts ignored. Use the checkout's
`mise run os-build` and `mise run os-test` tasks: they preserve the installed
machine configuration and release pin while overriding ohmansy with local sources.

Use `os-test` and verify affected services before handing an installed change
off for `os-boot`, when activation preserves the session. If local sudo
authentication is unavailable, finish checks that do not require it and report
installed activation as untested. Never request a password in chat. A successful
test activation does not replace a running compositor; rendering code still
needs a planned session restart before it can be verified in that desktop.

For Shine rendering iterations, use `mise run shine-dev` from the checkout.
It verifies hardware rendering, watches Rust sources and reloads shaders/QML
in an isolated nested preview. Use `mise run shine-check -- --no-graphics`
for package checks while investigating GPU freezes; a nested preview still
shares the physical GPU with the main desktop. See the checkout's compositor
development guide for logs, private configuration and verification limits.

For diagnostics, inspect the affected unit with `systemctl status` and
`journalctl -b -u UNIT`; desktop services use `systemctl --user` and
`journalctl --user -b -u UNIT`. Prefer reloading the affected settings or
restarting only the affected service. Preserve the compositor and application
windows during shell styling work.

## Update and recover

When `ohmansy-update` is available, `sudo ohmansy-update prepare RELEASE`
accepts a published tag or full commit ID and builds a candidate using the
local configuration. Use an actual requested release, not a guessed tag.
`sudo ohmansy-update apply UPDATE_ID` selects the prepared generation for the
next boot; it does not replace the running desktop. Use the ID returned by
preparation. Read command help for the installed version when needed.

For recovery, an older generation can be selected in the boot menu, or
`sudo nixos-rebuild boot --rollback` can select the previous generation for
next boot. Rolling back the OS does not restore `/etc/nixos` source files.
Preserve previous generations and `/var/lib/ohmansy/updates` while diagnosing
an update failure. Do not replace the disk or recreate accounts to update.

Report separately what was edited, built, activated, and verified running.
