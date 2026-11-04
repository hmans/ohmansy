{ pkgs }:
let
  # Ship exactly the source needed to evaluate this release, including its lock.
  # A store-path pin also supports offline first boot and unpublished test builds.
  source = pkgs.runCommand "ohmansy-release" {} ''
    mkdir -p "$out"
    cp ${../../flake.nix} "$out/flake.nix"
    cp ${../../flake.lock} "$out/flake.lock"
    cp -r ${../.} "$out/nix"
  '';
  template = pkgs.writeText "installed-flake.nix" (builtins.replaceStrings
    [ "@SOURCE@" "@SYSTEM@" ] [ (toString source) pkgs.stdenv.hostPlatform.system ]
    (builtins.readFile ./installation/flake.nix.in));
in pkgs.runCommand "ohmansy-installation" { nativeBuildInputs = [ pkgs.nix pkgs.python3 ]; } ''
  mkdir -p "$out"
  cp ${template} "$out/flake.nix"
  export SOURCE_HASH=$(nix --extra-experimental-features nix-command hash path ${source})
  python3 - ${source} "$out/flake.lock" <<'PY'
  import json, os, sys
  from pathlib import Path
  source, output = sys.argv[1:]
  lock = json.loads((Path(source) / 'flake.lock').read_text())
  # Follows paths start at the lock root. Nest this release under ohmansy.
  for node in lock['nodes'].values():
      for name, target in node.get('inputs', {}).items():
          if isinstance(target, list):
              node['inputs'][name] = ['ohmansy', *target]
  upstream = lock['nodes'].pop(lock['root'])
  lock['nodes']['ohmansy'] = {
      'inputs': upstream['inputs'],
      'locked': {'type': 'path', 'path': source, 'narHash': os.environ['SOURCE_HASH']},
      'original': {'type': 'path', 'path': source},
  }
  lock['root'] = 'root'
  lock['nodes']['root'] = {'inputs': {'ohmansy': 'ohmansy', 'nixpkgs': ['ohmansy', 'nixpkgs']}}
  Path(output).write_text(json.dumps(lock, indent=2) + '\n')
  PY
  cp ${./vm-hardware.nix} "$out/vm-hardware.nix"
''
