{ pkgs }:
pkgs.writeShellScript "ohmansy-launch-app" ''
  desktop_id="''${1:-}"
  if [ "$desktop_id" = -- ]; then desktop_id="''${2:-}"; fi
  if ${pkgs.python3}/bin/python3 ${./launcher/activate.py} "$desktop_id"; then
    exit 0
  fi
  # Keep app lifetime and journal streams independent of the shell process.
  # A nested preview owns a private activation bus without a systemd manager.
  # Keep that bus: reaching the host manager would launch into the real desktop.
  if [ "''${OHMANSY_COMPOSITOR_SESSION_KIND:-}" = nested ]; then
    exec ${pkgs.systemd}/bin/systemd-cat --identifier=ohmansy-app-launch \
      ${pkgs.gtk3}/bin/gtk-launch "$@"
  fi
  exec ${pkgs.systemd}/bin/systemd-run --user --scope --collect --quiet \
    ${pkgs.systemd}/bin/systemd-cat --identifier=ohmansy-app-launch \
    ${pkgs.gtk3}/bin/gtk-launch "$@"
''
