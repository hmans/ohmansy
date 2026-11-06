{ nixpkgs, pkgs, system, ohmansyModules, herdrPackage, misePackage }:
let
  lib = nixpkgs.lib;
  evaluate = modules: (lib.nixosSystem {
    inherit system;
    modules = modules ++ [ { system.stateVersion = "26.05"; } ];
  }).config;
  defaults = evaluate [ ohmansyModules.default ];
  noAgentSkills = evaluate [ ohmansyModules.default { ohmansy.agentSkills.enable = false; } ];
  hostOwnedState = (lib.nixosSystem {
    inherit system;
    modules = [ ohmansyModules.default { system.stateVersion = "25.11"; } ];
  }).config;
  desktopOnly = evaluate [ ohmansyModules.desktop ];
  withoutCompositor = evaluate [ ohmansyModules.desktop { ohmansy.compositor.enable = false; } ];
  niriDefault = evaluate [ ohmansyModules.desktop { services.displayManager.defaultSession = "niri"; } ];
  softwareOnly = evaluate [ ohmansyModules.software ];
  noAppImages = evaluate [ ohmansyModules.software { programs.appimage.enable = false; } ];
  noFlatpak = evaluate [ ohmansyModules.software { services.flatpak.enable = false; } ];
  noBtopStyle = evaluate [ ohmansyModules.software { ohmansy.btopStyle.enable = false; } ];
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
      programs.chromium.enable = false;
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
  niriShell = import ../modules/desktop-package.nix { inherit pkgs; };
  shineShell = import ../modules/shine-shell.nix { inherit pkgs; };
  pathProbe = pkgs.writeText "session-path-probe.qml" ''
    import QtQuick
    import Quickshell
    import Quickshell.Io
    ShellRoot {
      Process {
        running: true
        command: ["ohmansy-path-probe"]
        stdout: StdioCollector {
          onStreamFinished: {
            if (Quickshell.env("PATH") === Quickshell.env("OHMANSY_TEST_PATH")
                && text.trim() === Quickshell.env("OHMANSY_TEST_PATH"))
              console.log("SESSION_PATH_TEST passed");
            Qt.quit();
          }
        }
      }
      Timer { running: true; interval: 10000; onTriggered: Qt.quit() }
    }
  '';
in
assert hostOwnedState.system.stateVersion == "25.11";
assert defaults.environment.etc."ohmansy/skills/ohmansy-maintenance".source
  == defaults.environment.etc."codex/skills/ohmansy-maintenance".source;
assert defaults.environment.etc."ohmansy/skills/ohmansy-maintenance".source
  == defaults.environment.etc."claude-code/.claude/skills/ohmansy-maintenance".source;
assert !(noAgentSkills.environment.etc ? "ohmansy/skills/ohmansy-maintenance");
assert !(noAgentSkills.environment.etc ? "codex/skills/ohmansy-maintenance");
assert !(noAgentSkills.environment.etc ? "claude-code/.claude/skills/ohmansy-maintenance");
assert defaults.programs.firefox.enable && defaults.programs.fish.enable;
assert defaults.programs.chromium.enable && softwareOnly.programs.chromium.enable;
assert builtins.elem pkgs.chromium defaults.environment.systemPackages;
assert !desktopOnly.programs.chromium.enable;
assert !custom.programs.chromium.enable;
assert !(builtins.elem pkgs.chromium custom.environment.systemPackages);
assert defaults.services.displayManager.defaultSession == "ohmansy";
assert (builtins.fromJSON (builtins.unsafeDiscardStringContext defaults.environment.etc."ohmansy/greeter-sessions.json".text)).default == "ohmansy";
assert desktopOnly.services.displayManager.defaultSession == "ohmansy";
assert withoutCompositor.services.displayManager.defaultSession == "niri";
assert (builtins.fromJSON (builtins.unsafeDiscardStringContext withoutCompositor.environment.etc."ohmansy/greeter-sessions.json".text)).default == "niri";
assert niriDefault.services.displayManager.defaultSession == "niri";
assert (builtins.fromJSON (builtins.unsafeDiscardStringContext niriDefault.environment.etc."ohmansy/greeter-sessions.json".text)).default == "niri";
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
assert defaults.services.flatpak.enable && softwareOnly.services.flatpak.enable;
assert !desktopOnly.services.flatpak.enable;
assert defaults.systemd.user.services ? ohmansy-btop-theme;
assert softwareOnly.systemd.user.services ? ohmansy-btop-theme;
assert !(desktopOnly.systemd.user.services ? ohmansy-btop-theme);
assert !(custom.systemd.user.services ? ohmansy-btop-theme);
assert !(noBtopStyle.systemd.user.services ? ohmansy-btop-theme);
assert builtins.elem pkgs.btop noBtopStyle.environment.systemPackages;
assert softwareOnly.xdg.portal.enable;
assert desktopOnly.xdg.portal.enable && desktopOnly.xdg.portal.wlr.enable;
assert builtins.elem pkgs.xdg-desktop-portal-gtk desktopOnly.xdg.portal.extraPortals;
assert builtins.any (package: lib.getName package == "xdg-desktop-portal-wlr") desktopOnly.xdg.portal.extraPortals;
assert desktopOnly.xdg.portal.config.ohmansy.default == "gtk";
assert desktopOnly.xdg.portal.config.ohmansy."org.freedesktop.impl.portal.ScreenCast" == "wlr";
assert desktopOnly.xdg.portal.config.ohmansy."org.freedesktop.impl.portal.Secret" == "gnome-keyring";
assert desktopOnly.xdg.portal.config.niri."org.freedesktop.impl.portal.ScreenCast" or "gnome" == "gnome";
assert !withoutCompositor.xdg.portal.wlr.enable;
assert builtins.elem pkgs.xdg-desktop-portal-gtk softwareOnly.xdg.portal.extraPortals;
assert builtins.elem defaults.services.flatpak.package defaults.environment.systemPackages;
assert builtins.elem "$HOME/.local/share/flatpak/exports" defaults.environment.profiles;
assert builtins.elem "/var/lib/flatpak/exports" defaults.environment.profiles;
assert defaults.systemd.user.services.ohmansy-flathub.wantedBy == [ "default.target" ];
assert lib.hasInfix "remote-add --user --if-not-exists flathub" defaults.systemd.user.services.ohmansy-flathub.serviceConfig.ExecStart;
assert !(noFlatpak.systemd.user.services ? ohmansy-flathub);
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
assert lib.hasInfix "$HOME/.local/share/mise/shims" defaults.environment.sessionVariables.PATH;
assert lib.hasInfix "$HOME/.local/share/mise/shims" softwareOnly.environment.sessionVariables.PATH;
assert !(lib.hasInfix "$HOME/.local/share/mise/shims" (custom.environment.sessionVariables.PATH or ""));
assert lib.hasInfix "@{HOME}/.local/share/mise/shims" defaults.environment.etc."pam/environment".text;
assert lib.hasInfix "$HOME/.local/share/mise/shims" defaults.environment.etc."environment.d/50-systemd-path.conf".text;
assert !defaults.systemd.user.services.quickshell.enableDefaultPath;
assert defaults.systemd.user.services.quickshell.path == [];
assert !(defaults.systemd.user.services.quickshell.environment ? PATH);
assert !(custom.systemd.user.services.quickshell.environment ? PATH);
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
  python3 ${./btop-theme.py} ${../modules/btop-theme.py}
  export XDG_CONFIG_HOME="$TMPDIR/config"
  export XDG_CONFIG_DIRS="$TMPDIR/config"
  export XDG_DATA_HOME="$TMPDIR/data"
  export XDG_DATA_DIRS="${pkgs.kitty}/share"
  mkdir -p "$XDG_CONFIG_HOME" "$XDG_DATA_HOME"
  # Both wrappers must preserve the caller's PATH and resolve child commands
  # from it. No windows or access to the running desktop are needed.
  mkdir -p "$TMPDIR/probe-bin" "$TMPDIR/runtime"
  chmod 700 "$TMPDIR/runtime"
  cat > "$TMPDIR/probe-bin/ohmansy-path-probe" <<'EOF'
  #!${pkgs.runtimeShell}
  printf '%s\n' "$PATH"
  EOF
  chmod +x "$TMPDIR/probe-bin/ohmansy-path-probe"
  for wrapper in ${niriShell}/bin/ohmansy-quickshell ${shineShell}/bin/ohmansy-shine-shell; do
    case "$wrapper" in
      */ohmansy-shine-shell) set -- ;;
      *) set -- --path ${pathProbe} ;;
    esac
    ${pkgs.coreutils}/bin/env PATH="$TMPDIR/probe-bin" \
      OHMANSY_TEST_PATH="$TMPDIR/probe-bin" XDG_RUNTIME_DIR="$TMPDIR/runtime" \
      QT_QPA_PLATFORM=offscreen QSG_RHI_BACKEND=software \
      OHMANSY_SHINE_QML=${pathProbe} \
      ${pkgs.coreutils}/bin/timeout 15s \
      ${pkgs.dbus}/bin/dbus-run-session --dbus-daemon=${pkgs.dbus}/bin/dbus-daemon \
      --config-file=${pkgs.dbus}/share/dbus-1/session.conf \
      -- "$wrapper" "$@" > path-probe.log 2>&1 || {
        cat path-probe.log
        exit 1
      }
    grep -F 'SESSION_PATH_TEST passed' path-probe.log || { cat path-probe.log; exit 1; }
  done
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
  # Register from the bundled definition without network access or app installs.
  ${defaults.systemd.user.services.ohmansy-flathub.serviceConfig.ExecStart}
  ${defaults.systemd.user.services.ohmansy-flathub.serviceConfig.ExecStart}
  test "$(${defaults.services.flatpak.package}/bin/flatpak remotes --user --columns=name,url)" = \
    "$(printf 'flathub\thttps://dl.flathub.org/repo/')"
  touch "$out"
''
