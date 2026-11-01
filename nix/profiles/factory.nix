{ config, lib, pkgs, modulesPath, ... }:
let
  closure = pkgs.closureInfo { rootPaths = [ config.system.build.toplevel ]; };
  entry = pkgs.writeText "ohmansy-boot.conf" ''
    title Ohmansy
    linux /ohmansy/kernel
    initrd /ohmansy/initrd
    options init=${config.system.build.toplevel}/init ${toString config.boot.kernelParams}
  '';
in {
  imports = [ (modulesPath + "/image/repart.nix") ../modules/persistent-vm.nix ../modules/first-boot.nix
    (import ../modules/image-policy.nix {}) ];
  services.openssh.enable = lib.mkForce false;
  environment.etc."ohmansy/source/flake.lock".source = ../../flake.lock;
  environment.etc."ohmansy/source/nix".source = ../.;
  # Register the shipped store on the first boot of each private writable copy.
  boot.postBootCommands = ''
    if [ -f /nix-path-registration ]; then
      ${config.nix.package}/bin/nix-store --load-db < /nix-path-registration
      ${config.nix.package}/bin/nix-env -p /nix/var/nix/profiles/system --set /run/current-system
      rm /nix-path-registration
    fi
    if [ ! -e /etc/nixos/flake.nix ]; then
      mkdir -p /etc/nixos
      cp -rL /etc/ohmansy/source/nix /etc/nixos/nix
      cp /etc/ohmansy/source/flake.lock /etc/nixos/flake.lock
      chmod -R u+w /etc/nixos
      echo '{ ... }: { }' > /etc/nixos/owner.nix
      cat > /etc/nixos/flake.nix <<'EOF'
    {
      inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
      outputs = { nixpkgs, ... }: {
        nixosConfigurations.ohmansy = nixpkgs.lib.nixosSystem {
          system = "aarch64-linux";
          modules = [ ./nix/modules/persistent-vm.nix ./owner.nix ];
        };
      };
    }
    EOF
    fi
  '';
  image.repart = {
    name = "ohmansy-0.1.0-aarch64-linux";
    compression.enable = true;
    partitions = {
      "10-esp" = {
        contents = {
          "/EFI/BOOT/BOOTAA64.EFI".source = "${pkgs.systemd}/lib/systemd/boot/efi/systemd-bootaa64.efi";
          "/loader/loader.conf".source = pkgs.writeText "loader.conf" "default ohmansy.conf\ntimeout 0\n";
          "/loader/entries/ohmansy.conf".source = entry;
          "/ohmansy/kernel".source = "${config.system.build.kernel}/${config.system.boot.loader.kernelFile}";
          "/ohmansy/initrd".source = "${config.system.build.initialRamdisk}/${config.system.boot.loader.initrdFile}";
        };
        repartConfig = { Type = "esp"; Format = "vfat"; Label = "ESP"; SizeMinBytes = "512M"; SizeMaxBytes = "512M"; };
      };
      "20-root" = {
        storePaths = [ config.system.build.toplevel ];
        contents."/nix-path-registration".source = "${closure}/registration";
        repartConfig = { Type = "root-arm64"; Format = "ext4"; Label = "ohmansy"; Minimize = "guess"; };
      };
    };
  };
}
