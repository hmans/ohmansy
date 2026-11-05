{ nixpkgs, pkgs, system, ohmansyModules, herdrPackage, misePackage }:
let
  lib = nixpkgs.lib;
  evaluate = modules: (lib.nixosSystem {
    inherit system;
    modules = modules ++ [ { system.stateVersion = "26.05"; } ];
  }).config;
  defaults = evaluate [ ohmansyModules.default ];
  hostOwnedState = (lib.nixosSystem {
    inherit system;
    modules = [ ohmansyModules.default { system.stateVersion = "25.11"; } ];
  }).config;
  desktopOnly = evaluate [ ohmansyModules.desktop ];
  withoutCompositor = evaluate [ ohmansyModules.desktop { ohmansy.compositor.enable = false; } ];
  softwareOnly = evaluate [ ohmansyModules.software ];
  noAppImages = evaluate [ ohmansyModules.software { programs.appimage.enable = false; } ];
  noFish = evaluate [ ohmansyModules.default { programs.fish.enable = false; } ];
  noFishStyle = evaluate [ ohmansyModules.software { ohmansy.fishStyle.enable = false; } ];
  customPrompt = evaluate [ ohmansyModules.software {
    programs.starship.settings.directory.style = "bold blue";
  } ];
  differentPreset = evaluate [ ohmansyModules.software {
    programs.starship.presets = [ "plain-text-symbols" ];
  } ];
  noBrowserStyle = evaluate [ ohmansyModules.software { ohmansy.firefoxStyle.enable = false; } ];
  custom = evaluate [
    ohmansyModules.default
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
assert defaults.services.displayManager.defaultSession == "niri";
assert defaults.ohmansy.greeter.sessions ? niri;
assert defaults.ohmansy.greeter.sessions ? ohmansy;
assert !(withoutCompositor.ohmansy.greeter.sessions ? ohmansy);
assert withoutCompositor.ohmansy.greeter.sessions ? niri;
assert noBrowserStyle.programs.firefox.enable && noBrowserStyle.programs.firefox.autoConfig == "";
assert custom.programs.firefox.autoConfig == "";
assert defaults.users.defaultUserShell == pkgs.fish;
assert defaults.environment.etc."xdg/xdg-terminals.list".text == "foot.desktop\n";
assert defaults.environment.etc ? "xdg/foot/foot.ini";
assert !desktopOnly.programs.firefox.enable && !desktopOnly.programs.fish.enable;
assert !softwareOnly.programs.niri.enable;
assert defaults.programs.appimage.enable && defaults.programs.appimage.binfmt;
assert softwareOnly.programs.appimage.enable && !desktopOnly.programs.appimage.enable;
assert builtins.elem defaults.programs.appimage.package defaults.environment.systemPackages;
assert defaults.boot.binfmt.registrations ? appimage_type_1;
assert defaults.boot.binfmt.registrations ? appimage_type_2;
assert !(noAppImages.boot.binfmt.registrations ? appimage_type_2);
assert builtins.elem herdrPackage defaults.environment.systemPackages;
assert builtins.elem herdrPackage softwareOnly.environment.systemPackages;
assert builtins.elem misePackage defaults.environment.systemPackages;
assert builtins.elem misePackage softwareOnly.environment.systemPackages;
assert !(builtins.any (package: lib.getName package == "codex") defaults.environment.systemPackages);
assert lib.hasInfix (builtins.unsafeDiscardStringContext "${lib.getExe misePackage} activate fish | source") defaults.programs.fish.interactiveShellInit;
assert lib.hasInfix (builtins.unsafeDiscardStringContext "${lib.getExe misePackage} activate bash") noFish.programs.bash.interactiveShellInit;
assert lib.hasInfix (builtins.unsafeDiscardStringContext "${lib.getExe misePackage} activate zsh") defaults.programs.zsh.interactiveShellInit;
assert !(lib.hasInfix "activate fish" custom.programs.fish.interactiveShellInit);
assert !(lib.hasInfix "activate bash" custom.programs.bash.interactiveShellInit);
assert !(lib.hasInfix "activate zsh" custom.programs.zsh.interactiveShellInit);
assert !(builtins.any (package: lib.getName package == "herdr") desktopOnly.environment.systemPackages);
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
assert !(builtins.elem herdrPackage custom.environment.systemPackages);
assert !(builtins.elem misePackage custom.environment.systemPackages);
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
