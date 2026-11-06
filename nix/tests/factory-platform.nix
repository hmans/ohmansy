{ pkgs, appliance }:
let
  config = appliance.config;
  arm = pkgs.stdenv.hostPlatform.isAarch64;
  bootFile = if arm then "/EFI/BOOT/BOOTAA64.EFI" else "/EFI/BOOT/BOOTX64.EFI";
  console = if arm then "console=ttyAMA0,115200" else "console=ttyS0,115200";
  output = ''output "Virtual-1" { scale ${if arm then "2" else "1"}; }'';
  installation = config.environment.etc."ohmansy/installation".source;
in
assert config.image.repart.partitions."10-esp".contents ? ${bootFile};
assert config.image.repart.partitions."20-root".repartConfig.Type == (if arm then "root-arm64" else "root-x86-64");
assert builtins.elem console config.boot.kernelParams;
assert config.ohmansy.vm.displayScale == (if arm then 2 else 1);
assert pkgs.lib.hasInfix output config.environment.etc."ohmansy/greeter-output.kdl".text;
assert pkgs.lib.hasInfix output config.environment.etc."ohmansy/niri.kdl".text;
assert config.systemd.sockets ? ohmansy-first-boot;
assert !config.services.displayManager.autoLogin.enable;
assert !config.services.openssh.enable;
assert builtins.elem appliance.pkgs.mise config.environment.systemPackages;
pkgs.runCommand "ohmansy-factory-platform" {} ''
  grep -F 'system = "${pkgs.stdenv.hostPlatform.system}";' ${installation}/flake.nix
  if grep -F '@SYSTEM@' ${installation}/flake.nix; then
    echo 'Unresolved installed platform' >&2
    exit 1
  fi
  ${pkgs.python3}/bin/python3 - ${installation}/flake.lock <<'PY'
  import json, sys
  lock = json.load(open(sys.argv[1]))
  nodes = lock['nodes']
  def resolve(target):
      if isinstance(target, str):
          return nodes[target]
      node = nodes[lock['root']]
      for name in target:
          node = resolve(node['inputs'][name])
      return node
  for node in nodes.values():
      for target in node.get('inputs', {}).values():
          resolve(target)
  PY
  touch "$out"
''
