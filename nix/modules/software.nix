{ config, lib, pkgs, ... }:
{
  imports = [ ./firefox-style.nix ./fish-style.nix ];
  options.ohmansy.software.packages = lib.mkOption {
    type = lib.types.listOf lib.types.package;
    default = with pkgs; [
      git
      mise
      vim
      curl
      wget
      jq
      python3
      fastfetch
      btop
      htop
    ];
    description = ''
      Optional command-line tools bundled with Ohmansy. Assign a list to replace
      these defaults, or an empty list to omit them. Add unrelated software with
      environment.systemPackages.
    '';
  };

  config = {
    programs.firefox.enable = lib.mkDefault true;
    programs.fish.enable = lib.mkDefault true;
    environment.localBinInPath = lib.mkDefault true;
    # Bash already defines a priority-1000 default. A normal host definition
    # still wins over this preference. Disabling Fish restores NixOS's default.
    users.defaultUserShell = lib.mkIf config.programs.fish.enable (lib.mkOverride 900 pkgs.fish);
    environment.systemPackages = config.ohmansy.software.packages;
  };
}
