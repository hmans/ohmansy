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
    exec = "sudo ${installer}/bin/ohmansy-install";
    terminal = true;
    icon = "system-software-install";
    categories = [ "System" ];
  };
  panelInstaller = pkgs.writeShellScript "ohmansy-panel-install" ''
    exec ${pkgs.xdg-terminal-exec}/bin/xdg-terminal-exec sudo ${installer}/bin/ohmansy-install
  '';
in {
  environment.systemPackages = [ installer launcher ];
  environment.etc."ohmansy/source/flake.nix".source = ../../flake.nix;
  environment.etc."ohmansy/source/flake.lock".source = ../../flake.lock;
  environment.etc."ohmansy/source/nix".source = ../.;
  # Live-only launcher button; installed desktops retain the normal panel.
  systemd.user.services.quickshell.environment.OHMANSY_INSTALLER = "${panelInstaller}";
}
