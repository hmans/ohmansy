{ pkgs, ... }:
let
  update = pkgs.writeShellApplication {
    name = "ohmansy-update";
    runtimeInputs = [ pkgs.python3 pkgs.nix pkgs.nixos-rebuild ];
    text = ''exec python3 ${./updates/update.py} "$@"'';
  };
in {
  environment.systemPackages = [ update (import ./apply-package.nix { inherit pkgs; }) ];
}
