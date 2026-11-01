{ pkgs, ... }:
let
  setup = pkgs.writeShellApplication {
    name = "ohmansy-first-boot";
    runtimeInputs = [ pkgs.python3 pkgs.shadow pkgs.coreutils pkgs.systemd ];
    text = ''exec python3 ${./first-boot/setup.py}'';
  };
in {
  users.mutableUsers = true;
  services.displayManager.autoLogin.enable = false;
  systemd.services.ohmansy-first-boot = {
    description = "Create the Ohmansy owner account";
    wantedBy = [ "multi-user.target" ];
    requires = [ "post-boot.service" ];
    after = [ "post-boot.service" ];
    before = [ "display-manager.service" "getty@tty1.service" ];
    conflicts = [ "getty@tty1.service" ];
    unitConfig.ConditionPathExists = "!/var/lib/ohmansy/provisioned";
    serviceConfig = {
      Type = "oneshot";
      TimeoutStartSec = "infinity";
      ExecStart = "${setup}/bin/ohmansy-first-boot";
      StandardInput = "tty-force";
      StandardOutput = "tty";
      StandardError = "tty";
      TTYPath = "/dev/tty1";
      TTYReset = true;
      TTYVHangup = true;
      RemainAfterExit = true;
      Restart = "on-failure";
      RestartSec = 2;
    };
  };
  systemd.services.display-manager.requires = [ "ohmansy-first-boot.service" ];
}
