{ pkgs }:
pkgs.symlinkJoin {
  name = "ohmansy-apply";
  paths = map (action: pkgs.writeShellApplication {
    name = "ohmansy-${action}";
    runtimeInputs = [ pkgs.python3 pkgs.nix pkgs.nixos-rebuild pkgs.sudo ];
    text = ''exec python3 ${./apply/apply.py} ${action} --release-source ${import ./release-source.nix { inherit pkgs; }} "$@"'';
  }) [ "switch" "boot" ];
}
