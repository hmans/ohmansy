{ config, lib, pkgs, ... }:
let
  setup = pkgs.writeShellApplication {
    name = "ohmansy-first-boot";
    runtimeInputs = [ pkgs.python3 pkgs.shadow pkgs.coreutils pkgs.systemd ];
    text = ''exec python3 ${./first-boot}/backend.py ${lib.getExe config.users.defaultUserShell}'';
  };
in {
  users.mutableUsers = true;
  services.displayManager.autoLogin.enable = false;
  environment.etc."ohmansy/first-boot".source = ./first-boot;
  systemd.tmpfiles.rules = [ "d /var/lib/ohmansy 0755 root root -" ];
  # The UI runs as greetd's unprivileged greeter. Only this socket reaches root.
  systemd.sockets.ohmansy-first-boot = {
    wantedBy = [ "sockets.target" ];
    socketConfig = {
      ListenStream = "/run/ohmansy-first-boot.sock";
      SocketMode = "0600";
      SocketUser = "greeter";
      RemoveOnStop = true;
    };
  };
  systemd.services.ohmansy-first-boot = {
    description = "Create the Ohmansy owner account";
    requires = [ "post-boot.service" ];
    after = [ "post-boot.service" ];
    unitConfig.ConditionPathExists = "!/var/lib/ohmansy/provisioned";
    serviceConfig = {
      Type = "simple";
      ExecStart = "${setup}/bin/ohmansy-first-boot";
      StandardOutput = "journal";
      StandardError = "journal";
      UMask = "0077";
      Restart = "on-failure";
      RestartSec = 2;
    };
  };
  systemd.services.greetd.requires = [ "ohmansy-first-boot.socket" "post-boot.service" ];
  systemd.services.greetd.after = [ "ohmansy-first-boot.socket" "post-boot.service" ];
  boot.consoleLogLevel = lib.mkDefault 3;
  boot.kernelParams = [ "quiet" "systemd.show_status=false" ];
}
