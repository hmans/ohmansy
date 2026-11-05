{ config, lib, pkgs, ... }:
let
  flathub = pkgs.fetchurl {
    url = "https://dl.flathub.org/repo/flathub.flatpakrepo";
    hash = "sha256-M3HdJQ5h2eFjNjAHP+/aFTzUQm9y9K+gwzc64uj+oDo=";
  };
in {
  config = lib.mkIf config.services.flatpak.enable {
    xdg.portal.enable = lib.mkDefault true;
    xdg.portal.extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
    xdg.portal.config.common.default = lib.mkDefault [ "gtk" ];

    # Register the remote locally; downloads remain a user's explicit choice.
    systemd.user.services.ohmansy-flathub = {
      description = "Set up Flathub for this user";
      wantedBy = [ "default.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${config.services.flatpak.package}/bin/flatpak remote-add --user --if-not-exists flathub ${flathub}";
        RemainAfterExit = true;
        Restart = "on-failure";
        RestartSec = 60;
        TimeoutStartSec = 30;
      };
    };
  };
}
