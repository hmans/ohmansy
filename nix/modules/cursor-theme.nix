{ pkgs }:
let
  name = "Bibata-Modern-Classic";
  size = 24;
  fallback = pkgs.writeTextDir "share/icons/default/index.theme" ''
    [Icon Theme]
    Name=ohmansy default cursor theme
    Inherits=${name}
  '';
  package = pkgs.symlinkJoin {
    name = "ohmansy-cursors";
    paths = [
      pkgs.bibata-cursors
      pkgs.adwaita-icon-theme
      fallback
    ];
  };
in
{
  inherit name size package;
  environment = pkgs.writeText "ohmansy-cursor-environment" ''
    export XCURSOR_THEME="''${XCURSOR_THEME:-${name}}"
    export XCURSOR_SIZE="''${XCURSOR_SIZE:-${toString size}}"
    export XCURSOR_PATH="''${XCURSOR_PATH:-$HOME/.icons:$HOME/.local/share/icons:/run/current-system/sw/share/icons}:${package}/share/icons"
  '';
}
