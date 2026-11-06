{ config, lib, pkgs, ... }:
let
  cfg = config.ohmansy.apps.obs;
in {
  options.ohmansy.apps.obs = {
    enable = lib.mkEnableOption "OBS Studio with browser sources";
    virtualCamera.enable = lib.mkEnableOption "the OBS virtual camera kernel module";
  };

  config = lib.mkIf cfg.enable {
    programs.obs-studio = {
      enable = true;
      # Browser sources are built into OBS in our pinned Nixpkgs.
      package = lib.mkDefault (pkgs.obs-studio.override { browserSupport = true; });
      enableVirtualCamera = cfg.virtualCamera.enable;
    };
  };
}
