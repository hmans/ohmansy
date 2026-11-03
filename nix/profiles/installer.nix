{ lib, pkgs, ... }:
{
  imports = [ ./live-vm.nix ../modules/installer.nix ];
  image.baseName = lib.mkForce "ohmansy-0.1.0-installer-${pkgs.stdenv.hostPlatform.system}";
}
