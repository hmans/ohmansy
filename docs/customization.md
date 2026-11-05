# Customizing Ohmansy

Keep your preferences in a host module under `/etc/nixos`, separate from the
Ohmansy release input. Import it alongside your existing host configuration.
This lets you change defaults without editing the desktop implementation.

## Select modules

The root flake exports these NixOS modules:

| Module | Includes |
| --- | --- |
| `nixosModules.default` | Desktop and software defaults |
| `nixosModules.desktop` | Niri, Quickshell, login screen, desktop services, and terminal integration |
| `nixosModules.software` | Firefox, Fish, and optional command-line tools |
| `nixosModules.vm` | Guest display and Virtio integration |
| `nixosModules.updates` | Command-line release preparation and boot selection |

The default module has no accounts or disk layout. A physical machine combines
it with its hardware configuration and local accounts. The app's persistent VM
profile combines it with VM integration and the VM disk layout. Choosing
`desktop` alone omits the optional software bundle.

New factory and installer configurations use a pinned `ohmansy` flake input.
The initial pin points to the exact source shipped in the image, so first boot
does not require a published release or network access. Updates select a GitHub
release tag or full commit ID. See [Updating Ohmansy](updates.md).

`configuration.nix`, `hardware-configuration.nix`, `owner.nix`, and
`preferences.nix` belong to the installed machine. Its `system.stateVersion`
stays in local configuration; it is not the Ohmansy release number.

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

New installations already import `./preferences.nix`. On older installations,
add it to the host's module imports. Then rebuild:

```sh
sudo nixos-rebuild switch --flake /etc/nixos#ohmansy
```

The optional utility bundle defaults to Git, mise, herdr, Vim, curl, wget, jq,
GCC, GNU Make, Python 3, pkg-config, fastfetch, btop, htop, and psmisc (including
`killall`). These defaults live in `nix/modules/software.nix`, exported by the
root flake as `nixosModules.software`.
Assigning `ohmansy.software.packages` replaces that list; ordinary
`environment.systemPackages` entries add to it. Firefox and Fish use their
standard NixOS enable options. Disabling Fish restores NixOS's Bash default
unless you select another shell. Individual accounts can set
`users.users.<name>.shell` instead.

Run `herdr` in a terminal to open its agent workspace. It comes from the upstream
Nix flake, pinned to `v0.9.5`, for both PC and ARM systems. It updates with
ohmansy through Nix. To select another upstream release when maintaining ohmansy,
change `inputs.herdr.url` in `flake.nix` and run `nix flake update herdr`.

The shared software defaults add `~/.local/bin` to `PATH`, including in Fish.
Set `environment.localBinInPath = false;` to disable this. Log out and back in
after rebuilding to load the updated session environment.

Mise uses upstream release binaries, pinned to `2026.11.0` with a checksum for
each architecture. The bundled tools and development shells use this package.
To update it when maintaining ohmansy, change the version and archive hashes in
`nix/modules/mise-package.nix`. It updates with ohmansy through Nix.
Use `nix run .#mise -- --version` to try it separately. When the utility bundle
includes mise, ohmansy automatically activates it in interactive Fish, Bash,
and Zsh shells. Open a new terminal after rebuilding. Repository tasks also
work without shell activation.

Codex is installed by the user through mise, rather than bundled with ohmansy:

```sh
mise use --global codex@latest
```

Log out and back in after changing the default shell so the desktop receives
the new `SHELL` environment variable. Existing shells keep running.

Desktop services keep their runtime dependencies, even if a tool is removed
from the optional bundle. Old system generations and other packages may also
retain store paths; removing a default does not immediately erase its files.
Nautilus and the sound, network, Bluetooth, clipboard, and lock tools remain
part of the desktop integration in this version.

## Cursor theme

ohmansy uses Bibata Modern Classic at size 24 for the desktop and login screen.
The desktop supplies the Xcursor assets and an unlocked GTK preference;
your saved GTK cursor choice takes priority. Shine's session and development
wrappers also honor `XCURSOR_THEME`, `XCURSOR_SIZE`, and `XCURSOR_PATH`.

After installing an updated system, log out and back in to reload the cursor
theme in the compositor and applications.

## AppImages

The software defaults include `appimage-run` and register type 1 and type 2
AppImages for direct execution. Download an AppImage for your machine's CPU
architecture, make it executable, and run it:

```sh
chmod +x Example.AppImage
./Example.AppImage
```

You can also run it explicitly with `appimage-run ./Example.AppImage`.
Existing installations need a rebuild to receive this support. The runner
extracts applications into your user cache and supplies a conventional Linux
filesystem environment.

Set `programs.appimage.enable = false;` to omit the runner and registration.
To keep the runner but require explicit invocation, set
`programs.appimage.binfmt = false;`.

## Fish appearance

Fish uses Starship's Pastel Powerline preset, with connected colored segments
for the user, directory, Git state, language tools, container context, and time.
JetBrainsMono Nerd Font supplies its icons and separators in Foot. The preset
uses fixed colors with explicit pale lettering in both modes. Fish keeps its
standard syntax colors. These lettering defaults apply only
to the Pastel Powerline preset and can be overridden through Starship settings.

Set `ohmansy.fishStyle.enable = false;` to omit these defaults. Customize the
prompt with `~/.config/starship.toml`, or use the standard NixOS
`programs.starship.presets` and `programs.starship.settings` options. NixOS's
Starship integration also applies to other enabled supported shells.
New terminals load changes; existing Fish
processes keep their loaded configuration.

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

## VM display scale

The VM module uses 100% scale on x86-64 and retains 200% for the ARM Mac VM.
The setup screen, login screen, and desktop share this setting. A host that
imports `nixosModules.vm` can override it in its configuration or preferences:

```nix
ohmansy.vm.displayScale = 1.25;
```

## Verification

`nix build .#checks.aarch64-linux.customization` checks independent module
imports, Firefox and Fish opt-outs, Bash fallback, a Zsh override, replacement
of the utility bundle, and Kitty selection and generated shortcuts. It resolves
the terminal command without opening a GUI. The Niri configuration check also
validates the packaged bindings for the factory and both ISO profiles.
