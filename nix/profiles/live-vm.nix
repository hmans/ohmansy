{ ... }:
{
  imports = [ ./live.nix ../modules/vm.nix ];
  boot.kernelParams = [ "console=ttyAMA0,115200" "console=tty0" ];
}
