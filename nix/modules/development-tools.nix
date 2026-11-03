{ pkgs, ... }:
let
  source = pkgs.runCommand "ohmansy-dev-source" {} ''
    mkdir -p "$out/development" "$out/updates"
    cp ${./development/dev.py} "$out/development/dev.py"
    cp ${./updates/update.py} "$out/updates/update.py"
  '';
  command = pkgs.writeShellApplication {
    name = "ohmansy-dev";
    runtimeInputs = [ pkgs.python3 pkgs.nix pkgs.openssh ];
    text = ''
      exec python3 ${source}/development/dev.py "$@"
    '';
  };
in {
  # Shipping the command does not enable the development module.
  environment.systemPackages = [ command ];
}
