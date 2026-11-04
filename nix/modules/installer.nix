{ config, pkgs, lib, installedSystem, ... }:
let
  runtimeInputs = with pkgs; [ python3 util-linux parted dosfstools e2fsprogs systemd nixos-install-tools config.nix.package ];
  installer = pkgs.writeShellApplication {
    name = "ohmansy-install";
    inherit runtimeInputs;
    text = ''exec python3 ${./installer}/install.py "$@"'';
  };
  backend = pkgs.writeShellApplication {
    name = "ohmansy-installer-service";
    inherit runtimeInputs;
    text = ''exec python3 ${./installer}/backend.py'';
  };
  graphicalInstaller = pkgs.writeShellScriptBin "ohmansy-installer" ''
    exec ${pkgs.util-linux}/bin/flock -n "$XDG_RUNTIME_DIR/ohmansy-installer-ui.lock" \
      ${import ./greeter-package.nix { inherit pkgs; }}/bin/quickshell --path ${./installer}/shell.qml
  '';
  launcher = pkgs.makeDesktopItem {
    name = "ohmansy-install";
    desktopName = "Install Ohmansy";
    comment = "Install Ohmansy by erasing a selected disk";
    exec = "${graphicalInstaller}/bin/ohmansy-installer";
    terminal = false;
    icon = "system-software-install";
    categories = [ "System" ];
  };
in {
  # A local serial console also lets VM tests drive the real installer without
  # injecting commands through a graphical terminal or enabling remote access.
  systemd.services."serial-getty@ttyS0".wantedBy = [ "getty.target" ];
  environment.systemPackages = [ installer graphicalInstaller launcher ];
  environment.etc."ohmansy/desktop.kdl".text = lib.mkAfter ''
    window-rule {
      match title="^Install Ohmansy$"
      default-column-width { proportion 1.0; }
    }
  '';
  systemd.sockets.ohmansy-installer = {
    wantedBy = [ "sockets.target" ];
    socketConfig = {
      ListenStream = "/run/ohmansy-installer.sock";
      SocketMode = "0600";
      SocketUser = "nixos";
      RemoveOnStop = true;
    };
  };
  systemd.services.ohmansy-installer = {
    description = "Install Ohmansy from the live image";
    serviceConfig = {
      ExecStart = "${backend}/bin/ohmansy-installer-service";
      RuntimeDirectory = "ohmansy-installer";
      RuntimeDirectoryMode = "0700";
      RuntimeDirectoryPreserve = "yes";
      UMask = "0077";
      Restart = "on-failure";
      RestartSec = 2;
    };
  };
  isoImage.storeContents = [ installedSystem ];
  environment.etc."ohmansy/installed-system".source = installedSystem;
  environment.etc."ohmansy/installation".source = import ./installation-package.nix { inherit pkgs; };
  # Live-only launcher button; installed desktops retain the normal panel.
  systemd.user.services.quickshell.environment.OHMANSY_INSTALLER = "${graphicalInstaller}/bin/ohmansy-installer";
}
