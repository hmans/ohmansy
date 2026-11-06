{ config, pkgs, lib, ... }:
let
  shell = import ./desktop-package.nix {
    inherit pkgs;
    syncFootTheme = lib.getName config.ohmansy.terminal.package == "foot";
    niri = config.programs.niri.package;
    terminal = "${config.ohmansy.terminal.launcher}/bin/ohmansy-terminal";
  };
  wallpaper = import ./wallpaper-package.nix { inherit pkgs; };
  desktop = import ./desktop-actions.nix { inherit pkgs; };
  displays = import ./display-package.nix { inherit pkgs; };
  cursor = import ./cursor-theme.nix { inherit pkgs; };
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
    settings."org/gnome/desktop/interface" = {
      color-scheme = "prefer-dark";
      cursor-theme = cursor.name;
      cursor-size = lib.gvariant.mkInt32 cursor.size;
      font-name = "Source Sans 3 11";
    };
  }];
  # NixOS enables speech synthesis for graphical desktops by default, pulling
  # in the full MBROLA voice collection. Keep it opt-in for Ohmansy; a host's
  # ordinary services.speechd.enable = true still overrides this default.
  services.speechd.enable = lib.mkOverride 900 false;
  services.displayManager.defaultSession = lib.mkDefault (
    if config.ohmansy.compositor.enable then "ohmansy" else "niri"
  );
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
  # WebHID configurators need raw HID access for the active local seat user.
  # Tag before systemd's seat-late rule applies the device ACL.
  services.udev.packages = [ (pkgs.writeTextFile {
    name = "ohmansy-keychron-udev";
    destination = "/lib/udev/rules.d/70-ohmansy-keychron.rules";
    text = ''
      SUBSYSTEM=="hidraw", KERNEL=="hidraw*", ATTRS{idVendor}=="3434", TAG+="uaccess"
    '';
  }) ];
  fonts.packages = with pkgs; [ inter source-sans jetbrains-mono ibm-plex ];
  fonts.fontconfig.defaultFonts.sansSerif = lib.mkDefault [ "Source Sans 3" ];
  fonts.fontconfig.localConf = ''
    <alias binding="same">
      <family>system-ui</family>
      <prefer><family>Source Sans 3</family></prefer>
    </alias>
  '';
  # Chromium and Electron obtain their system-ui family from GTK settings.
  environment.etc."xdg/gtk-3.0/settings.ini".text = ''
    [Settings]
    gtk-font-name=Source Sans 3 11
  '';
  environment.etc."xdg/gtk-4.0/settings.ini".text = ''
    [Settings]
    gtk-font-name=Source Sans 3 11
  '';

  # No account, credentials, machine identifiers, or personal services here.
  environment.systemPackages = with pkgs; [
    desktop displays quickshell swaybg swaylock nautilus
    playerctl wireplumber
    xwayland-satellite cursor.package wl-clipboard
  ];
  environment.sessionVariables.NIRI_CONFIG = lib.mkDefault "/etc/ohmansy/niri.kdl";
  environment.sessionVariables.XCURSOR_THEME = lib.mkDefault cursor.name;
  environment.sessionVariables.XCURSOR_SIZE = lib.mkDefault (toString cursor.size);
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
    # Launch desktop apps with the user manager's session environment. The
    # wrapper names panel helpers explicitly, so no service PATH is needed.
    enableDefaultPath = false;
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
