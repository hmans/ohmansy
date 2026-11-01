# Guest development

This page is a historical record of the retired personal development VM and
earlier bootstrap steps. That VM has been deleted; the commands below are not
the current development workflow. New product work uses the independent root flake; see
[Ohmansy development](ohmansy-development.md). Do not add new dependencies on
the reference `flakey/` checkout.

The accelerated VM forwards `127.0.0.1:2222` on the Mac to guest SSH port 22.
`app/legacy/guest/ssh/configuration.nix` enables key-only login for `hmans`. It imports the
existing `/etc/nixos/ohmansy/configuration.nix` wrapper and does not grant
passwordless sudo.

The development key and verified host key live in ignored `.local/ssh/`.
From this checkout, connect with:

```sh
ssh -p 2222 -i .local/ssh/id_ed25519 \
  -o IdentitiesOnly=yes -o StrictHostKeyChecking=yes \
  -o UserKnownHostsFile=.local/ssh/known_hosts hmans@127.0.0.1
```

For a new guest, place `app/legacy/guest/ssh/configuration.nix`, `app/legacy/guest/ssh/setup.sh`, and
the public key named `id_ed25519.pub` in one guest directory. Run `sudo bash
setup.sh` there. Compare its displayed host fingerprint with `ssh-keyscan`
before trusting the host key. Do not transfer the private key into the guest.

## Full flakey host

The separate flakey repository now defines `nixosConfigurations.ohmansy`.
It imports the shared workstation and Home Manager configuration, with ARM VM
hardware and the existing SSH public key in `hosts/ohmansy/`. The PC keeps its
NVIDIA driver and Steam settings. The VM uses the shared SDDM greeter, scale 2,
Mac Command mapping, and software cursor. Command–Enter and Command–T launch
Ghostty with a VM-only software-rendering wrapper. Its cursor shader is disabled
to limit CPU use; Console remains installed as a fallback.

Keep the guest checkout at `/home/hmans/flakey`: desktop QML and VS Code
settings link to files there. Build and prepare a boot from inside the guest:

```sh
cd ~/flakey
nix build .#nixosConfigurations.ohmansy.config.system.build.toplevel
sudo nixos-rebuild boot --flake .#ohmansy
```

Reboot to use the prepared system. Subsequent package changes can use
`sudo nixos-rebuild switch --flake .#ohmansy`. This target uses flakey's locked
inputs, rather than the installed guest channel. See flakey's README for ARM
package differences and the initial 1Password/NetBird setup.

## Earlier Niri experiment

`app/legacy/guest/niri/configuration.nix` was the initial adapter for the separate flakey checkout in this ARM
VM. The guest has a copy of flakey at `/home/hmans/flakey` and the guest modules
at `/home/hmans/ohmansy-guest`. The SSH public key is next to the SSH module.
The Mac's `flakey/` repository remains separate and ignored by this repository.

The adapter uses the installed NixOS channel and pins Home Manager to the
revision in the flakey lock file. It imports only the Niri desktop modules,
retains GNOME and the installed hardware settings, and keeps state versions at
26.05. It sets `Virtual-1` to scale 2 without a fixed resolution, removes the
PC Alt/Win swap, and disables the PC key remapper.

Niri uses a software cursor to avoid the separate virtual cursor plane.
Command–Enter and Command–T launch GNOME Console: Ghostty 1.3.1 exits because
it requires OpenGL 4.3, while this VirGL runtime exposes OpenGL 4.1.

Build in the guest:

```sh
nix-build '<nixpkgs/nixos>' -A system \
  -I nixos-config=/home/hmans/ohmansy-guest/niri/configuration.nix \
  -o /home/hmans/ohmansy-niri-system
```

Activate and set the next boot default:

```sh
sudo nixos-rebuild switch \
  --include nixos-config=/home/hmans/ohmansy-guest/niri/configuration.nix
```

Select **Niri** in the login screen's session menu. Inspect with `niri validate`
and `journalctl --user -u niri -u quickshell`. From SSH, run graphical commands
with `systemd-run --user` so they inherit the desktop environment.

Verified on 2026-11-01: full system build and activation, a Niri login on the
virtio GPU, Quickshell startup, scale 2, and a visible GNOME Console window.
Cursor behavior after restart and host modifier capture still need interactive
verification. The user also confirmed the SDDM login manager works after reboot.
Clipboard sharing and audio remain separate work.
