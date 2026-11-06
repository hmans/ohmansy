{ lib, ... }:
{
  services.netbird = {
    enable = lib.mkDefault true;
    ui.enable = lib.mkDefault true;
  };
}
