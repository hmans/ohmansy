{ config, lib, pkgs, ... }:
let
  cfg = config.ohmansy.firefoxStyle;
  stylesheet = pkgs.writeText "ohmansy-firefox.css" cfg.css;
in {
  # Apply the wrapper setting to the selected Firefox package, including ESR.
  options.programs.firefox.package = lib.mkOption {
    apply = package: if cfg.enable then package.override (old: {
      extraAutoConfig = (old.extraAutoConfig or "") + ''
        pref("general.config.sandbox_enabled", false);
      '';
    }) else package;
  };
  options.ohmansy.firefoxStyle = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Use Ohmansy's compact Firefox chrome when Firefox is enabled.";
    };
    css = lib.mkOption {
      type = lib.types.lines;
      default = builtins.readFile ./firefox/chrome.css;
      description = "Replaceable stylesheet scoped to Firefox's browser window.";
    };
  };
  config = lib.mkIf (config.programs.firefox.enable && cfg.enable) {
    # This grants the packaged AutoConfig access to the chrome stylesheet service;
    # it does not change Firefox's web-content sandbox.
    programs.firefox.autoConfig = ''
      defaultPref("ohmansy.browserStyle.enabled", true);
      defaultPref("browser.compactmode.show", true);
      defaultPref("browser.uidensity", 1);
      defaultPref("browser.toolbars.bookmarks.visibility", "never");
      if (getPref("ohmansy.browserStyle.enabled")) {
        const sheets = Components.classes["@mozilla.org/content/style-sheet-service;1"]
          .getService(Components.interfaces.nsIStyleSheetService);
        const io = Components.classes["@mozilla.org/network/io-service;1"]
          .getService(Components.interfaces.nsIIOService);
        const uri = io.newURI("file://${stylesheet}");
        if (!sheets.sheetRegistered(uri, sheets.USER_SHEET)) {
          sheets.loadAndRegisterSheet(uri, sheets.USER_SHEET);
        }
      }
    '';
  };
}
