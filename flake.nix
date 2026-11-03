{
  description = "Ohmansy — a portable Niri desktop, persistent VM, and live images";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

  outputs = { self, nixpkgs }:
    let
      system = "aarch64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      live = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [ ./nix/profiles/live-vm.nix ];
      };
      appliance = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [ ./nix/profiles/factory.nix ];
      };
      installer = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [ ./nix/profiles/installer.nix ];
      };
      pcSystem = "x86_64-linux";
      pcPkgs = nixpkgs.legacyPackages.${pcSystem};
      pcLive = nixpkgs.lib.nixosSystem {
        system = pcSystem;
        modules = [ ./nix/profiles/live.nix ];
      };
      pcNvidia = nixpkgs.lib.nixosSystem {
        system = pcSystem;
        modules = [ ./nix/profiles/live-nvidia.nix ];
      };
      rejectsDevelopment = base: extra:
        let candidate = base.extendModules { modules = [ extra ]; };
        in builtins.any (item: !item.assertion &&
          nixpkgs.lib.hasPrefix "Image policy:" item.message) candidate.config.assertions;
    in {
      nixosModules.default = import ./nix/modules/default.nix;
      nixosModules.desktop = import ./nix/modules/desktop.nix;
      nixosModules.software = import ./nix/modules/software.nix;
      nixosModules.vm = import ./nix/modules/vm.nix;
      nixosModules.updates = import ./nix/modules/updates.nix;
      nixosModules.development = import ./nix/modules/development.nix;
      nixosConfigurations.live = live;
      nixosConfigurations.appliance = appliance;
      nixosConfigurations.installer = installer;
      nixosConfigurations.live-x86_64 = pcLive;
      nixosConfigurations.live-nvidia-x86_64 = pcNvidia;
      packages.${pcSystem} = {
        iso = pcLive.config.system.build.isoImage;
        iso-nvidia = pcNvidia.config.system.build.isoImage;
        default = self.packages.${pcSystem}.iso;
      };
      checks.${pcSystem} = {
        live-pc-policy = import ./nix/tests/live-pc.nix {
          inherit nixpkgs pcLive pcNvidia;
          pkgs = pcPkgs;
        };
        customization = import ./nix/tests/customization.nix {
          inherit nixpkgs;
          pkgs = pcPkgs;
          system = pcSystem;
        };
      };
      packages.${system} = {
        installation = import ./nix/modules/installation-package.nix { inherit pkgs; };
        desktop-shell = import ./nix/modules/desktop-package.nix { inherit pkgs; };
        greeter-preview = pkgs.writeShellScriptBin "ohmansy-greeter-preview" ''
          preview=preview.qml
          if [ "''${PREVIEW_FULLSCREEN:-0}" = 1 ]; then
            preview=preview-fullscreen.qml
          fi
          exec ${import ./nix/modules/greeter-package.nix { inherit pkgs; }}/bin/quickshell \
            --path ${./nix/modules/greeter}/"$preview" "$@"
        '';
        first-boot-preview = pkgs.writeShellScriptBin "ohmansy-first-boot-preview" ''
          exec ${import ./nix/modules/greeter-package.nix { inherit pkgs; }}/bin/quickshell \
            --path ${./nix/modules}/first-boot/preview.qml "$@"
        '';
        vm-image = appliance.config.system.build.image;
        iso = live.config.system.build.isoImage;
        installer-iso = installer.config.system.build.isoImage;
        default = self.packages.${system}.vm-image;
      };
      checks.${system} = {
        development-module = import ./nix/tests/development.nix { inherit nixpkgs pkgs system; };
        customization = import ./nix/tests/customization.nix { inherit nixpkgs pkgs system; };
        greeter-auth = pkgs.runCommand "ohmansy-greeter-auth" {
          nativeBuildInputs = [ pkgs.python3 (import ./nix/modules/greeter-package.nix { inherit pkgs; }) ];
        } ''
          export HOME="$TMPDIR"
          python3 ${./nix}/tests/greeter-auth.py
          touch "$out"
        '';
        image-development-boundary =
          assert builtins.all (base: rejectsDevelopment base {
            imports = [ ./nix/modules/development.nix ];
            ohmansy.development = {
              enable = true;
              user = "test-developer";
              authorizedKeys = [ "ssh-ed25519 AAAA test" ];
            };
            users.users.test-developer.isNormalUser = true;
          }) [ appliance live installer ];
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
          assert appliance.config.services.greetd.enable;
          assert !appliance.config.services.displayManager.sddm.enable;
          assert !(appliance.config.services.greetd.settings ? initial_session);
          assert !appliance.config.security.pam.services.greetd.allowNullPassword;
          assert builtins.elem "ohmansy-first-boot.socket" appliance.config.systemd.services.greetd.requires;
          assert appliance.config.systemd.sockets.ohmansy-first-boot.socketConfig.SocketMode == "0600";
          assert appliance.config.systemd.services.ohmansy-first-boot.serviceConfig.StandardOutput == "journal";
          assert appliance.config.security.sudo.wheelNeedsPassword;
          assert !(builtins.hasAttr "ohmansy" appliance.config.users.users);
          assert !(builtins.hasAttr "hmans" appliance.config.users.users);
          assert !(builtins.hasAttr "ohmansy/source/flake.nix" appliance.config.environment.etc);
          pkgs.runCommand "ohmansy-appliance-policy" { } ''touch "$out"'';
        niri-config = pkgs.runCommand "ohmansy-niri-config" { nativeBuildInputs = [ pkgs.niri pkgs.python3 ]; } ''
          ${nixpkgs.lib.concatMapStringsSep "\n" (profile: ''
            python3 ${./nix/tests/niri-shortcuts.py} \
              ${profile.config.environment.etc."ohmansy/niri.kdl".source} \
              ${profile.config.environment.etc."ohmansy/desktop.kdl".source} \
              ${./nix/modules/desktop/shortcuts.json}
          '') [ appliance live installer ]}
          niri validate --config ${pkgs.writeText "ohmansy-greeter-validation.kdl" appliance.config.environment.etc."ohmansy/greeter.kdl".text}
          touch "$out"
        '';
        live-policy = assert !live.config.services.openssh.enable;
          assert live.config.services.greetd.settings.initial_session.user == "nixos";
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
