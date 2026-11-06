{ pkgs }:
pkgs.stdenv.mkDerivation {
  pname = "ohmansy-notification-support";
  version = "1";
  src = ./notifications/native;
  nativeBuildInputs = [ pkgs.cmake pkgs.ninja pkgs.pkg-config pkgs.wayland-scanner ];
  buildInputs = [ pkgs.qt6.qtbase pkgs.qt6.qtdeclarative pkgs.wayland pkgs.wayland-protocols ];
  dontWrapQtApps = true;
}
