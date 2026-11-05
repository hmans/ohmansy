{ config, lib, pkgs, ... }:
let
  cfg = config.ohmansy.terminal;
  isFoot = lib.getName cfg.package == "foot";
  terminal = if isFoot then import ./terminal-package.nix {
    inherit pkgs;
    package = cfg.package;
  } else cfg.package;
  desktopEntries = {
    foot = "foot.desktop";
    kitty = "kitty.desktop";
    alacritty = "Alacritty.desktop";
    ghostty = "com.mitchellh.ghostty.desktop";
  };
  launcher = pkgs.writeShellScriptBin "ohmansy-terminal" ''
    export PATH="${terminal}/bin:$PATH"
    exec ${pkgs.xdg-terminal-exec}/bin/xdg-terminal-exec "$@"
  '';
in {
  options.ohmansy.terminal = {
    launcher = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      internal = true;
      default = launcher;
      description = "Launcher for the configured desktop terminal.";
    };
    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.foot;
      description = "Default desktop terminal package. Foot includes Ohmansy's glass and appearance integration.";
    };
    desktopEntry = lib.mkOption {
      type = lib.types.str;
      default = desktopEntries.${lib.getName cfg.package} or "";
      example = "org.example.Terminal.desktop";
      description = ''
        Desktop entry ID used by xdg-terminal-exec. Known Foot, Kitty, Alacritty,
        and Ghostty packages are detected automatically; other packages must set
        this explicitly and supply a terminal-compatible desktop entry.
      '';
    };
  };
  config = lib.mkMerge [
    {
      assertions = [{
        assertion = cfg.desktopEntry != "" && lib.hasSuffix ".desktop" cfg.desktopEntry
          && !(lib.hasInfix "\n" cfg.desktopEntry);
        message = "Set ohmansy.terminal.desktopEntry to the selected terminal's .desktop ID.";
      }];
      environment.systemPackages = [ terminal launcher pkgs.xdg-terminal-exec ];
      environment.etc."xdg/xdg-terminals.list".text = lib.mkDefault (cfg.desktopEntry + "\n");
    }
    (lib.mkIf isFoot {
      environment.etc."ohmansy/desktop.kdl".text = lib.mkAfter ''
        // Wallpaper blur stays behind Foot's translucent background.
        window-rule {
            match app-id="^foot$"
            background-effect {
                blur true
                xray true
            }
        }
      '';
      environment.etc."xdg/foot/foot.ini".text = ''
        [main]
        font=${if config.programs.fish.enable && (config.ohmansy.fishStyle.enable or false) then "JetBrainsMono Nerd Font" else "JetBrains Mono"}:size=11
        pad=16x14
        [csd]
        size=0
        [colors-dark]
        alpha=0.85
        blur=yes
        background=202020
        foreground=f5f5f5
        regular0=202020
        regular1=e78284
        regular2=a6d189
        regular3=e5c890
        regular4=8caaee
        regular5=c4a7e7
        regular6=81c8be
        regular7=c6c6cc
        bright0=777780
        bright1=efa0a2
        bright2=b9df9e
        bright3=f2d8a5
        bright4=a6bdf5
        bright5=d6bff0
        bright6=9bdad2
        bright7=ffffff
        [colors-light]
        alpha=0.85
        blur=yes
        background=ffffff
        foreground=202024
        regular0=202024
        regular1=a33340
        regular2=356b32
        regular3=805d14
        regular4=315ba5
        regular5=68478d
        regular6=246b70
        regular7=50505a
        bright0=62626e
        bright1=b53645
        bright2=397332
        bright3=89600e
        bright4=3567b7
        bright5=79519e
        bright6=21777d
        bright7=202024
        [key-bindings]
        color-theme-toggle=Control+Shift+t
      '';
    })
  ];
}
