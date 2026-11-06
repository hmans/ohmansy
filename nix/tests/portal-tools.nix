{ pkgs }:
pkgs.symlinkJoin {
  name = "ohmansy-portal-test-tools";
  paths = with pkgs; [
    xdg-desktop-portal
    xdg-desktop-portal-wlr
    xdg-desktop-portal-gtk
    wofi
    grim
    pipewire
    (python3.withPackages (p: [ p.dbus-python p.pygobject3 p.pillow ]))
  ];
}
