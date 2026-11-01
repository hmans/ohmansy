{ lib, ... }:
{
  imports = [ ./live.nix ../modules/installer.nix ];
  image.baseName = lib.mkForce "ohmansy-0.1.0-installer-aarch64-linux";
}
