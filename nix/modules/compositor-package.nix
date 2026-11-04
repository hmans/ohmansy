{ pkgs }:
let
  cursor = import ./cursor-theme.nix { inherit pkgs; };
in
pkgs.rustPlatform.buildRustPackage {
  pname = "ohmansy-compositor";
  version = "0.1.0";
  src = pkgs.lib.cleanSource ../compositor;
  cargoHash = "sha256-pDd7sc/msQWtla1pImiulWIozOxqK2T69Bk7XqHRw98=";
  nativeBuildInputs = [
    pkgs.pkg-config
    pkgs.makeWrapper
  ];
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
  OHMANSY_COMPOSITOR_ASSETS = "${../compositor}";
  postFixup = ''
    wrapProgram "$out/bin/ohmansy-compositor" \
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
}
