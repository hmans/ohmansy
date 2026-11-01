{ pkgs, ... }:
let
  installer = pkgs.writeShellApplication {
    name = "ohmansy-install";
    runtimeInputs = with pkgs; [ python3 util-linux parted dosfstools e2fsprogs systemd nixos-install-tools ];
    text = ''exec python3 ${./installer/install.py} "$@"'';
  };
  launcher = pkgs.makeDesktopItem {
    name = "ohmansy-install";
    desktopName = "Install Ohmansy";
    comment = "Install Ohmansy to a blank virtual disk";
    exec = "${pkgs.foot}/bin/foot --title=Install-Ohmansy sudo ${installer}/bin/ohmansy-install";
    icon = "system-software-install";
    categories = [ "System" ];
  };
in {
  environment.systemPackages = [ installer launcher ];
  environment.etc."ohmansy/source/flake.nix".source = ../../flake.nix;
  environment.etc."ohmansy/source/flake.lock".source = ../../flake.lock;
  environment.etc."ohmansy/source/nix".source = ../.;
  # Live-only launcher button; installed desktops retain the normal panel.
  environment.etc."xdg/waybar/config".text = builtins.toJSON (
    (builtins.fromJSON (builtins.readFile ./desktop/waybar.json)) // {
      modules-left = [ "custom/launcher" "custom/install" "niri/workspaces" ];
      "custom/install" = {
        format = "Install Ohmansy";
        on-click = "${pkgs.foot}/bin/foot --title=Install-Ohmansy sudo ${installer}/bin/ohmansy-install";
        tooltip = false;
      };
    }
  );
}
