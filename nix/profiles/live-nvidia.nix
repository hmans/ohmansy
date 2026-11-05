{ lib, pkgs, ... }:
{
  imports = [ ./live-pc.nix ../modules/nvidia.nix ];
  image.baseName = lib.mkForce "ohmansy-0.1.0-live-nvidia-${pkgs.stdenv.hostPlatform.system}";
}
