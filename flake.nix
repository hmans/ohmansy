{
  description = "ohmansy — a portable Shine desktop, persistent VM, and live images";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
  inputs.herdr.url = "github:herdrdev/herdr/v0.9.5";

  outputs = { self, nixpkgs, herdr }:
    let
      nixosSystem = args: nixpkgs.lib.nixosSystem (args // {
        modules = args.modules ++ [{ nixpkgs.overlays = [ self.overlays.default ]; }];
      });
      system = "aarch64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      live = nixosSystem {
        inherit system;
        modules = [ ./nix/profiles/live-vm.nix ];
      };
      appliance = nixosSystem {
        inherit system;
        modules = [ ./nix/profiles/factory.nix ];
      };
      installer = nixosSystem {
        inherit system;
        specialArgs.installedSystem = installedBase.config.system.build.toplevel;
        modules = [ ./nix/profiles/installer.nix ./nix/profiles/live-vm.nix ];
      };
      installedBase = nixosSystem {
        inherit system;
        modules = [ ./nix/profiles/installed-base.nix ];
      };
      pcSystem = "x86_64-linux";
      pcPkgs = nixpkgs.legacyPackages.${pcSystem};
      pcAppliance = nixosSystem {
        system = pcSystem;
        modules = [ ./nix/profiles/factory.nix ];
      };
      pcInstaller = nixosSystem {
        system = pcSystem;
        specialArgs.installedSystem = pcInstalledBase.config.system.build.toplevel;
        specialArgs.installedNvidiaSystem = pcInstalledNvidia.config.system.build.toplevel;
        specialArgs.nvidiaDriver = pcInstalledNvidia.config.hardware.nvidia.package;
        modules = [ ./nix/profiles/installer.nix ./nix/profiles/live-pc.nix ];
      };
      pcInstalledBase = nixosSystem {
        system = pcSystem;
        modules = [ ./nix/profiles/installed-base.nix ];
      };
      pcInstalledNvidia = nixosSystem {
        system = pcSystem;
        modules = [ ./nix/profiles/installed-base.nix ./nix/modules/nvidia.nix ];
      };
      pcLive = nixosSystem {
        system = pcSystem;
        modules = [ ./nix/profiles/live-pc.nix ];
      };
      pcNvidia = nixosSystem {
        system = pcSystem;
        modules = [ ./nix/profiles/live-nvidia.nix ];
      };
      desktopPackages = pkgs: {
        compositor = import ./nix/modules/compositor-package.nix { inherit pkgs; };
        compositor-session = import ./nix/modules/compositor-session-package.nix { inherit pkgs; };
        herdr = herdr.packages.${pkgs.stdenv.hostPlatform.system}.default;
        mise = pkgs.callPackage ./nix/modules/mise-package.nix { };
        desktop-shell = import ./nix/modules/desktop-package.nix { inherit pkgs; };
        display-preview = pkgs.writeShellScriptBin "ohmansy-display-preview" ''
          exec ${import ./nix/modules/desktop-package.nix { inherit pkgs; }}/bin/ohmansy-quickshell \
            --path ${./nix/modules/desktop/quickshell}/display-preview.qml "$@"
        '';
        wallpaper = import ./nix/modules/wallpaper-package.nix { inherit pkgs; };
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
        installer-preview = pkgs.writeShellScriptBin "ohmansy-installer-preview" ''
          export OHMANSY_RIBBONS="''${OHMANSY_RIBBONS:-file://${./nix/modules/greeter/scene/Ribbons.qml}}"
          exec ${import ./nix/modules/greeter-package.nix { inherit pkgs; }}/bin/quickshell \
            --path "''${OHMANSY_INSTALLER_QML:-${./nix/modules/installer}/preview.qml}" "$@"
        '';
      };
      rejectsDevelopment = base: extra:
        let candidate = base.extendModules { modules = [ extra ]; };
        in builtins.any (item: !item.assertion &&
          nixpkgs.lib.hasPrefix "Image policy:" item.message) candidate.config.assertions;
      offlinePolicy = packages: payload: media:
        let
          target = packages.writeText "offline-symlink-target" "preserve this store link\n";
          link = packages.runCommand "offline-store-symlink" {} ''ln -s ${target} "$out"'';
        in
        assert payload.config.fileSystems."/".device == "/dev/disk/by-label/OHMANSY_ROOT";
        assert payload.config.fileSystems."/boot".device == "/dev/disk/by-label/OHMANSY_EFI";
        assert payload.config.boot.loader.systemd-boot.enable;
        assert !payload.config.services.openssh.enable;
        assert !payload.config.services.speechd.enable;
        assert !payload.config.services.displayManager.autoLogin.enable;
        assert !(builtins.hasAttr "nixos" payload.config.users.users);
        assert builtins.elem "ohmansy-first-boot.socket" payload.config.systemd.services.greetd.requires;
        assert builtins.elem payload.config.system.build.toplevel media.config.isoImage.storeContents;
        assert !(payload.config.systemd.services ? ohmansy-installer);
        assert media.config.systemd.sockets.ohmansy-installer.socketConfig.SocketMode == "0600";
        assert media.config.systemd.sockets.ohmansy-installer.socketConfig.SocketUser == "nixos";
        packages.runCommand "ohmansy-offline-installer-policy" {
          nativeBuildInputs = [ media.pkgs.squashfsTools ];
        } ''
          touch registration
          mksquashfs registration ${link} test.squashfs -noappend -processors 1
          unsquashfs -d extracted test.squashfs
          test -L extracted/${builtins.baseNameOf link}
          test "$(readlink extracted/${builtins.baseNameOf link})" = ${target}
          touch "$out"
        '';
    in {
      overlays.default = final: _prev: {
        herdr = herdr.packages.${final.stdenv.hostPlatform.system}.default;
        mise = final.callPackage ./nix/modules/mise-package.nix { };
      };
      nixosModules.default = {
        imports = [ ./nix/modules/default.nix ];
        nixpkgs.overlays = [ self.overlays.default ];
      };
      nixosModules.desktop = import ./nix/modules/desktop.nix;
      nixosModules.software = {
        imports = [ ./nix/modules/software.nix ];
        nixpkgs.overlays = [ self.overlays.default ];
      };
      nixosModules.vm = import ./nix/modules/vm.nix;
      nixosModules.nvidia = import ./nix/modules/nvidia.nix;
      nixosModules.firstBoot = import ./nix/modules/first-boot.nix;
      nixosModules.updates = import ./nix/modules/updates.nix;
      nixosModules.agentSkills = import ./nix/modules/agent-skills.nix;
      nixosModules.development = import ./nix/modules/development.nix;
      nixosConfigurations.live = live;
      nixosConfigurations.appliance = appliance;
      nixosConfigurations.installer = installer;
      nixosConfigurations.live-x86_64 = pcLive;
      nixosConfigurations.appliance-x86_64 = pcAppliance;
      nixosConfigurations.installer-x86_64 = pcInstaller;
      nixosConfigurations.live-nvidia-x86_64 = pcNvidia;
      packages.${pcSystem} = desktopPackages pcPkgs // {
        portal-test-tools = import ./nix/tests/portal-tools.nix { pkgs = pcLive.pkgs; };
        installed-system-nvidia = pcInstalledNvidia.config.system.build.toplevel;
        iso = pcLive.config.system.build.isoImage;
        iso-nvidia = pcNvidia.config.system.build.isoImage;
        vm-image = pcAppliance.config.system.build.image;
        installer-iso = pcInstaller.config.system.build.isoImage;
        default = self.packages.${pcSystem}.iso;
      };
      checks.${pcSystem} = {
        compositor-drm = import ./nix/tests/compositor-drm.nix { pkgs = pcPkgs; };
        compositor-screenshots = import ./nix/tests/compositor-screenshots.nix { pkgs = pcPkgs; };
        cursor-theme = import ./nix/tests/cursor-theme.nix { pkgs = pcPkgs; };
        greeter-ui = import ./nix/tests/greeter-ui.nix { pkgs = pcPkgs; };
        greeter-auth = pcPkgs.runCommand "ohmansy-greeter-auth" {
          nativeBuildInputs = [ pcPkgs.python3 (import ./nix/modules/greeter-package.nix { pkgs = pcPkgs; }) ];
        } ''
          export HOME="$TMPDIR"
          python3 ${./nix}/tests/greeter-auth.py
          touch "$out"
        '';
        displays-ui = import ./nix/tests/displays-ui.nix { pkgs = pcPkgs; };
        installer-ui = import ./nix/tests/installer-ui.nix { pkgs = pcPkgs; };
        offline-installer = offlinePolicy pcPkgs pcInstalledBase pcInstaller;
        offline-installer-nvidia =
          assert pcInstalledNvidia.config.hardware.nvidia.open;
          assert pcInstalledNvidia.config.hardware.nvidia.modesetting.enable;
          assert pcInstalledNvidia.config.services.xserver.videoDrivers == [ "nvidia" ];
          assert builtins.elem "nouveau" pcInstalledNvidia.config.boot.blacklistedKernelModules;
          assert builtins.elem pcInstalledNvidia.pkgs.autoAddDriverRunpath pcInstalledNvidia.pkgs.btop.nativeBuildInputs;
          assert pcInstaller.config.environment.etc."ohmansy/installed-system-nvidia".source
            == pcInstalledNvidia.config.system.build.toplevel;
          offlinePolicy pcPkgs pcInstalledNvidia pcInstaller;
        factory-platform = import ./nix/tests/factory-platform.nix {
          pkgs = pcPkgs;
          appliance = pcAppliance;
        };
        ribbons = import ./nix/tests/ribbons.nix { pkgs = pcPkgs; };
        live-pc-policy = import ./nix/tests/live-pc.nix {
          inherit nixpkgs pcLive pcNvidia;
          pkgs = pcPkgs;
          installedSystems = [ pcInstalledBase pcAppliance ];
        };
        customization = import ./nix/tests/customization.nix {
          inherit nixpkgs;
          ohmansyModules = self.nixosModules;
          herdrPackage = herdr.packages.${pcSystem}.default;
          misePackage = self.packages.${pcSystem}.mise;
          pkgs = pcPkgs;
          system = pcSystem;
        };
      };
      packages.${system} = desktopPackages pkgs // {
        portal-test-tools = import ./nix/tests/portal-tools.nix { pkgs = live.pkgs; };
        installation = import ./nix/modules/installation-package.nix { inherit pkgs; };
        vm-image = appliance.config.system.build.image;
        iso = live.config.system.build.isoImage;
        installer-iso = installer.config.system.build.isoImage;
        default = self.packages.${system}.vm-image;
      };
      checks.${system} = {
        cursor-theme = import ./nix/tests/cursor-theme.nix { inherit pkgs; };
        greeter-ui = import ./nix/tests/greeter-ui.nix { inherit pkgs; };
        displays-ui = import ./nix/tests/displays-ui.nix { inherit pkgs; };
        installer-ui = import ./nix/tests/installer-ui.nix { inherit pkgs; };
        offline-installer = offlinePolicy pkgs installedBase installer;
        factory-platform = import ./nix/tests/factory-platform.nix { inherit pkgs appliance; };
        ribbons = import ./nix/tests/ribbons.nix { inherit pkgs; };
        development-module = import ./nix/tests/development.nix { inherit nixpkgs pkgs system; };
        customization = import ./nix/tests/customization.nix {
          inherit nixpkgs pkgs system;
          ohmansyModules = self.nixosModules;
          herdrPackage = herdr.packages.${system}.default;
          misePackage = self.packages.${system}.mise;
        };
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
          assert live.config.services.displayManager.defaultSession == "ohmansy";
          assert !(builtins.hasAttr "hmans" live.config.users.users);
          pkgs.runCommand "ohmansy-live-policy" { } ''touch "$out"'';
      };
      devShells = nixpkgs.lib.genAttrs [ system pcSystem ] (target:
        let tools = import nixpkgs { system = target; overlays = [ self.overlays.default ]; };
        in { spatial = tools.mkShell {
          OHMANSY_COMPOSITOR_SHELL = "${import ./nix/modules/shine-shell.nix { pkgs = tools; }}/bin/ohmansy-shine-shell";
          packages = with tools; [ rustup pkg-config gcc tools.mise (python3.withPackages (p: [ p.pillow ])) niri weston dbus quickshell wl-clipboard xdg-user-dirs satty foot firefox gnome-text-editor mako ];
          buildInputs = with tools; [ wayland libxkbcommon libGL libgbm libdrm libinput seatd udev gtk4 ];
          LD_LIBRARY_PATH = nixpkgs.lib.makeLibraryPath (with tools; [ wayland libxkbcommon libGL ]);
          OHMANSY_SPATIAL_FONT = "${tools.inter}/share/fonts/truetype/Inter.ttc";
          shellHook = ''. ${(import ./nix/modules/cursor-theme.nix { pkgs = tools; }).environment}'';
        }; default = tools.mkShell {
          packages = with tools; [ git nixfmt nil statix python3 niri ripgrep tools.mise ];
        }; });
    };
}
