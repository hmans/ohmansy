{ pkgs }:
pkgs.writeShellScript "ohmansy-appearance" ''
  export GSETTINGS_SCHEMA_DIR=${pkgs.gsettings-desktop-schemas}/share/gsettings-schemas/${pkgs.gsettings-desktop-schemas.name}/glib-2.0/schemas
  case "$1" in
    read) exec ${pkgs.glib}/bin/gsettings get org.gnome.desktop.interface color-scheme ;;
    monitor) exec ${pkgs.glib}/bin/gsettings monitor org.gnome.desktop.interface color-scheme ;;
    default|prefer-light|prefer-dark)
      exec ${pkgs.glib}/bin/gsettings set org.gnome.desktop.interface color-scheme "$1" ;;
    *) exit 2 ;;
  esac
''
