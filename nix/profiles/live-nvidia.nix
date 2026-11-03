{ config, lib, pkgs, ... }:
{
  imports = [ ./live-pc.nix ];
  image.baseName = lib.mkForce "ohmansy-0.1.0-live-nvidia-${pkgs.stdenv.hostPlatform.system}";

  # NVIDIA's open kernel module supports Turing and newer GPUs, including
  # the RTX 3060 Ti. The matching userspace driver remains proprietary.
  nixpkgs.config.allowUnfreePredicate = package:
    builtins.elem (lib.getName package) [ "nvidia-x11" "nvidia-settings" ];
  services.xserver.videoDrivers = [ "nvidia" ];
  hardware.nvidia = {
    open = true;
    modesetting.enable = true;
    package = config.boot.kernelPackages.nvidiaPackages.stable;
  };
}
