{ nixpkgs, pkgs, system }:
let
  lib = nixpkgs.lib;
  evaluate = modules: (lib.nixosSystem {
    inherit system;
    modules = modules ++ [ { system.stateVersion = "26.05"; } ];
  }).config;
  defaults = evaluate [ ../modules/default.nix ];
  hostOwnedState = (lib.nixosSystem {
    inherit system;
    modules = [ ../modules/default.nix { system.stateVersion = "25.11"; } ];
  }).config;
  desktopOnly = evaluate [ ../modules/desktop.nix ];
  softwareOnly = evaluate [ ../modules/software.nix ];
  noFish = evaluate [ ../modules/default.nix { programs.fish.enable = false; } ];
  noFishStyle = evaluate [ ../modules/software.nix { ohmansy.fishStyle.enable = false; } ];
  customPrompt = evaluate [ ../modules/software.nix {
    programs.starship.settings.directory.style = "bold blue";
  } ];
  differentPreset = evaluate [ ../modules/software.nix {
    programs.starship.presets = [ "plain-text-symbols" ];
  } ];
  noBrowserStyle = evaluate [ ../modules/software.nix { ohmansy.firefoxStyle.enable = false; } ];
  custom = evaluate [
    ../modules/default.nix
    {
      programs.firefox.enable = false;
      programs.fish.enable = false;
      programs.zsh.enable = true;
      users.defaultUserShell = pkgs.zsh;
      ohmansy.software.packages = [];
      environment.systemPackages = [ pkgs.hello ];
      ohmansy.terminal.package = pkgs.kitty;
    }
  ];
  terminalLauncher = lib.findFirst (package: lib.getName package == "ohmansy-terminal")
    (throw "No terminal launcher installed") custom.environment.systemPackages;
in
assert hostOwnedState.system.stateVersion == "25.11";
assert defaults.programs.firefox.enable && defaults.programs.fish.enable;
assert noBrowserStyle.programs.firefox.enable && noBrowserStyle.programs.firefox.autoConfig == "";
assert custom.programs.firefox.autoConfig == "";
assert defaults.users.defaultUserShell == pkgs.fish;
assert defaults.environment.etc."xdg/xdg-terminals.list".text == "foot.desktop\n";
assert defaults.environment.etc ? "xdg/foot/foot.ini";
assert !desktopOnly.programs.firefox.enable && !desktopOnly.programs.fish.enable;
assert !softwareOnly.programs.niri.enable;
assert noFish.users.defaultUserShell == pkgs.bashInteractive;
assert softwareOnly.programs.starship.enable;
assert !noFish.programs.starship.enable && !noFishStyle.programs.starship.enable;
assert customPrompt.programs.starship.settings.directory.style == "bold blue";
assert differentPreset.programs.starship.presets == [ "plain-text-symbols" ];
assert differentPreset.programs.starship.settings == { };
assert !custom.programs.firefox.enable && !custom.programs.fish.enable;
assert custom.users.defaultUserShell == pkgs.zsh;
assert custom.ohmansy.software.packages == [];
assert builtins.elem pkgs.hello custom.environment.systemPackages;
assert !(builtins.elem pkgs.git custom.environment.systemPackages);
assert !(builtins.elem pkgs.fish custom.environment.systemPackages);
assert !(custom.environment.etc ? "xdg/foot/foot.ini");
assert !(lib.hasInfix "match app-id=\"^foot$\"" custom.environment.etc."ohmansy/desktop.kdl".text);
assert lib.hasInfix "spawn \"ohmansy-terminal\"" custom.environment.etc."ohmansy/desktop.kdl".text;
assert custom.environment.etc."xdg/xdg-terminals.list".text == "kitty.desktop\n";
pkgs.runCommand "ohmansy-customization" {
  nativeBuildInputs = [ pkgs.python3 pkgs.niri ];
} ''
  export HOME="$TMPDIR"
  export XDG_CONFIG_HOME="$TMPDIR/config"
  export XDG_CONFIG_DIRS="$TMPDIR/config"
  export XDG_DATA_HOME="$TMPDIR/data"
  export XDG_DATA_DIRS="${pkgs.kitty}/share"
  mkdir -p "$XDG_CONFIG_HOME" "$XDG_DATA_HOME"
  cp ${custom.environment.etc."xdg/xdg-terminals.list".source} "$XDG_CONFIG_HOME/xdg-terminals.list"
  test "$(${terminalLauncher}/bin/ohmansy-terminal --print-id)" = kitty.desktop
  # Read the whole command before matching: grep -q can close a pipe early
  # and fail the launcher under pipefail while it is still writing arguments.
  ${terminalLauncher}/bin/ohmansy-terminal --print-cmd nmtui > terminal-command
  grep -Fq kitty terminal-command
  python3 ${./niri-shortcuts.py} \
    ${custom.environment.etc."ohmansy/niri.kdl".source} \
    ${custom.environment.etc."ohmansy/desktop.kdl".source} \
    ${../modules/desktop/shortcuts.json}
  touch "$out"
''
