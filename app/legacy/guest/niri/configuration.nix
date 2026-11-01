# VM adapter for the separate flakey checkout. Use the installed NixOS channel.
{ lib, pkgs, ... }:
let
  flakey = /home/hmans/flakey;
  homeManager = builtins.fetchTarball {
    url = "https://github.com/nix-community/home-manager/archive/24f8f8e786f87d6a818e1746cb2389bf922afdab.tar.gz";
  };
in
{
  imports = [
    ../ssh/configuration.nix
    (flakey + "/modules/niri.nix")
    (homeManager + "/nixos")
  ];

  # Provide the layout alias used by flakey without changing GNOME's keymap.
  services.xserver.xkb.extraLayouts.eurkey = {
    description = "EurKEY (US)";
    languages = [ "eng" ];
    symbolsFile = pkgs.xkeyboard_config + "/share/X11/xkb/symbols/eu";
  };

  # The PC remapper assumes a Windows keyboard. Keep the Mac's modifiers.
  systemd.user.services.niri-super-tap.enable = lib.mkForce false;

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    backupFileExtension = "before-ohmansy-niri";
    users.hmans = { lib, ... }: {
      imports = [ (flakey + "/home/niri.nix") ];
      home.username = "hmans";
      home.homeDirectory = "/home/hmans";
      home.stateVersion = "26.05";

      xdg.configFile."niri/config.kdl".source = lib.mkForce (
        pkgs.writeText "ohmansy-niri.kdl" (builtins.replaceStrings
          [ "altwin:swap_lalt_lwin," "debug {" "spawn \"ghostty\"" ]
          [ "" "debug {\n    disable-cursor-plane" "spawn \"kgx\"" ]
          (builtins.readFile (flakey + "/home/niri/config.kdl")))
      );
      # Do not pin a mode: QEMU supplies modes when the host window changes.
      xdg.configFile."niri/outputs.kdl".source = lib.mkForce (
        pkgs.writeText "ohmansy-outputs.kdl" ''
          output "Virtual-1" {
              scale 2
          }
        ''
      );
    };
  };
}
