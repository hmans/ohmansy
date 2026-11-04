{
  config,
  lib,
  pkgs,
  ...
}:
let
  niri = config.programs.niri.package;
  quickshell = import ./greeter-package.nix { inherit pkgs; };
  cursor = import ./cursor-theme.nix { inherit pkgs; };
  cfg = config.ohmansy.greeter;
  defaultSession = config.services.displayManager.defaultSession;
  sessions = lib.mapAttrs (
    id: entry:
    entry
    // {
      inherit id;
      command = toString (
        pkgs.writeShellScript "ohmansy-${id}-session" ''
          # Keep session diagnostics out of the VT exposed between compositors.
          exec ${pkgs.systemd}/bin/systemd-cat --identifier=ohmansy-session ${lib.escapeShellArg entry.command}
        ''
      );
    }
  ) cfg.sessions;
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
    export XCURSOR_THEME=${cursor.name}
    export XCURSOR_SIZE=${toString cursor.size}
    export XCURSOR_PATH=${cursor.package}/share/icons
    export QT_QUICK_CONTROLS_STYLE=Basic
    export QSG_RHI_BACKEND=opengl
    # The greeter has no writable home. Keep Qt's shader cache session-local.
    export XDG_CACHE_HOME="$XDG_RUNTIME_DIR/ohmansy-cache"
    exec ${pkgs.dbus}/bin/dbus-run-session -- ${niri}/bin/niri --config /etc/ohmansy/greeter.kdl
  '';
in
{
  options.ohmansy.greeter.sessions = lib.mkOption {
    type = lib.types.attrsOf (
      lib.types.submodule {
        options = {
          label = lib.mkOption {
            type = lib.types.str;
            description = "Name shown at login.";
          };
          command = lib.mkOption {
            type = lib.types.str;
            description = "Absolute path to the session executable.";
          };
          desktop = lib.mkOption {
            type = lib.types.str;
            description = "XDG desktop name for this session.";
          };
        };
      }
    );
    default = { };
    description = "System-defined Wayland sessions offered by the ohmansy login screen.";
  };
  config = {
    assertions = [
      {
        assertion = builtins.hasAttr defaultSession cfg.sessions;
        message = "The default desktop session must be present in ohmansy.greeter.sessions.";
      }
    ]
    ++ lib.mapAttrsToList (id: entry: {
      assertion =
        lib.hasPrefix "/" entry.command
        && builtins.match "[A-Za-z0-9_-]+" id != null
        && builtins.match "[A-Za-z0-9_:-]+" entry.desktop != null;
      message = "Greeter session ${id} needs an absolute executable path and valid desktop/session names.";
    }) cfg.sessions;
    ohmansy.greeter.sessions.niri = {
      label = "ohmansy (Niri)";
      command = "${niri}/bin/niri-session";
      desktop = "niri";
    };
    services.greetd = {
      enable = true;
      settings = {
        default_session.command = "${compositor}";
      }
      // lib.optionalAttrs config.services.displayManager.autoLogin.enable {
        initial_session = {
          command = sessions.${defaultSession}.command;
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
      cursor { xcursor-theme "${cursor.name}"; xcursor-size ${toString cursor.size}; }
      layout { background-color "#171a21"; }
      hotkey-overlay { skip-at-startup; }
      gestures { hot-corners { off; }; }
      animations { off; }
      spawn-at-startup "${shell}"
    '';
    environment.etc."ohmansy/greeter-sessions.json".text = builtins.toJSON {
      default = defaultSession;
      sessions = lib.attrValues sessions;
    };
    environment.etc."ohmansy/greeter-users".source = pkgs.writeScript "ohmansy-greeter-users" ''
      #!${pkgs.python3}/bin/python3
      import json, pwd
      print(json.dumps([{"name": u.pw_name, "label": u.pw_gecos.split(",")[0] or u.pw_name}
        for u in sorted(pwd.getpwall(), key=lambda u: u.pw_name)
        if 1000 <= u.pw_uid < 65534 and u.pw_shell not in ("/run/current-system/sw/bin/nologin", "/bin/false")]))
    '';
  };
}
