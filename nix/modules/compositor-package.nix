{ pkgs }:
let
  cursor = import ./cursor-theme.nix { inherit pkgs; };
  # Pin the build helper here so standalone module imports use the same cache
  # layout as flake packages, without needing an additional overlay.
  crane = import (pkgs.fetchFromGitHub {
    owner = "ipetkov";
    repo = "crane";
    rev = "79fd63528501446749c09f08cad486a58c7d173e";
    hash = "sha256-TREenflwEjxOSq292FYwbc3kEm7TDRtXCZRNWEdjBmg=";
  }) { inherit pkgs; };
  common = {
    pname = "ohmansy-compositor";
    version = "0.1.0";
    src = pkgs.lib.cleanSource ../compositor;
    nativeBuildInputs = [ pkgs.pkg-config ];
    buildInputs = [
      pkgs.wayland
      pkgs.libxkbcommon
      pkgs.libGL
      pkgs.libgbm
      pkgs.libdrm
      pkgs.libinput
      pkgs.seatd
      pkgs.udev
    ];
  };
  # Only Cargo manifests, the lock file, toolchain and build inputs determine
  # these artifacts. Keep source-dependent paths and wrapping out of this build.
  cargoArtifacts = crane.buildDepsOnly common;
in
crane.buildPackage (common // {
  inherit cargoArtifacts;
  nativeBuildInputs = common.nativeBuildInputs ++ [ pkgs.makeWrapper ];
  OHMANSY_COMPOSITOR_ASSETS = "${../compositor}";
  postFixup = ''
    wrapProgram "$out/bin/ohmansy-compositor" \
      --prefix PATH : ${pkgs.lib.makeBinPath [ pkgs.coreutils pkgs.wl-clipboard pkgs.xdg-user-dirs pkgs.satty ]} \
      --run '. ${cursor.environment}' \
      --prefix LD_LIBRARY_PATH : ${
        pkgs.lib.makeLibraryPath [
          pkgs.wayland
          pkgs.libxkbcommon
          pkgs.libGL
        ]
      }
  '';
  meta = {
    description = "Shine, the experimental scrolling Wayland compositor for ohmansy";
    platforms = pkgs.lib.platforms.linux;
    mainProgram = "ohmansy-compositor";
  };
})
