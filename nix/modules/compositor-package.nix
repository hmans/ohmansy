{ pkgs }:
pkgs.rustPlatform.buildRustPackage {
  pname = "ohmansy-compositor";
  version = "0.1.0";
  src = pkgs.lib.cleanSource ../compositor;
  cargoHash = "sha256-12XS/brE2MTRi82HPyOW6lU/gR+eSHu80ebi+uQAHRQ=";
  nativeBuildInputs = [
    pkgs.pkg-config
    pkgs.makeWrapper
  ];
  buildInputs = [
    pkgs.wayland
    pkgs.libxkbcommon
    pkgs.libGL
  ];
  OHMANSY_COMPOSITOR_ASSETS = "${../compositor}";
  postFixup = ''
    wrapProgram "$out/bin/ohmansy-compositor" \
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
