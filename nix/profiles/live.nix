{ lib, pkgs, modulesPath, ... }:
{
  imports = [
    (modulesPath + "/installer/cd-dvd/installation-cd-base.nix")
    ../modules/default.nix
    (import ../modules/image-policy.nix { live = true; })
  ];
  system.stateVersion = "26.05";
  isoImage = {
    edition = "ohmansy";
    volumeID = "OHMANSY_LIVE";
    squashfsCompression = "zstd -Xcompression-level 6";
  };
  image.baseName = lib.mkDefault "ohmansy-0.1.0-live-${pkgs.stdenv.hostPlatform.system}";
  boot.zfs.forceImportRoot = false;
  # Disposable local live session. No remote login and no persistent credentials.
  services.openssh.enable = lib.mkForce false;
  services.displayManager.autoLogin = { enable = true; user = "nixos"; };
  documentation.nixos.enable = lib.mkForce false;
  documentation.man.enable = lib.mkForce false;
}
