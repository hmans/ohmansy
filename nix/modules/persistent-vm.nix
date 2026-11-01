{ lib, ... }:
{
  imports = [ ./desktop.nix ./vm.nix ];
  system.stateVersion = "26.05";
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = false;
  boot.growPartition = true;
  boot.kernelParams = [ "console=ttyAMA0,115200" "console=tty0" ];
  fileSystems = {
    "/" = { device = "/dev/disk/by-label/ohmansy"; fsType = "ext4"; autoResize = true; };
    "/boot" = { device = "/dev/disk/by-label/ESP"; fsType = "vfat"; };
  };
  services.openssh.enable = lib.mkDefault false;
}
