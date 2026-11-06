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
    enableKeyring = config.services.gnome.gnome-keyring.enable;
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
    # 0.8.2 passes NULL here when a software-rendered compositor has no
    # DMA-BUF feedback. Keep its shared-memory screencopy path available.
    nixpkgs.overlays = [ (_final: prev: {
      xdg-desktop-portal-wlr = prev.xdg-desktop-portal-wlr.overrideAttrs (old: {
        patches = (old.patches or []) ++ lib.optionals (old.version == "0.8.2") [
          ./portal-wlr-shm.patch
          ./portal-wlr-capture-lifetime.patch
        ];
      });
    }) ];
    # Shine implements standard display/window capture and wlr-screencopy.
    # GTK remains responsible for file
    # choosers, settings and the other desktop portals.
    xdg.portal = {
      extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
      config.ohmansy = {
        default = lib.mkDefault [ "gtk" ];
        "org.freedesktop.impl.portal.ScreenCast" = [ "wlr" ];
        "org.freedesktop.impl.portal.Secret" = lib.mkIf config.services.gnome.gnome-keyring.enable [ "gnome-keyring" ];
      };
      wlr = {
        enable = true;
        settings.screencast = {
          max_fps = 30;
          chooser_type = "dmenu";
          chooser_cmd = "${pkgs.wofi}/bin/wofi --normal-window --dmenu --prompt 'Share a display or window'";
        };
      };
    };
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
