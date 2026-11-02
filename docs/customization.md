# Customizing Ohmansy

Keep your preferences in a host module under `/etc/nixos`, separate from the
copied Ohmansy modules. Import it alongside your existing host configuration.
This lets you change defaults without editing the desktop implementation.

## Select modules

The root flake exports these NixOS modules:

| Module | Includes |
| --- | --- |
| `nixosModules.default` | Desktop and software defaults |
| `nixosModules.desktop` | Niri, Quickshell, login screen, desktop services, and terminal integration |
| `nixosModules.software` | Firefox, Fish, and optional command-line tools |
| `nixosModules.vm` | Guest display and Virtio integration |

The default module has no accounts or disk layout. A physical machine combines
it with its hardware configuration and local accounts. The app's persistent VM
profile combines it with VM integration and the VM disk layout. Choosing
`desktop` alone omits the optional software bundle.

Factory and installer configurations use local module copies. Their combined
entry point is `nix/modules/default.nix`. The factory imports it through
`persistent-vm.nix`; newly generated installer configurations import it directly.
Older configurations importing `desktop.nix` directly must switch to
`default.nix` if they want to retain the optional bundle after updating sources.
This separation does not implement automatic upstream updates.

## Add or remove optional software

For example, create a `preferences.nix` module:

```nix
{ pkgs, ... }: {
  programs.firefox.enable = false;
  programs.fish.enable = false;
  programs.zsh.enable = true;
  users.defaultUserShell = pkgs.zsh;

  # Replace the optional utility bundle, including with [].
  ohmansy.software.packages = with pkgs; [ git curl ];

  # Add your own programs without replacing the bundle.
  environment.systemPackages = with pkgs; [ vlc libreoffice ];
}
```

Add `./preferences.nix` to the host's module imports. The factory flake's
`nixosSystem.modules` list is one such location. Then rebuild:

```sh
sudo nixos-rebuild switch --flake /etc/nixos#ohmansy
```

The optional utility bundle defaults to Git, Vim, curl, jq, and Python.
Assigning `ohmansy.software.packages` replaces that list; ordinary
`environment.systemPackages` entries add to it. Firefox and Fish use their
standard NixOS enable options. Disabling Fish restores NixOS's Bash default
unless you select another shell. Individual accounts can set
`users.users.<name>.shell` instead.

Log out and back in after changing the default shell so the desktop receives
the new `SHELL` environment variable. Existing shells keep running.

Desktop services keep their runtime dependencies, even if a tool is removed
from the optional bundle. Old system generations and other packages may also
retain store paths; removing a default does not immediately erase its files.
Nautilus and the sound, network, Bluetooth, clipboard, and lock tools remain
part of the desktop integration in this version.

## Firefox appearance

Firefox starts with compact controls, flat tabs, coordinated light/dark toolbar
colors, and a softer address-field focus outline. The bookmarks toolbar is hidden
by default; Firefox's toolbar menu can show it again. Density preferences remain
editable. Browser content and security indicators retain Firefox's behavior.

Disable the integration with `ohmansy.firefoxStyle.enable = false;`, or replace
the stylesheet with `ohmansy.firefoxStyle.css = builtins.readFile ./browser.css;`.
Individual users can set `ohmansy.browserStyle.enabled` to `false` in
`about:config` and restart Firefox to disable the stylesheet. This leaves the
compact and bookmarks defaults, which can be changed separately in Firefox.

The package loads browser-only CSS through AutoConfig; it does not write to user
profiles or replace `userChrome.css`. Firefox UI selectors can change between
releases, so check the appearance after browser upgrades. Restart Firefox after
rebuilding to load a changed stylesheet.

## Choose a terminal

One setting changes the system terminal selection:

```nix
{ pkgs, ... }: {
  ohmansy.terminal.package = pkgs.kitty;
}
```

This installs Kitty, changes the system `xdg-terminals.list`, and removes
Ohmansy's Foot-specific configuration and theme signaling. Super+Enter, network
controls, terminal desktop applications, and the installer use the shared
terminal selection through `xdg-terminal-exec`. Foot remains the default.
Alternative terminals use their own appearance settings.

Foot, Kitty, Alacritty, and Ghostty desktop entry IDs are detected automatically.
For another package, also set `ohmansy.terminal.desktopEntry` to its installed
`.desktop` ID. It must supply an entry supported by `xdg-terminal-exec`.

A user's `~/.config/xdg-terminals.list` can override the system selection if
their preferred terminal is installed. Such a user override selects the
launcher; it does not change system-wide terminal styling.

## Verification

`nix build .#checks.aarch64-linux.customization` checks independent module
imports, Firefox and Fish opt-outs, Bash fallback, a Zsh override, replacement
of the utility bundle, and Kitty selection and generated shortcuts. It resolves
the terminal command without opening a GUI. The Niri configuration check also
validates the packaged bindings for the factory and both ISO profiles.
