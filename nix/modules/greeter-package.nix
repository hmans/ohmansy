{ pkgs }:
let
  # Quickshell 0.3.0 confuses cancel acknowledgements with authentication
  # success. Keep this patch scoped to the greeter and test delayed replies.
  quickshell = pkgs.quickshell.overrideAttrs (old: {
    patches = (old.patches or []) ++ [ ./greeter/quickshell-greetd-cancel.patch ];
  });
  ribbons = import ./greeter-ribbons.nix { inherit pkgs; };
in pkgs.writeShellScriptBin "quickshell" ''
  # Changing a shader must not require recompiling Quickshell itself.
  export QML_IMPORT_PATH="${ribbons}/lib/qt-6/qml''${QML_IMPORT_PATH:+:$QML_IMPORT_PATH}"
  exec ${quickshell}/bin/quickshell "$@"
''
