{ config, lib, pkgs, ... }:
{
  imports = [ ./firefox-style.nix ./fish-style.nix ./flatpak.nix ];
  options.ohmansy.software.packages = lib.mkOption {
    type = lib.types.listOf lib.types.package;
    default = with pkgs; [
      git
      mise
      herdr
      vim
      neovim
      vscodium
      zed-editor
      curl
      wget
      jq
      gcc
      gnumake
      python3
      pkg-config
      fastfetch
      btop
      htop
      psmisc
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
    programs.nix-ld.enable = true;
    programs.appimage = {
      enable = lib.mkDefault true;
      binfmt = lib.mkDefault true;
    };
    environment.localBinInPath = lib.mkDefault true;
    # Bash already defines a priority-1000 default. A normal host definition
    # still wins over this preference. Disabling Fish restores NixOS's default.
    users.defaultUserShell = lib.mkIf config.programs.fish.enable (lib.mkOverride 900 pkgs.fish);
    environment.systemPackages = config.ohmansy.software.packages;
  };
}
