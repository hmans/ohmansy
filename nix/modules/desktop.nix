{ pkgs, lib, ... }:
let shell = import ./desktop-package.nix { inherit pkgs; };
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
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    pulse.enable = true;
  };
  hardware.graphics.enable = true;
  programs.firefox.enable = true;
  fonts.packages = with pkgs; [ inter jetbrains-mono ibm-plex ];

  # No account, credentials, machine identifiers, or personal services here.
  environment.systemPackages = with pkgs; [
    foot fuzzel quickshell mako swaybg swaylock nautilus
    xwayland-satellite adwaita-icon-theme wl-clipboard
    git vim curl jq python3
  ];
  environment.sessionVariables.NIRI_CONFIG = lib.mkDefault "/etc/ohmansy/niri.kdl";
  environment.etc."ohmansy/niri.kdl".source = ./desktop/niri.kdl;
  environment.etc."ohmansy/wallpaper.png".source = lib.mkDefault ./desktop/wallpapers/twilight-cat.png;
  systemd.user.services.ohmansy-wallpaper = {
    description = "Ohmansy desktop wallpaper";
    wantedBy = [ "niri.service" ];
    after = [ "niri.service" ];
    partOf = [ "niri.service" ];
    serviceConfig = {
      ExecStart = "${pkgs.swaybg}/bin/swaybg --image /etc/ohmansy/wallpaper.png --mode fill --color '#171c29'";
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
    path = with pkgs; [ niri fuzzel foot networkmanager ];
    serviceConfig = {
      ExecStart = "${shell}/bin/ohmansy-quickshell --path /etc/xdg/quickshell/ohmansy/shell.qml";
      Restart = "on-failure";
      RestartSec = 2;
    };
  };
  environment.etc."xdg/foot/foot.ini".text = ''
    [main]
    font=JetBrains Mono:size=11
    [colors]
    background=171a21
    foreground=e6e9ef
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
