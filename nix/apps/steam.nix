{ config, lib, pkgs, ... }:
{
  options.ohmansy.apps.steam.enable = lib.mkEnableOption "Steam with desktop gaming integration";

  config = lib.mkIf config.ohmansy.apps.steam.enable {
    assertions = [{
      assertion = pkgs.stdenv.hostPlatform.system == "x86_64-linux";
      message = "The ohmansy Steam layer requires x86_64-linux.";
    }];
    # Upstream supplies the runtime, 32-bit graphics and controller rules.
    # License policy and optional firewall openings remain host decisions.
    programs.steam.enable = true;
  };
}
