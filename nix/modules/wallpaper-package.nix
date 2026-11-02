{ pkgs }:
let
  ribbons = import ./greeter-ribbons.nix { inherit pkgs; };
  scene = pkgs.runCommand "ohmansy-wallpaper-qml" {} ''
    mkdir -p $out
    cp ${./desktop/wallpaper.qml} $out/shell.qml
    cp ${./greeter/scene/Ribbons.qml} $out/Ribbons.qml
    cp ${./desktop/quickshell/NiriState.qml} $out/NiriState.qml
    cp ${./desktop/quickshell/Niri.js} $out/Niri.js
  '';
in pkgs.writeShellScriptBin "ohmansy-wallpaper" ''
  wallpaper_state="''${XDG_STATE_HOME:-$HOME/.local/state}/ohmansy/wallpaper"
  if [ -f "$wallpaper_state" ]; then
    IFS= read -r OHMANSY_WALLPAPER_IMAGE < "$wallpaper_state" || true
    if [ -f "$OHMANSY_WALLPAPER_IMAGE" ]; then export OHMANSY_WALLPAPER_IMAGE; fi
  fi
  export QML_IMPORT_PATH="${ribbons}/lib/qt-6/qml''${QML_IMPORT_PATH:+:$QML_IMPORT_PATH}"
  export PATH="${pkgs.niri}/bin:$PATH"
  exec ${pkgs.quickshell}/bin/quickshell --path ${scene}/shell.qml
''
