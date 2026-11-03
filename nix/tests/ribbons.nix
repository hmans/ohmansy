{ pkgs }:
let
  ribbons = import ../modules/greeter-ribbons.nix { inherit pkgs; };
in pkgs.runCommand "ohmansy-ribbons-render-check" {
  nativeBuildInputs = [ pkgs.stdenv.cc pkgs.pkg-config pkgs.xvfb-run ];
  buildInputs = [ pkgs.qt6.qtbase pkgs.qt6.qtdeclarative ];
  dontWrapQtApps = true;
} ''
  c++ -std=c++17 ${./ribbons.cpp} -I${../modules/greeter/ribbons} \
    $(pkg-config --cflags --libs Qt6Quick Qt6OpenGL) \
    -L${ribbons}/lib/qt-6/qml/Ohmansy/Welcome -lohmansy-welcome \
    -Wl,-rpath,${ribbons}/lib/qt-6/qml/Ohmansy/Welcome -o ribbon-check
  export HOME="$TMPDIR"
  export XDG_RUNTIME_DIR="$TMPDIR/runtime"
  mkdir -m 700 "$XDG_RUNTIME_DIR"
  export QT_QPA_PLATFORM=xcb QT_XCB_GL_INTEGRATION=xcb_egl
  export LIBGL_ALWAYS_SOFTWARE=1 GALLIUM_DRIVER=llvmpipe
  export __EGL_VENDOR_LIBRARY_FILENAMES=${pkgs.mesa}/share/glvnd/egl_vendor.d/50_mesa.json
  xvfb-run -a ./ribbon-check desktop
  xvfb-run -a ./ribbon-check es
  touch "$out"
''
