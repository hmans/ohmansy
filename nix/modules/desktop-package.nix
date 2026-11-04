{ pkgs, syncFootTheme ? true }:
let
  ui = import ./quickshell-ui.nix { inherit pkgs; };
  desktop = import ./desktop-actions.nix { inherit pkgs; };
  displays = import ./display-package.nix { inherit pkgs; };
  previewDisplay = pkgs.writeShellScript "ohmansy-preview-display" ''
    # The preview worker must outlive a shell reload/crash so its timeout can
    # restore the previous settings. Only this small relay belongs to Quickshell.
    exec ${pkgs.systemd}/bin/systemd-run --user --pipe --wait --collect --quiet \
      --setenv=NIRI_SOCKET="$NIRI_SOCKET" \
      --setenv=XDG_CONFIG_HOME="''${XDG_CONFIG_HOME:-$HOME/.config}" \
      ${displays}/bin/ohmansy-displays preview "$@"
  '';
  appearance = pkgs.writeShellScript "ohmansy-appearance" ''
    export GSETTINGS_SCHEMA_DIR=${pkgs.gsettings-desktop-schemas}/share/gsettings-schemas/${pkgs.gsettings-desktop-schemas.name}/glib-2.0/schemas
    case "$1" in
      read) exec ${pkgs.glib}/bin/gsettings get org.gnome.desktop.interface color-scheme ;;
      monitor) exec ${pkgs.glib}/bin/gsettings monitor org.gnome.desktop.interface color-scheme ;;
      default|prefer-light|prefer-dark)
        exec ${pkgs.glib}/bin/gsettings set org.gnome.desktop.interface color-scheme "$1" ;;
      *) exit 2 ;;
    esac
  '';
  syncTerminalTheme = pkgs.writeShellScript "ohmansy-terminal-theme" ''
    ${pkgs.lib.optionalString (!syncFootTheme) "exit 0"}
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
  syncNiriTheme = pkgs.writeShellScript "ohmansy-niri-theme" ''
    set -eu
    case "$1" in
      dark) palette=${./desktop/niri-dark.kdl} ;;
      light) palette=${./desktop/niri-light.kdl} ;;
      *) exit 2 ;;
    esac
    # Niri's home-relative include uses this fixed path, independent of XDG vars.
    directory="$HOME/.local/state/ohmansy"
    target="$directory/niri-appearance.kdl"
    ${pkgs.coreutils}/bin/mkdir -p "$directory"
    if ${pkgs.diffutils}/bin/cmp -s "$palette" "$target"; then exit 0; fi
    temporary=$(${pkgs.coreutils}/bin/mktemp "$directory/.niri-appearance.XXXXXX")
    trap '${pkgs.coreutils}/bin/rm -f "$temporary"' EXIT
    ${pkgs.coreutils}/bin/cp "$palette" "$temporary"
    ${pkgs.coreutils}/bin/mv -f "$temporary" "$target"
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
  export OHMANSY_NIRI_THEME="${syncNiriTheme}"
  export OHMANSY_APPEARANCE="${appearance}"
  export OHMANSY_DESKTOP="${desktop}/bin/ohmansy-desktop"
  export OHMANSY_DISPLAYS="${displays}/bin/ohmansy-displays"
  export OHMANSY_DISPLAY_PREVIEW="${previewDisplay}"
  export PATH="${pkgs.xdg-terminal-exec}/bin:$PATH"
  exec ${pkgs.quickshell}/bin/quickshell "$@"
''
