{ lib, pkgs, ... }:
{
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
  # Match desktop scaling and draw the cursor in the composited VM image.
  environment.etc."ohmansy/greeter-output.kdl".text = ''
    output "Virtual-1" { scale 2; }
    debug { disable-cursor-plane; }
  '';
  environment.etc."ohmansy/niri.kdl".text = lib.mkForce (builtins.readFile ./desktop/vm.kdl);
}
