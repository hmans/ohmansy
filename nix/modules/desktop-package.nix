{ pkgs }:
let
  ui = import ./quickshell-ui.nix { inherit pkgs; };
  syncTerminalTheme = pkgs.writeShellScript "ohmansy-terminal-theme" ''
    case "$1" in
      dark) signal=USR1 ;;
      light) signal=USR2 ;;
      *) exit 2 ;;
    esac
    # Foot servers update their clients and the default for future clients too.
    ${pkgs.procps}/bin/pkill --signal "$signal" --euid "$(${pkgs.coreutils}/bin/id -u)" --exact foot && exit 0
    status=$?
    # No running terminal is a normal state.
    [ "$status" -eq 1 ] && exit 0
    exit "$status"
  '';
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
  export OHMANSY_TERMINAL_THEME="${syncTerminalTheme}"
  export PATH="${pkgs.xdg-terminal-exec}/bin:$PATH"
  exec ${pkgs.quickshell}/bin/quickshell "$@"
''
