# Development access for the accelerated VM. Keep the installed system intact.
{ ... }:
{
  imports = [ /etc/nixos/ohmansy/configuration.nix ];
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
      AllowUsers = [ "hmans" ];
    };
  };
  users.users.hmans.openssh.authorizedKeys.keyFiles = [ ./id_ed25519.pub ];
}
