{ pkgs, ... }:
{
  imports = [ ./live.nix ../modules/vm.nix ];
  boot.kernelParams = [
    "console=${if pkgs.stdenv.hostPlatform.isAarch64 then "ttyAMA0" else "ttyS0"},115200"
    "console=tty0"
  ];
}
