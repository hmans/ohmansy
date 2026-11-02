{ pkgs }:
let
  ui = import ./quickshell-ui.nix { inherit pkgs; };
  launchApp = pkgs.writeShellScript "ohmansy-launch-app" ''
    # Applications must not inherit QProcess pipes which close when gtk-launch
    # exits. Journal streams survive the launcher and retain application errors.
    # Keep launched apps outside the shell service's lifetime as well.
    exec ${pkgs.systemd}/bin/systemd-run --user --scope --collect --quiet \
      ${pkgs.systemd}/bin/systemd-cat --identifier=ohmansy-app-launch \
      ${pkgs.gtk3}/bin/gtk-launch "$@"
  '';
in pkgs.writeShellScriptBin "ohmansy-quickshell" ''
  export QML_IMPORT_PATH="${ui}/lib/qt-6/qml''${QML_IMPORT_PATH:+:$QML_IMPORT_PATH}"
  export OHMANSY_APP_LAUNCHER="${launchApp}"
  export PATH="${pkgs.xdg-terminal-exec}/bin:$PATH"
  exec ${pkgs.quickshell}/bin/quickshell "$@"
''
