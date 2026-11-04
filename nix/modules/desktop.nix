{ config, pkgs, lib, ... }:
let
  shell = import ./desktop-package.nix {
    inherit pkgs;
    syncFootTheme = lib.getName config.ohmansy.terminal.package == "foot";
  };
  wallpaper = import ./wallpaper-package.nix { inherit pkgs; };
  desktop = import ./desktop-actions.nix { inherit pkgs; };
  displays = import ./display-package.nix { inherit pkgs; };
  shortcutGroups = builtins.fromJSON (builtins.readFile ./desktop/shortcuts.json);
  shortcutBindings = lib.concatMap (group: group.bindings) shortcutGroups;
  renderBinding = binding:
    "  ${binding.key} ${binding.options or ""} hotkey-overlay-title=${builtins.toJSON binding.title} { ${binding.action}; }";
in {
  imports = [ ./greeter.nix ./terminal.nix ./compositor.nix ];
  networking.hostName = lib.mkDefault "ohmansy";
  networking.networkmanager.enable = true;
  time.timeZone = lib.mkDefault "UTC";
  i18n.defaultLocale = lib.mkDefault "en_US.UTF-8";
  console.keyMap = lib.mkDefault "us";
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  programs.niri.enable = true;
  # Fresh accounts start dark; a user's appearance choice still takes priority.
  programs.dconf.enable = true;
  programs.dconf.profiles.user.databases = [{
    settings."org/gnome/desktop/interface".color-scheme = "prefer-dark";
  }];
  # NixOS enables speech synthesis for graphical desktops by default, pulling
  # in the full MBROLA voice collection. Keep it opt-in for Ohmansy; a host's
  # ordinary services.speechd.enable = true still overrides this default.
  services.speechd.enable = lib.mkOverride 900 false;
  services.displayManager.defaultSession = lib.mkDefault "niri";
  security.polkit.enable = true;
  security.rtkit.enable = true;
  security.pam.services.swaylock = {};
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    pulse.enable = true;
  };
  hardware.graphics.enable = true;
  hardware.bluetooth.enable = lib.mkDefault true;
  fonts.packages = with pkgs; [ inter jetbrains-mono ibm-plex ];

  # No account, credentials, machine identifiers, or personal services here.
  environment.systemPackages = with pkgs; [
    desktop displays quickshell mako swaybg swaylock nautilus
    playerctl wireplumber
    xwayland-satellite adwaita-icon-theme wl-clipboard
  ];
  environment.sessionVariables.NIRI_CONFIG = lib.mkDefault "/etc/ohmansy/niri.kdl";
  environment.etc."xdg/mako/config".text = ''
    max-history=100
  '';
  systemd.user.services.ohmansy-lock = {
    description = "Ohmansy screen lock";
    after = [ "niri.service" ];
    partOf = [ "niri.service" ];
    serviceConfig = {
      Type = "forking";
      ExecStart = "${pkgs.swaylock}/bin/swaylock --daemonize --ignore-empty-password --color 171a21";
    };
  };
  systemd.user.services.ohmansy-clipboard = {
    description = "Ohmansy clipboard history";
    wantedBy = [ "niri.service" ];
    after = [ "niri.service" ];
    partOf = [ "niri.service" ];
    serviceConfig = {
      ExecStart = "${pkgs.wl-clipboard}/bin/wl-paste --watch ${pkgs.cliphist}/bin/cliphist store";
      Restart = "on-failure";
      UMask = "0077";
    };
  };
  systemd.user.services.ohmansy-displays = {
    description = "Restore saved display settings";
    wantedBy = [ "niri.service" ];
    after = [ "niri.service" ];
    before = [ "quickshell.service" "ohmansy-wallpaper.service" ];
    partOf = [ "niri.service" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${displays}/bin/ohmansy-displays restore";
      RemainAfterExit = true;
    };
  };
  environment.etc."ohmansy/niri.kdl".text = ''
    include "/etc/ohmansy/desktop.kdl"
    include optional=true "~/.local/state/ohmansy/niri-appearance.kdl"
  '';
  environment.etc."ohmansy/desktop.kdl".text =
    builtins.readFile ./desktop/niri.kdl
    + "\nbinds {\n" + lib.concatMapStringsSep "\n" renderBinding shortcutBindings + "\n}\n";
  environment.etc."ohmansy/shortcuts.json".source = ./desktop/shortcuts.json;
  environment.etc."ohmansy/wallpaper.png".source = lib.mkDefault ./desktop/wallpapers/twilight-cat.png;
  systemd.user.services.ohmansy-wallpaper = {
    description = "Ohmansy desktop wallpaper";
    wantedBy = [ "niri.service" ];
    after = [ "niri.service" ];
    partOf = [ "niri.service" ];
    serviceConfig = {
      ExecStart = "${wallpaper}/bin/ohmansy-wallpaper";
      Restart = "on-failure";
      RestartSec = 2;
    };
  };
  environment.etc."xdg/quickshell/ohmansy".source = ./desktop/quickshell;
  systemd.user.services.quickshell = {
    description = "Ohmansy desktop panel";
    wantedBy = [ "niri.service" ];
    after = [ "niri.service" ];
    partOf = [ "niri.service" ];
    # Desktop entries often use bare command names. Include the user's and
    # system's installed apps, not just the panel's own helper programs.
    path = [
      "/run/wrappers"
      "%h/.nix-profile"
      "/nix/profile"
      "%h/.local/state/nix/profile"
      "/etc/profiles/per-user/%u"
      "/nix/var/nix/profiles/default"
      "/run/current-system/sw"
    ] ++ (with pkgs; [ niri networkmanager ]);
    serviceConfig = {
      ExecStart = "${shell}/bin/ohmansy-quickshell --path /etc/xdg/quickshell/ohmansy/shell.qml";
      Restart = "on-failure";
      RestartSec = 2;
    };
  };
  systemd.user.services.ohmansy-polkit = {
    description = "Ohmansy desktop authentication agent";
    wantedBy = [ "niri.service" ];
    after = [ "niri.service" ];
    partOf = [ "niri.service" ];
    serviceConfig = {
      ExecStart = "${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1";
      Restart = "on-failure";
    };
  };
}
