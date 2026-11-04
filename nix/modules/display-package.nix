{ pkgs }:
pkgs.writeShellApplication {
  name = "ohmansy-displays";
  runtimeInputs = [ pkgs.python3 pkgs.niri ];
  text = ''exec python3 ${./desktop/displays.py} "$@"'';
}
