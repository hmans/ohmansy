{ config, lib, pkgs, ... }:
let
  niri = config.programs.niri.package;
  quickshell = import ./greeter-package.nix { inherit pkgs; };
  session = pkgs.writeShellScript "ohmansy-desktop-session" ''
    # Keep session diagnostics out of the VT exposed between compositors.
    exec ${pkgs.systemd}/bin/systemd-cat --identifier=ohmansy-session ${niri}/bin/niri-session
  '';
  shell = pkgs.writeShellScript "ohmansy-greeter-shell" ''
    scene=/etc/ohmansy/greeter/shell.qml
    if [ -d /etc/ohmansy/first-boot ] && [ ! -f /var/lib/ohmansy/provisioned ]; then
      scene=/etc/ohmansy/first-boot/shell.qml
    fi
    if ! ${quickshell}/bin/quickshell --no-duplicate --path "$scene"; then
      # A graphics failure must not prevent access to the login form.
      OHMANSY_GREETER_STATIC=1 ${quickshell}/bin/quickshell --no-duplicate --path "$scene"
    fi
    # greetd waits for the whole greeter session to exit before starting Niri.
    ${niri}/bin/niri msg action quit --skip-confirmation
  '';
  compositor = pkgs.writeShellScript "ohmansy-greeter" ''
    export XCURSOR_THEME=Adwaita
    export XCURSOR_SIZE=24
    export XCURSOR_PATH=${pkgs.adwaita-icon-theme}/share/icons
    export QT_QUICK_CONTROLS_STYLE=Basic
    export QSG_RHI_BACKEND=opengl
    # The greeter has no writable home. Keep Qt's shader cache session-local.
    export XDG_CACHE_HOME="$XDG_RUNTIME_DIR/ohmansy-cache"
    exec ${pkgs.dbus}/bin/dbus-run-session -- ${niri}/bin/niri --config /etc/ohmansy/greeter.kdl
  '';
in {
  services.greetd = {
    enable = true;
    settings = {
      default_session.command = "${compositor}";
    } // lib.optionalAttrs config.services.displayManager.autoLogin.enable {
      initial_session = {
        command = "${session}";
        user = config.services.displayManager.autoLogin.user;
      };
    };
  };
  security.pam.services.greetd = {
    enableGnomeKeyring = true;
    allowNullPassword = lib.mkForce config.services.displayManager.autoLogin.enable;
  };
  environment.etc."ohmansy/greeter".source = ./greeter;
  environment.etc."ohmansy/greeter-output.kdl".text = lib.mkDefault "";
  environment.etc."ohmansy/greeter.kdl".text = ''
    ${config.environment.etc."ohmansy/greeter-output.kdl".text}
    input {
      keyboard { xkb { layout "${config.services.xserver.xkb.layout}"; }; }
      touchpad { tap; natural-scroll; }
    }
    cursor { xcursor-theme "Adwaita"; xcursor-size 24; }
    layout { background-color "#171a21"; }
    hotkey-overlay { skip-at-startup; }
    gestures { hot-corners { off; }; }
    animations { off; }
    spawn-at-startup "${shell}"
  '';
  environment.etc."ohmansy/greeter-session".text = "${session}";
  environment.etc."ohmansy/greeter-users".source = pkgs.writeScript "ohmansy-greeter-users" ''
    #!${pkgs.python3}/bin/python3
    import json, pwd
    print(json.dumps([{"name": u.pw_name, "label": u.pw_gecos.split(",")[0] or u.pw_name}
      for u in sorted(pwd.getpwall(), key=lambda u: u.pw_name)
      if 1000 <= u.pw_uid < 65534 and u.pw_shell not in ("/run/current-system/sw/bin/nologin", "/bin/false")]))
  '';
}
