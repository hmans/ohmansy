{ pkgs, package ? pkgs.btop }:
let
  palettes = {
    dark = {
      foreground = "f5f5f5"; muted = "777780"; selection = "50505a";
      red = "e78284"; green = "a6d189"; yellow = "e5c890";
      blue = "8caaee"; purple = "c4a7e7"; cyan = "81c8be";
    };
    light = {
      foreground = "202024"; muted = "62626e"; selection = "e0d8ea";
      red = "a33340"; green = "356b32"; yellow = "805d14";
      blue = "315ba5"; purple = "68478d"; cyan = "246b70";
    };
  };
  themes = pkgs.runCommand "ohmansy-btop-themes" {} (pkgs.lib.concatStringsSep "\n"
    (pkgs.lib.mapAttrsToList (mode: p: let
      colors = {
        main_bg = "";
        main_fg = p.foreground; title = p.foreground; hi_fg = p.purple;
        selected_bg = p.selection; selected_fg = p.foreground;
        inactive_fg = p.muted; graph_text = p.muted; meter_bg = p.selection;
        proc_misc = p.cyan; cpu_box = p.purple; mem_box = p.green;
        net_box = p.blue; proc_box = p.purple; div_line = p.muted;
        proc_pause_bg = p.red; proc_follow_bg = p.blue;
        proc_banner_bg = p.purple; proc_banner_fg = if mode == "dark" then "202024" else "ffffff";
        followed_bg = p.selection; followed_fg = p.foreground;
      } // pkgs.lib.concatMapAttrs (name: color: {
        "${name}_start" = p.cyan;
        "${name}_mid" = color;
        "${name}_end" = color;
      }) {
        temp = p.red; cpu = p.purple; free = p.green; cached = p.blue;
        available = p.yellow; used = p.red; download = p.blue;
        upload = p.purple; process = p.green;
      };
      theme = pkgs.writeText "${mode}.theme" (pkgs.lib.concatStringsSep "\n"
        (pkgs.lib.mapAttrsToList (name: value: ''theme[${name}]="${pkgs.lib.optionalString (value != "") "#"}${value}"'') colors));
    in ''
      mkdir -p "$out"
      cp ${theme} "$out/${mode}.theme"
    '') palettes));
  helper = pkgs.writeShellScriptBin "ohmansy-btop-theme" ''
    export PATH="${pkgs.lib.makeBinPath [ pkgs.glib pkgs.procps pkgs.coreutils ]}:$PATH"
    export GSETTINGS_SCHEMA_DIR=${pkgs.gsettings-desktop-schemas}/share/gsettings-schemas/${pkgs.gsettings-desktop-schemas.name}/glib-2.0/schemas
    exec ${pkgs.python3}/bin/python3 ${./btop-theme.py} "$1" ${themes} "''${@:2}"
  '';
  launcher = pkgs.writeShellScript "ohmansy-btop" ''
    # Explicit configs and informational commands do not create user settings.
    for argument in "$@"; do
      case "$argument" in
        -c|--config|--config=*|-c?*|-h|--help|-V|--version|--default-config)
          exec ${package}/bin/btop "$@" ;;
      esac
    done
    ${helper}/bin/ohmansy-btop-theme prepare
    exec ${package}/bin/btop "$@"
  '';
in {
  inherit helper themes;
  package = pkgs.symlinkJoin {
    name = "ohmansy-btop-${package.version}";
    paths = [ package ];
    postBuild = ''
      rm "$out/bin/btop"
      ln -s ${launcher} "$out/bin/btop"
    '';
    meta = package.meta;
  };
}
