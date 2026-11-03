{ config, lib, ... }:
let
  cfg = config.ohmansy.development;
in {
  options.ohmansy.development = {
    enable = lib.mkEnableOption "private development access (never for release images)";
    user = lib.mkOption {
      type = lib.types.nullOr (lib.types.strMatching "[a-z_][a-z0-9_-]*");
      default = null;
      description = "Existing installed owner allowed to connect over SSH.";
    };
    authorizedKeys = lib.mkOption {
      type = lib.types.listOf (lib.types.strMatching "ssh-ed25519 [A-Za-z0-9+/]+={0,2}( .*)?");
      default = [];
      description = "Developer Ed25519 public keys. Keep personal values in local configuration.";
    };
    passwordlessSudo = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Let the development owner administer the guest without password prompts.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.user != null && cfg.user != "root" && cfg.user != "nixos"
          && lib.attrByPath [ "users" "users" cfg.user "isNormalUser" ] false config;
        message = "Development access requires an existing installed owner.";
      }
      {
        assertion = cfg.authorizedKeys != [];
        message = "Development access requires at least one developer public key.";
      }
    ];
    # Image profiles reject this marker, even if SSH or sudo is overridden.
    environment.etc."ohmansy/development-access".text = "Private development guest\n";
    services.openssh = {
      enable = true;
      settings = {
        PasswordAuthentication = false;
        KbdInteractiveAuthentication = false;
        PermitRootLogin = "no";
        AllowUsers = lib.optional (cfg.user != null) cfg.user;
      };
    };
    users.users = lib.optionalAttrs (cfg.user != null) {
      ${cfg.user}.openssh.authorizedKeys.keys = cfg.authorizedKeys;
    };
    security.sudo.extraRules = lib.mkIf (cfg.passwordlessSudo && cfg.user != null) [{
      users = [ cfg.user ];
      commands = [{ command = "ALL"; options = [ "NOPASSWD" ]; }];
    }];
  };
}
