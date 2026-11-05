{ config, lib, ... }:
{
  # NVIDIA's official open kernel module supports Turing and newer GPUs.
  # Its matching userspace driver, including NVML, remains proprietary.
  nixpkgs.config.allowUnfreePredicate = package:
    builtins.elem (lib.getName package) [ "nvidia-x11" "nvidia-settings" ];
  services.xserver.videoDrivers = [ "nvidia" ];
  hardware.nvidia = {
    open = true;
    modesetting.enable = true;
    package = config.boot.kernelPackages.nvidiaPackages.stable;
  };
  # Nixpkgs only adds /run/opengl-driver/lib to btop's runtime search path
  # with this package option. It does not pull in the CUDA toolkit.
  nixpkgs.overlays = [ (_final: prev: {
    btop = prev.btop.override { cudaSupport = true; };
  }) ];
}
