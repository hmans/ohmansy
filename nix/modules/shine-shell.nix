{ pkgs }:
let
  ui = import ./quickshell-ui.nix { inherit pkgs; };
  ribbons = import ./greeter-ribbons.nix { inherit pkgs; };
in pkgs.writeShellScriptBin "ohmansy-shine-shell" ''
  wallpaper_state="''${XDG_STATE_HOME:-$HOME/.local/state}/ohmansy/wallpaper"
  if [ -f "$wallpaper_state" ]; then
    IFS= read -r OHMANSY_WALLPAPER_IMAGE < "$wallpaper_state" || true
    if [ -f "$OHMANSY_WALLPAPER_IMAGE" ]; then export OHMANSY_WALLPAPER_IMAGE; fi
  fi
  export QML_IMPORT_PATH="${ribbons}/lib/qt-6/qml:${ui}/lib/qt-6/qml''${QML_IMPORT_PATH:+:$QML_IMPORT_PATH}"
  exec ${pkgs.quickshell}/bin/quickshell --path "''${OHMANSY_SHINE_QML:-${./shine-shell}/shell.qml}" "$@"
''
