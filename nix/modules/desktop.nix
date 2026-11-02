{ pkgs, lib, ... }:
let
  shell = import ./desktop-package.nix { inherit pkgs; };
  terminal = import ./terminal-package.nix { inherit pkgs; };
  wallpaper = import ./wallpaper-package.nix { inherit pkgs; };
  desktop = import ./desktop-actions.nix { inherit pkgs; };
  shortcutGroups = builtins.fromJSON (builtins.readFile ./desktop/shortcuts.json);
  shortcutBindings = lib.concatMap (group: group.bindings) shortcutGroups;
  renderBinding = binding:
    "  ${binding.key} ${binding.options or ""} hotkey-overlay-title=${builtins.toJSON binding.title} { ${binding.action}; }";
in {
  imports = [ ./greeter.nix ];
  networking.hostName = lib.mkDefault "ohmansy";
  networking.networkmanager.enable = true;
  time.timeZone = lib.mkDefault "UTC";
  i18n.defaultLocale = lib.mkDefault "en_US.UTF-8";
  console.keyMap = lib.mkDefault "us";
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  programs.niri.enable = true;
  services.displayManager.defaultSession = "niri";
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
  programs.firefox.enable = true;
  fonts.packages = with pkgs; [ inter jetbrains-mono ibm-plex ];

  # No account, credentials, machine identifiers, or personal services here.
  environment.systemPackages = with pkgs; [
    terminal desktop quickshell mako swaybg swaylock nautilus
    playerctl wireplumber
    xwayland-satellite adwaita-icon-theme wl-clipboard
    git vim curl jq python3
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
  environment.etc."xdg/xdg-terminals.list".text = lib.mkDefault "foot.desktop\n";
  environment.etc."ohmansy/niri.kdl".text = ''
    include "/etc/ohmansy/desktop.kdl"
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
    ] ++ [ terminal ] ++ (with pkgs; [ niri networkmanager ]);
    serviceConfig = {
      ExecStart = "${shell}/bin/ohmansy-quickshell --path /etc/xdg/quickshell/ohmansy/shell.qml";
      Restart = "on-failure";
      RestartSec = 2;
    };
  };
  environment.etc."xdg/foot/foot.ini".text = ''
    [main]
    font=JetBrains Mono:size=11
    pad=16x14
    [colors-dark]
    alpha=0.85
    blur=yes
    background=202020
    foreground=f5f5f5
    regular0=202020
    regular1=e78284
    regular2=a6d189
    regular3=e5c890
    regular4=8caaee
    regular5=c4a7e7
    regular6=81c8be
    regular7=c6c6cc
    bright0=777780
    bright1=efa0a2
    bright2=b9df9e
    bright3=f2d8a5
    bright4=a6bdf5
    bright5=d6bff0
    bright6=9bdad2
    bright7=ffffff
    [colors-light]
    alpha=0.85
    blur=yes
    background=ffffff
    foreground=202024
    regular0=202024
    regular1=a33340
    regular2=356b32
    regular3=805d14
    regular4=315ba5
    regular5=68478d
    regular6=246b70
    regular7=50505a
    bright0=62626e
    bright1=b53645
    bright2=397332
    bright3=89600e
    bright4=3567b7
    bright5=79519e
    bright6=21777d
    bright7=202024
    [key-bindings]
    color-theme-toggle=Control+Shift+t
  '';
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
