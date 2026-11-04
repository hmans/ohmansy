{ pkgs }:
let
  fallback = pkgs.writeTextDir "share/icons/default/index.theme" ''
    [Icon Theme]
    Name=ohmansy default cursor theme
    Inherits=Adwaita
  '';
  package = pkgs.symlinkJoin {
    name = "ohmansy-cursors";
    paths = [
      pkgs.adwaita-icon-theme
      fallback
    ];
  };
in
{
  inherit package;
  environment = pkgs.writeText "ohmansy-cursor-environment" ''
    export XCURSOR_THEME="''${XCURSOR_THEME:-Adwaita}"
    export XCURSOR_SIZE="''${XCURSOR_SIZE:-24}"
    export XCURSOR_PATH="''${XCURSOR_PATH:-$HOME/.icons:$HOME/.local/share/icons:/run/current-system/sw/share/icons}:${package}/share/icons"
  '';
}
