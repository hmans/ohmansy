{ config, lib, pkgs, ... }:
{
  imports = [ ./firefox-style.nix ./fish-style.nix ./flatpak.nix ];
  options.ohmansy.software.packages = lib.mkOption {
    type = lib.types.listOf lib.types.package;
    default = (with pkgs; [
      git
      tig
      lazygit
      tmux
      mise
      herdr
      vim
      neovim
      vscodium
      zed-editor
      curl
      wget
      fzf
      ripgrep
      eza
      bat
      satty
      jq
      gcc
      gnumake
      python3
      pkg-config
      fastfetch
      btop
      htop
      psmisc
    ]) ++ map (app: pkgs.makeDesktopItem {
      name = "ohmansy-${app.id}";
      desktopName = app.name;
      exec = "google-chrome --app=https://${app.host}/";
      tryExec = "google-chrome";
      icon = app.icon;
      terminal = false;
      categories = [ "Network" ];
      keywords = [ app.host ];
    }) [
      { id = "chatto"; name = "Chatto"; host = "chat.chatto.run"; icon = "applications-internet"; }
      { id = "whatsapp"; name = "WhatsApp"; host = "web.whatsapp.com"; icon = "whatsapp"; }
      { id = "bluesky"; name = "Bluesky"; host = "bsky.app"; icon = "applications-internet"; }
    ];
    description = ''
      Optional command-line tools bundled with ohmansy. Assign a list to replace
      these defaults, or an empty list to omit them. Add unrelated software with
      environment.systemPackages.
    '';
  };

  config = {
    services.flatpak.enable = lib.mkDefault true;
    programs.firefox.enable = lib.mkDefault true;
    programs.chromium.enable = lib.mkDefault true;
    programs.fish.enable = lib.mkDefault true;
    # Keep activation with the optional bundle, including when a host replaces it.
    programs.bash.interactiveShellInit = lib.mkIf (builtins.elem pkgs.mise config.ohmansy.software.packages) ''
      eval "$(${lib.getExe pkgs.mise} activate bash)"
    '';
    programs.zsh.interactiveShellInit = lib.mkIf (builtins.elem pkgs.mise config.ohmansy.software.packages) ''
      eval "$(${lib.getExe pkgs.mise} activate zsh)"
    '';
    programs.fish.interactiveShellInit = lib.mkIf (builtins.elem pkgs.mise config.ohmansy.software.packages) ''
      ${lib.getExe pkgs.mise} activate fish | source
    '';
    programs.nix-ld = {
      enable = true;
      # Downloaded GTK apps need these libraries outside their Nix wrappers.
      libraries = with pkgs; [
        gtk3
        glib
        pango
        atk
        cairo
        gdk-pixbuf
        fontconfig
        freetype
        dbus
        alsa-lib
        libx11
        libxcb
        # Includes both libxkbcommon.so and libxkbcommon-x11.so.
        libxkbcommon
        libxcomposite
        libxcursor
        libxdamage
        libxext
        libxfixes
        libxi
        libxrandr
        libxrender
      ];
    };
    programs.appimage = {
      enable = lib.mkDefault true;
      binfmt = lib.mkDefault true;
    };
    environment.localBinInPath = lib.mkDefault true;
    # Bash already defines a priority-1000 default. A normal host definition
    # still wins over this preference. Disabling Fish restores NixOS's default.
    users.defaultUserShell = lib.mkIf config.programs.fish.enable (lib.mkOverride 900 pkgs.fish);
    # The NixOS Chromium module configures policies but does not install it.
    environment.systemPackages = config.ohmansy.software.packages
      ++ lib.optional config.programs.chromium.enable pkgs.chromium;
  };
}
