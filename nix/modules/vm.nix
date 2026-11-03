{ config, lib, pkgs, ... }:
{
  options.ohmansy.vm.displayScale = lib.mkOption {
    type = lib.types.numbers.positive;
    default = if pkgs.stdenv.hostPlatform.isAarch64 then 2 else 1;
    description = "Niri display scale for the VM desktop and setup/login screen.";
  };

  config = {
    # Guest integration only; disk layout and user accounts belong to each host.
    boot.initrd.availableKernelModules = [ "virtio_pci" "virtio_blk" "xhci_pci" "usbhid" ];
    services.logind.settings.Login.HandlePowerKey = "poweroff";
    # logind grants the active local user access; no world-writable device or root agent.
    services.udev.packages = [ (pkgs.writeTextFile {
      name = "ohmansy-clipboard-udev";
      destination = "/lib/udev/rules.d/70-ohmansy-clipboard.rules";
      text = ''
        SUBSYSTEM=="virtio-ports", ATTR{name}=="dev.ohmansy.clipboard", TAG+="uaccess"
      '';
    }) ];
    systemd.user.services.ohmansy-host-clipboard = {
      description = "Ohmansy host text clipboard";
      wantedBy = [ "niri.service" ];
      after = [ "niri.service" ];
      partOf = [ "niri.service" ];
      path = [ pkgs.wl-clipboard ];
      serviceConfig = {
        ExecStart = "${pkgs.python3}/bin/python3 ${./vm/clipboard.py}";
        Restart = "on-failure";
        RestartSec = 2;
        UMask = "0077";
      };
    };
    # The Mac VM uses Retina scaling; native x86 VM windows default to 100%.
    environment.etc."ohmansy/greeter-output.kdl".text = ''
      output "Virtual-1" { scale ${toString config.ohmansy.vm.displayScale}; }
      debug { disable-cursor-plane; }
    '';
    environment.etc."ohmansy/niri.kdl".text = lib.mkForce (builtins.replaceStrings
      [ "@SCALE@" ] [ (toString config.ohmansy.vm.displayScale) ]
      (builtins.readFile ./desktop/vm.kdl));
  };
}
