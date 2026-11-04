{
  pkgs,
  terminal ? "${pkgs.foot}/bin/foot",
  xkb ? {
    layout = "us";
  },
}:
let
  cursor = import ./cursor-theme.nix { inherit pkgs; };
  compositor = import ./compositor-package.nix { inherit pkgs; };
  launcher = pkgs.writeShellScript "ohmansy-compositor-applications" ''
    exec ${pkgs.wofi}/bin/wofi --normal-window --show drun --prompt Applications
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
    exec ${pkgs.dbus}/bin/dbus-update-activation-environment \
      WAYLAND_DISPLAY XDG_CURRENT_DESKTOP XDG_SESSION_DESKTOP XDG_SESSION_TYPE
  '';
  session = pkgs.writeShellScript "ohmansy-compositor-session" ''
    set -eu
    . ${cursor.environment}
    # --nested is an explicit preview. A login must acquire displays itself,
    # even if stale display variables were inherited from the greeter.
    mod_key=super
    if [ "''${1:-}" = --nested ]; then
      shift
      mod_key=super-alt
    else
      unset WAYLAND_DISPLAY DISPLAY WAYLAND_SOCKET NIRI_SOCKET
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
    # Keep activation scoped to this bus, including when previewing inside Niri.
    exec ${pkgs.dbus}/bin/dbus-run-session -- \
      ${pkgs.cage}/bin/cage -s -m last -- \
      ${compositor}/bin/ohmansy-compositor --session --mod-key "$mod_key" "$@"
  '';
in
pkgs.runCommand "ohmansy-compositor-session"
  {
    passthru.providedSessions = [ "ohmansy" ];
    meta = {
      description = "Shine desktop session hosted by Cage";
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
