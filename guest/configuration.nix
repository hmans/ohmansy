# Bootstrap wrapper for an existing installation with the standard config path.
# For later rebuilds, import clipboard.nix from your own NixOS configuration.
{ ... }:
{
  imports = [ /etc/nixos/configuration.nix ./clipboard.nix ];
}
