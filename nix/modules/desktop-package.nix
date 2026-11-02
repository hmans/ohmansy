{ pkgs }:
let ui = import ./quickshell-ui.nix { inherit pkgs; };
in pkgs.writeShellScriptBin "ohmansy-quickshell" ''
  export QML_IMPORT_PATH="${ui}/lib/qt-6/qml''${QML_IMPORT_PATH:+:$QML_IMPORT_PATH}"
  exec ${pkgs.quickshell}/bin/quickshell "$@"
''
