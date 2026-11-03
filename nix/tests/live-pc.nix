{ nixpkgs, pkgs, pcLive, pcNvidia }:
let
  lib = nixpkgs.lib;
  configs = map (host: host.config) [ pcLive pcNvidia ];
  safe = config:
    !config.services.openssh.enable
    && config.services.greetd.settings.initial_session.user == "nixos"
    && !(config.environment.sessionVariables ? OHMANSY_INSTALLER)
    && !(config.systemd.user.services ? ohmansy-host-clipboard)
    && !(lib.hasInfix "disable-cursor-plane" config.environment.etc."ohmansy/niri.kdl".text)
    && !(lib.hasInfix "Virtual-1" config.environment.etc."ohmansy/niri.kdl".text)
    && !(builtins.elem "console=ttyAMA0,115200" config.boot.kernelParams)
    && builtins.all (user: !user.isNormalUser || user.name == "nixos")
      (builtins.attrValues config.users.users);
in
assert builtins.all safe configs;
assert pcNvidia.config.hardware.nvidia.open;
assert pcNvidia.config.hardware.nvidia.modesetting.enable;
assert pcNvidia.config.services.xserver.videoDrivers == [ "nvidia" ];
assert !pcLive.config.hardware.nvidia.enabled;
pkgs.runCommand "ohmansy-live-pc-policy" {
  nativeBuildInputs = [ pkgs.niri pkgs.python3 ];
} ''
  ${lib.concatMapStringsSep "\n" (config: ''
    python3 ${./niri-shortcuts.py} \
      ${config.environment.etc."ohmansy/niri.kdl".source} \
      ${config.environment.etc."ohmansy/desktop.kdl".source} \
      ${../modules/desktop/shortcuts.json}
  '') configs}
  touch "$out"
''
