# Only image profiles import this guard. Installed development hosts do not.
{ live ? false }:
{ config, lib, ... }:
let
  users = builtins.attrValues config.users.users;
  standardSudoRule = rule:
    rule.host == "ALL" && rule.runAs == "ALL:ALL" && (
      (rule.users == [ "root" ] && rule.groups == [] &&
        rule.commands == [{ command = "ALL"; options = [ "SETENV" ]; }]) ||
      (rule.users == [] && rule.groups == [ "wheel" ] &&
        rule.commands == [{ command = "ALL";
          options = lib.optional (!config.security.sudo.wheelNeedsPassword) "NOPASSWD" ++ [ "SETENV" ]; }])
    );
in {
  assertions = [
    {
      assertion = !(config.environment.etc ? "ohmansy/development-access");
      message = "Image policy: development access must not be included in an image.";
    }
    {
      assertion = !config.services.openssh.enable;
      message = "Image policy: SSH must be disabled.";
    }
    {
      assertion = builtins.all (user: user.openssh.authorizedKeys.keys == [] &&
        user.openssh.authorizedKeys.keyFiles == []) users;
      message = "Image policy: SSH authorized keys must not be included.";
    }
    {
      assertion = builtins.all (user: !user.isNormalUser || (live && user.name == "nixos")) users;
      message = "Image policy: installed owner accounts must not be included.";
    }
    {
      assertion = builtins.all standardSudoRule config.security.sudo.extraRules &&
        !(lib.hasInfix "NOPASSWD" config.security.sudo.extraConfig) &&
        (live || config.security.sudo.wheelNeedsPassword);
      message = "Image policy: custom sudo grants must not be included.";
    }
  ];
}
