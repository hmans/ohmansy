{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.ohmansy.compositor;
  session = import ./compositor-session-package.nix {
    inherit pkgs;
    terminal = "${config.ohmansy.terminal.launcher}/bin/ohmansy-terminal";
    xkb = config.services.xserver.xkb;
  };
in
{
  options.ohmansy.compositor.enable = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = "Offer Shine alongside Niri at login.";
  };
  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      session
      (import ./compositor-package.nix { inherit pkgs; })
    ];
    services.displayManager.sessionPackages = [ session ];
    ohmansy.greeter.sessions.ohmansy = {
      label = "Shine (experimental)";
      command = "${session}/bin/ohmansy-compositor-session";
      desktop = "ohmansy";
    };
  };
}
