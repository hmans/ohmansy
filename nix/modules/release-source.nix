{ pkgs }:
# Shared by installation and app switching, including unpublished local builds.
pkgs.runCommand "ohmansy-release" {} ''
  mkdir -p "$out"
  cp ${../../flake.nix} "$out/flake.nix"
  cp ${../../flake.lock} "$out/flake.lock"
  cp -r ${../.} "$out/nix"
''
