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
    && config.programs.dconf.profiles.user.enableUserDb
    && builtins.any (database:
      database.settings."org/gnome/desktop/interface".color-scheme or null == "prefer-dark"
      && !database.lockAll && database.locks == []
    ) config.programs.dconf.profiles.user.databases
    && config.systemd.user.services.ohmansy-live-scale.serviceConfig.Type == "oneshot"
    && builtins.all (user: !user.isNormalUser || user.name == "nixos")
      (builtins.attrValues config.users.users);
in
assert builtins.all safe configs;
assert pcNvidia.config.hardware.nvidia.open;
assert pcNvidia.config.hardware.nvidia.modesetting.enable;
assert pcNvidia.config.services.xserver.videoDrivers == [ "nvidia" ];
assert !pcLive.config.hardware.nvidia.enabled;
pkgs.runCommand "ohmansy-live-pc-policy" {
  nativeBuildInputs = [ pkgs.niri pkgs.python3 pkgs.dconf pkgs.dbus ];
} ''
  export HOME="$TMPDIR/home"
  export XDG_DATA_DIRS=${pkgs.dconf}/share
  mkdir -p "$HOME"
  ${lib.concatMapStringsSep "\n" (config: ''
    bash -n ${config.systemd.user.services.ohmansy-live-scale.serviceConfig.ExecStart}
    python3 ${./niri-shortcuts.py} \
      ${config.environment.etc."ohmansy/niri.kdl".source} \
      ${config.environment.etc."ohmansy/desktop.kdl".source} \
      ${../modules/desktop/shortcuts.json}
  '') configs}
  # Fresh users start dark; a local preference overrides it and reset restores it.
  export DCONF_PROFILE=${pcLive.config.environment.etc.dconf.source}/profile/user
  test "$(dconf read /org/gnome/desktop/interface/color-scheme)" = "'prefer-dark'"
  dbus-run-session --config-file=${pkgs.dbus}/share/dbus-1/session.conf -- bash -eu <<'CHECK'
  dconf write /org/gnome/desktop/interface/color-scheme "'prefer-light'"
  test "$(dconf read /org/gnome/desktop/interface/color-scheme)" = "'prefer-light'"
  dconf reset /org/gnome/desktop/interface/color-scheme
  test "$(dconf read /org/gnome/desktop/interface/color-scheme)" = "'prefer-dark'"
  CHECK
  touch "$out"
''
