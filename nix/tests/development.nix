{ nixpkgs, pkgs, system }:
let
  lib = nixpkgs.lib;
  baseline = nixpkgs.lib.nixosSystem {
    inherit system;
    modules = [{ system.stateVersion = "26.05"; }];
  };
  base = nixpkgs.lib.nixosSystem {
    inherit system;
    modules = [ ../modules/development.nix { system.stateVersion = "26.05"; } ];
  };
  enabled = extra: (base.extendModules { modules = [{
    users.users.developer.isNormalUser = true;
    ohmansy.development = {
      enable = true;
      user = "developer";
      authorizedKeys = [ "ssh-ed25519 AAAA test" ];
    };
  } extra]; }).config;
  normal = enabled {};
  passwordRequired = enabled { ohmansy.development.passwordlessSudo = false; };
  noOwner = (base.extendModules { modules = [{
    ohmansy.development.enable = true;
    ohmansy.development.authorizedKeys = [ "ssh-ed25519 AAAA test" ];
  }]; }).config;
  noKey = enabled { ohmansy.development.authorizedKeys = lib.mkForce []; };
  rejects = cfg: message: builtins.any (item: !item.assertion && item.message == message) cfg.assertions;
in
assert !base.config.services.openssh.enable;
assert !(base.config.environment.etc ? "ohmansy/development-access");
assert base.config.security.sudo.extraRules == baseline.config.security.sudo.extraRules;
assert builtins.attrNames base.config.users.users == builtins.attrNames baseline.config.users.users;
assert normal.services.openssh.enable;
assert !normal.services.openssh.settings.PasswordAuthentication;
assert !normal.services.openssh.settings.KbdInteractiveAuthentication;
assert normal.services.openssh.settings.PermitRootLogin == "no";
assert normal.services.openssh.settings.AllowUsers == [ "developer" ];
assert normal.users.users.developer.openssh.authorizedKeys.keys == [ "ssh-ed25519 AAAA test" ];
assert builtins.any (rule: rule.users == [ "developer" ] &&
  builtins.any (command: builtins.elem "NOPASSWD" command.options) rule.commands) normal.security.sudo.extraRules;
assert passwordRequired.security.sudo.extraRules == baseline.config.security.sudo.extraRules;
assert rejects noOwner "Development access requires an existing installed owner.";
assert rejects noKey "Development access requires at least one developer public key.";
pkgs.runCommand "ohmansy-development-module" {} ''touch "$out"''
