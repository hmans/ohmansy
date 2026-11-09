{ config, lib, ... }:
{
  options.ohmansy.apps.onepassword.enable = lib.mkEnableOption "1Password with browser and CLI integration";

  config = lib.mkIf config.ohmansy.apps.onepassword.enable {
    # Upstream modules install the privileged browser and CLI helpers.
    # Policy owners and the unfree license policy belong to the host.
    programs._1password.enable = true;
    programs._1password-gui.enable = true;
    security.polkit.enable = true;
  };
}
