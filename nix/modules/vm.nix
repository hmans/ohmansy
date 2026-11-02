{ lib, ... }:
{
  # Guest integration only; disk layout and user accounts belong to each host.
  boot.initrd.availableKernelModules = [ "virtio_pci" "virtio_blk" "xhci_pci" "usbhid" ];
  services.logind.settings.Login.HandlePowerKey = "poweroff";
  # Match desktop scaling and draw the cursor in the composited VM image.
  environment.etc."ohmansy/greeter-output.kdl".text = ''
    output "Virtual-1" { scale 2; }
    debug { disable-cursor-plane; }
  '';
  environment.etc."ohmansy/niri.kdl".source = lib.mkForce ./desktop/vm.kdl;
  environment.etc."ohmansy/desktop.kdl".source = ./desktop/niri.kdl;
}
