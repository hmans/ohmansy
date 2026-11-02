{ pkgs }:
pkgs.stdenv.mkDerivation {
  pname = "ohmansy-welcome-ribbons";
  version = "1";
  src = ./greeter/ribbons;
  nativeBuildInputs = [ pkgs.cmake pkgs.ninja ];
  buildInputs = [ pkgs.qt6.qtbase pkgs.qt6.qtdeclarative ];
  dontWrapQtApps = true;
}
