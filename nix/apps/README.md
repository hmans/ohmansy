# Optional app layers

These NixOS modules are included by the default ohmansy module, with every app
disabled. Other compositions can import `ohmansy.nixosModules.apps` explicitly.
They reuse upstream program modules and the desktop's audio, graphics and capture
services. They do not manage personal app settings or install user profiles.

Create `~/.config/ohmansy/apps.nix` containing:

```nix
{ ... }: {
  ohmansy.apps.obs.enable = true;
  ohmansy.apps.steam.enable = true;
  ohmansy.apps.onepassword.enable = true;
  # Optional; changes kernel configuration:
  # ohmansy.apps.obs.virtualCamera.enable = true;
}
```

OBS includes browser sources. Add further plugins through
`programs.obs-studio.plugins`. Steam uses the upstream runtime, controller rules
and 32-bit graphics support; it requires x86-64 Linux. Neither layer chooses a
GPU driver. The host must permit Steam's unfree packages in its existing license
policy (`steam`, `steam-unwrapped`, `steam-run` and `steam-original` as needed).
Merge these names into an existing `nixpkgs.config.allowUnfreePredicate`; do not
replace a policy that also permits the machine's NVIDIA driver.

Steam Remote Play and dedicated-server firewall openings remain opt-in through
the upstream `programs.steam` options. OBS virtual camera is also opt-in.
Disabling a layer removes its contributions, without deleting personal app data.

1Password installs the native desktop app and `op` CLI through their NixOS
modules, including the browser and CLI privilege helpers. In the host's local
configuration, set `programs._1password-gui.polkitPolicyOwners = [ "your-login" ];`
and permit `1password`, `1password-gui`, and `1password-cli` in the existing
unfree license policy. Preserve any existing NVIDIA or Steam allowances.
The shared authentication agent runs in both Shine and Niri login sessions.
In 1Password, enable system authentication under Security and CLI integration
under Developer. Account sign-in and these preferences remain personal.

Install the 1Password browser extension in a native NixOS browser. Firefox,
Chrome and Brave integration is handled upstream; Flatpak browsers cannot use
this integration. For other browsers, follow the
[NixOS 1Password guide](https://wiki.nixos.org/wiki/1Password) to add their actual
executable names to `/etc/1password/custom_allowed_browsers`. SSH-agent and Git
signing configuration remain opt-in; this layer does not change existing keys
or SSH-agent selection.

Run `ohmansy-switch` to build and activate, or `ohmansy-boot` to build and select
the next boot without changing the running desktop. Run these as your normal
user; activation requests sudo. `--build-only` validates without activation.
`--system /path/to/config --host name` selects a nonstandard installed flake.
The commands use their shipped ohmansy source automatically, including local
development builds. Protected host configuration is copied after sudo
authentication; its permissions and contents remain unchanged. Keep `apps.nix`
self-contained: relative imports are not supported.

Until the commands are installed, run `nix build .#ohmansy-apply` in the checkout,
then `./result/bin/ohmansy-switch` or `./result/bin/ohmansy-boot`.

After `mise run os-boot` and reboot, simply run `ohmansy-switch` or `ohmansy-boot`.
No checkout path or development flag is needed. `--build-only` also works when
the installed host configuration requires authentication to read.

These temporary wrappers compose a snapshot with the installed host; they do
not edit `/etc/nixos` or its release pin. They override the ohmansy input in the
temporary snapshot with the release shipped alongside the commands. Always use them to retain the personal
selection: ordinary `nixos-rebuild` and `ohmansy-update` do not yet include it.
The selection is system-wide and trusted NixOS configuration, not a sandboxed
per-user app list. Only an administrator can activate it. Nothing reboots
automatically. A future CLI can manage selection and unify the update workflow.
