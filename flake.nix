{
  description = "Ohmansy — a portable Niri desktop, persistent VM, and live images";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

  outputs = { self, nixpkgs }:
    let
      system = "aarch64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      live = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [ ./nix/profiles/live.nix ];
      };
      appliance = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [ ./nix/profiles/factory.nix ];
      };
      installer = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [ ./nix/profiles/installer.nix ];
      };
      rejectsDevelopment = base: extra:
        let candidate = base.extendModules { modules = [ extra ]; };
        in builtins.any (item: !item.assertion &&
          nixpkgs.lib.hasPrefix "Image policy:" item.message) candidate.config.assertions;
      vmConfig = pkgs.writeText "ohmansy-vm-validation.kdl" (
        builtins.replaceStrings [ "/etc/ohmansy/desktop.kdl" ]
          [ "${./nix/modules/desktop/niri.kdl}" ]
          (builtins.readFile ./nix/modules/desktop/vm.kdl)
      );
    in {
      nixosModules.default = self.nixosModules.desktop;
      nixosModules.desktop = import ./nix/modules/desktop.nix;
      nixosModules.vm = import ./nix/modules/vm.nix;
      nixosConfigurations.live = live;
      nixosConfigurations.appliance = appliance;
      nixosConfigurations.installer = installer;
      packages.${system} = {
        vm-image = appliance.config.system.build.image;
        iso = live.config.system.build.isoImage;
        installer-iso = installer.config.system.build.isoImage;
        default = self.packages.${system}.vm-image;
      };
      checks.${system} = {
        image-development-boundary =
          assert builtins.all (base: rejectsDevelopment base {
            environment.etc."ohmansy/development-access".text = "test";
          }) [ appliance live installer ];
          assert rejectsDevelopment appliance {
            security.sudo.extraRules = [{ users = [ "test-owner" ];
              commands = [{ command = "ALL"; options = [ "NOPASSWD" ]; }]; }];
          };
          assert rejectsDevelopment live {
            users.users.root.openssh.authorizedKeys.keys = [ "ssh-ed25519 AAAA test" ];
          };
          assert rejectsDevelopment installer {
            services.openssh.enable = nixpkgs.lib.mkOverride 0 true;
          };
          pkgs.runCommand "ohmansy-image-development-boundary" {} ''touch "$out"'';
        appliance-policy = assert !appliance.config.services.openssh.enable;
          assert !appliance.config.services.displayManager.autoLogin.enable;
          assert appliance.config.security.sudo.wheelNeedsPassword;
          assert !(builtins.hasAttr "ohmansy" appliance.config.users.users);
          assert !(builtins.hasAttr "hmans" appliance.config.users.users);
          assert !(builtins.hasAttr "ohmansy/source/flake.nix" appliance.config.environment.etc);
          pkgs.runCommand "ohmansy-appliance-policy" { } ''touch "$out"'';
        niri-config = pkgs.runCommand "ohmansy-niri-config" { nativeBuildInputs = [ pkgs.niri ]; } ''
          niri validate --config ${./nix/modules/desktop/niri.kdl}
          niri validate --config ${vmConfig}
          touch "$out"
        '';
        live-policy = assert !live.config.services.openssh.enable;
          assert !live.config.services.desktopManager.gnome.enable;
          assert live.config.services.displayManager.defaultSession == "niri";
          assert !(builtins.hasAttr "hmans" live.config.users.users);
          pkgs.runCommand "ohmansy-live-policy" { } ''touch "$out"'';
      };
      devShells.${system}.default = pkgs.mkShell {
        packages = with pkgs; [ git nixfmt nil statix python3 niri ];
        shellHook = ''
          echo "Ohmansy: nix flake check | nix build .#vm-image"
        '';
      };
    };
}
