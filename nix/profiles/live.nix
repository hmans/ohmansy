{ lib, modulesPath, ... }:
{
  imports = [
    (modulesPath + "/installer/cd-dvd/installation-cd-base.nix")
    ../modules/desktop.nix
    ../modules/vm.nix
  ];
  system.stateVersion = "26.05";
  isoImage = {
    edition = "ohmansy";
    volumeID = "OHMANSY_LIVE";
    squashfsCompression = "zstd -Xcompression-level 6";
  };
  image.baseName = lib.mkDefault "ohmansy-0.1.0-live-aarch64-linux";
  boot.zfs.forceImportRoot = false;
  # Disposable local live session. No remote login and no persistent credentials.
  services.openssh.enable = lib.mkForce false;
  services.displayManager.autoLogin = { enable = true; user = "nixos"; };
  boot.kernelParams = [ "console=ttyAMA0,115200" "console=tty0" ];
  documentation.nixos.enable = lib.mkForce false;
  documentation.man.enable = lib.mkForce false;
}
