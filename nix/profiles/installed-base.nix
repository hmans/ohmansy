{ pkgs, ... }: {
  imports = [
    ../modules/default.nix
    ../modules/first-boot.nix
    (import ../modules/image-policy.nix {})
  ];
  system.stateVersion = "26.05";
  # A generic bootable payload, not the live image or the Mac VM profile.
  hardware.enableAllHardware = true;
  hardware.enableRedistributableFirmware = true;
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  fileSystems = {
    "/" = { device = "/dev/disk/by-label/OHMANSY_ROOT"; fsType = "ext4"; };
    "/boot" = { device = "/dev/disk/by-label/OHMANSY_EFI"; fsType = "vfat"; options = [ "umask=0077" ]; };
  };
  # The installer writes the chosen hostname without evaluating a new system.
  networking.hostName = "";
  services.openssh.enable = false;
  environment.etc."ohmansy/installation".source = import ../modules/installation-package.nix { inherit pkgs; };
}
