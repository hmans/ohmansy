{ pkgs }:
let
  ui = import ./quickshell-ui.nix { inherit pkgs; };
  ribbons = import ./greeter-ribbons.nix { inherit pkgs; };
  displays = pkgs.writeShellScript "ohmansy-shine-displays" ''
    exec ${pkgs.python3}/bin/python3 ${./desktop/shine-displays.py} "$@"
  '';
  previewDisplay = pkgs.writeShellScript "ohmansy-shine-preview-display" ''
    # Keep the rollback worker alive if Quickshell reloads or exits.
    exec ${pkgs.systemd}/bin/systemd-run --user --pipe --wait --collect --quiet \
      --setenv=OHMANSY_COMPOSITOR_CONTROL="$OHMANSY_COMPOSITOR_CONTROL" \
      ${displays} preview "$@"
  '';
in pkgs.writeShellScriptBin "ohmansy-shine-shell" ''
  case "$OHMANSY_COMPOSITOR_CONTROL" in
    /*) ;;
    *) export OHMANSY_COMPOSITOR_CONTROL="$PWD/$OHMANSY_COMPOSITOR_CONTROL" ;;
  esac
  export OHMANSY_DISPLAYS=${displays}
  export OHMANSY_DISPLAY_PREVIEW=${previewDisplay}
  wallpaper_state="''${XDG_STATE_HOME:-$HOME/.local/state}/ohmansy/wallpaper"
  if [ -f "$wallpaper_state" ]; then
    IFS= read -r OHMANSY_WALLPAPER_IMAGE < "$wallpaper_state" || true
    if [ -f "$OHMANSY_WALLPAPER_IMAGE" ]; then export OHMANSY_WALLPAPER_IMAGE; fi
  fi
  export QML_IMPORT_PATH="${ribbons}/lib/qt-6/qml:${ui}/lib/qt-6/qml''${QML_IMPORT_PATH:+:$QML_IMPORT_PATH}"
  exec ${pkgs.quickshell}/bin/quickshell --path "''${OHMANSY_SHINE_QML:-${./shine-shell}/shell.qml}" "$@"
''
