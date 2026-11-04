{ pkgs, installedSystem, ... }:
let
  installer = pkgs.writeShellApplication {
    name = "ohmansy-install";
    runtimeInputs = with pkgs; [ python3 util-linux parted dosfstools e2fsprogs systemd nixos-install-tools ];
    text = ''exec python3 ${./installer/install.py} "$@"'';
  };
  terminalInstaller = pkgs.writeShellScript "ohmansy-install-terminal" ''
    status=0
    sudo ${installer}/bin/ohmansy-install || status=$?
    printf '\n'
    read -r -p 'Press Enter to close this window.' reply || true
    exit "$status"
  '';
  launcher = pkgs.makeDesktopItem {
    name = "ohmansy-install";
    desktopName = "Install Ohmansy";
    comment = "Install Ohmansy by erasing a selected disk";
    exec = "${terminalInstaller}";
    terminal = true;
    icon = "system-software-install";
    categories = [ "System" ];
  };
  panelInstaller = pkgs.writeShellScript "ohmansy-panel-install" ''
    exec ${pkgs.xdg-terminal-exec}/bin/xdg-terminal-exec ${terminalInstaller}
  '';
in {
  # A local serial console also lets VM tests drive the real installer without
  # injecting commands through a graphical terminal or enabling remote access.
  systemd.services."serial-getty@ttyS0".wantedBy = [ "getty.target" ];
  environment.systemPackages = [ installer launcher ];
  isoImage.storeContents = [ installedSystem ];
  environment.etc."ohmansy/installed-system".source = installedSystem;
  environment.etc."ohmansy/installation".source = import ./installation-package.nix { inherit pkgs; };
  # Live-only launcher button; installed desktops retain the normal panel.
  systemd.user.services.quickshell.environment.OHMANSY_INSTALLER = "${panelInstaller}";
}
