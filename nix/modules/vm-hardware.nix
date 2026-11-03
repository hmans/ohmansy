{ lib, pkgs, ... }: {
  boot.loader.systemd-boot.enable = true;
  boot.loader.systemd-boot.consoleMode = "auto";
  boot.loader.efi.canTouchEfiVariables = false;
  boot.growPartition = true;
  boot.kernelParams = [
    "console=${if pkgs.stdenv.hostPlatform.isAarch64 then "ttyAMA0" else "ttyS0"},115200"
    "console=tty0"
  ];
  fileSystems = {
    "/" = { device = "/dev/disk/by-label/ohmansy"; fsType = "ext4"; autoResize = true; };
    "/boot" = { device = "/dev/disk/by-label/ESP"; fsType = "vfat"; };
  };
  services.openssh.enable = lib.mkDefault false;
}
