{
  pkgs,
  terminal ? "${pkgs.foot}/bin/foot",
  enableKeyring ? true,
  xkb ? {
    layout = "us";
  },
}:
let
  cursor = import ./cursor-theme.nix { inherit pkgs; };
  compositor = import ./compositor-package.nix { inherit pkgs; };
  shell = import ./shine-shell.nix { inherit pkgs; };
  launcher = pkgs.writeShellScript "ohmansy-compositor-applications" ''
    exec ${pkgs.quickshell}/bin/quickshell \
      --path "''${OHMANSY_SHINE_QML:-${./shine-shell}/shell.qml}" ipc call launcher toggle
  '';
  logout = pkgs.writeShellScript "ohmansy-compositor-sign-out" ''
    # A previous confirmation must never make Sign out the next default.
    choice=$(printf 'Cancel\nSign out\n' | ${pkgs.wofi}/bin/wofi \
      --normal-window --dmenu --conf /dev/null --cache-file /dev/null \
      --prompt 'Sign out?') || exit 0
    if [ "$choice" = 'Sign out' ]; then
      exec ${compositor}/bin/ohmansy-compositor msg --socket "$OHMANSY_COMPOSITOR_CONTROL" quit
    fi
  '';
  setup = pkgs.writeShellScript "ohmansy-compositor-session-environment" ''
    set -eu
    if [ "$OHMANSY_COMPOSITOR_SESSION_KIND" = login ]; then
      printf '%s\n' "$WAYLAND_DISPLAY" > "$OHMANSY_COMPOSITOR_SESSION_STATE"
      ${pkgs.dbus}/bin/dbus-update-activation-environment --systemd \
        DISPLAY= WAYLAND_DISPLAY XDG_CURRENT_DESKTOP XDG_SESSION_DESKTOP \
        XDG_SESSION_TYPE SSH_AUTH_SOCK
      ${pkgs.lib.optionalString enableKeyring ''
        # PAM unlocks a login-mode daemon. Finish its initialization before
        # applications activate a replacement daemon with a locked keyring.
        ${pkgs.gnome-keyring}/bin/gnome-keyring-daemon --start --components=secrets,pkcs11 >/dev/null
      ''}
      exit 0
    fi
    # A preview must never replace the parent desktop's activation environment.
    exec ${pkgs.dbus}/bin/dbus-update-activation-environment \
      WAYLAND_DISPLAY XDG_CURRENT_DESKTOP XDG_SESSION_DESKTOP XDG_SESSION_TYPE
  '';
  cleanup = pkgs.writeShellScript "ohmansy-compositor-session-cleanup" ''
    set -eu
    state=$OHMANSY_COMPOSITOR_SESSION_STATE
    IFS= read -r owned < "$state" || exit 0
    current=
    while IFS= read -r entry; do
      case "$entry" in WAYLAND_DISPLAY=*) current=''${entry#WAYLAND_DISPLAY=};; esac
    done < <(${pkgs.systemd}/bin/systemctl --user show-environment)
    # Another login may already have published its own display.
    if [ "$current" = "$owned" ]; then
      ${pkgs.dbus}/bin/dbus-update-activation-environment \
        WAYLAND_DISPLAY= DISPLAY= XDG_CURRENT_DESKTOP= XDG_SESSION_DESKTOP= XDG_SESSION_TYPE=
      ${pkgs.systemd}/bin/systemctl --user unset-environment \
        WAYLAND_DISPLAY DISPLAY XDG_CURRENT_DESKTOP XDG_SESSION_DESKTOP XDG_SESSION_TYPE
    fi
  '';
  session = pkgs.writeShellScript "ohmansy-compositor-session" ''
    set -eu
    . ${cursor.environment}
    # --nested is an explicit preview. A login must acquire displays itself,
    # even if stale display variables were inherited from the greeter.
    mod_key=super
    backend=drm
    export OHMANSY_COMPOSITOR_SESSION_KIND=login
    if [ "''${1:-}" = --nested ]; then
      shift
      mod_key=super-alt
      backend=winit
      export OHMANSY_COMPOSITOR_SESSION_KIND=nested
    else
      unset WAYLAND_DISPLAY DISPLAY WAYLAND_SOCKET NIRI_SOCKET
      # PAM starts the keyring on this bus. A second private bus cannot reach it.
      export DBUS_SESSION_BUS_ADDRESS="unix:path=''${XDG_RUNTIME_DIR:?Missing login runtime directory}/bus"
      if [ -z "''${SSH_AUTH_SOCK:-}" ]; then
        while IFS= read -r entry; do
          case "$entry" in
            SSH_AUTH_SOCK=*)
              candidate=''${entry#SSH_AUTH_SOCK=}
              if [ -S "$candidate" ]; then export SSH_AUTH_SOCK=$candidate; fi
              break;;
          esac
        done < <(${pkgs.systemd}/bin/systemctl --user show-environment)
        if [ -z "''${SSH_AUTH_SOCK:-}" ] && [ -S "$XDG_RUNTIME_DIR/gcr/ssh" ]; then
          export SSH_AUTH_SOCK="$XDG_RUNTIME_DIR/gcr/ssh"
        fi
      fi
      export SSH_AUTH_SOCK="''${SSH_AUTH_SOCK:-}"
    fi
    export XDG_SESSION_TYPE=wayland XDG_CURRENT_DESKTOP=ohmansy XDG_SESSION_DESKTOP=ohmansy
    export WINIT_UNIX_BACKEND=wayland
    export XKB_DEFAULT_LAYOUT=${pkgs.lib.escapeShellArg (xkb.layout or "us")}
    export XKB_DEFAULT_VARIANT=${pkgs.lib.escapeShellArg (xkb.variant or "")}
    export XKB_DEFAULT_OPTIONS=${pkgs.lib.escapeShellArg (xkb.options or "")}
    export OHMANSY_COMPOSITOR_TERMINAL=${pkgs.lib.escapeShellArg terminal}
    export OHMANSY_COMPOSITOR_LAUNCHER=${launcher}
    export OHMANSY_COMPOSITOR_LOGOUT=${logout}
    export OHMANSY_COMPOSITOR_SESSION_SETUP=${setup}
    export OHMANSY_COMPOSITOR_SHELL=${shell}/bin/ohmansy-shine-shell
    if [ "$OHMANSY_COMPOSITOR_SESSION_KIND" = nested ]; then
      exec ${pkgs.dbus}/bin/dbus-run-session -- \
        ${compositor}/bin/ohmansy-compositor --backend "$backend" --session --mod-key "$mod_key" "$@"
    fi
    export OHMANSY_COMPOSITOR_SESSION_STATE=$(${pkgs.coreutils}/bin/mktemp "$XDG_RUNTIME_DIR/shine-session.XXXXXX")
    finish() {
      ${cleanup} || true
      ${pkgs.coreutils}/bin/rm -f "$OHMANSY_COMPOSITOR_SESSION_STATE"
    }
    trap finish EXIT
    ${compositor}/bin/ohmansy-compositor --backend "$backend" --session --mod-key "$mod_key" "$@" &
    child=$!
    trap 'kill -TERM "$child" 2>/dev/null || true; wait "$child" || true; exit 143' HUP INT TERM
    wait "$child"
  '';
in
pkgs.runCommand "ohmansy-compositor-session"
  {
    passthru.providedSessions = [ "ohmansy" ];
    meta = {
      description = "Shine desktop session with direct display and input support";
      platforms = pkgs.lib.platforms.linux;
      mainProgram = "ohmansy-compositor-session";
    };
  }
  ''
    mkdir -p "$out/bin" "$out/share/wayland-sessions"
    ln -s ${session} "$out/bin/ohmansy-compositor-session"
    cat > "$out/share/wayland-sessions/ohmansy.desktop" <<EOF
    [Desktop Entry]
    Name=Shine (experimental)
    Comment=Scrolling desktop with fixed 2x client rendering
    Exec=$out/bin/ohmansy-compositor-session
    Type=Application
    DesktopNames=ohmansy
    EOF
  ''
