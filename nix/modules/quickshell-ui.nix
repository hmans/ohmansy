{ pkgs }:
let support = import ./notifications-support.nix { inherit pkgs; };
in pkgs.runCommand "ohmansy-quickshell-ui" { nativeBuildInputs = [ pkgs.qt6.qtshadertools ]; } ''
  mkdir -p "$out/lib/qt-6/qml"
  cp -r ${support}/lib/qt-6/qml/. "$out/lib/qt-6/qml/"
  chmod -R u+w "$out/lib/qt-6/qml"
  mkdir -p "$out/lib/qt-6/qml/Ohmansy/Notifications"
  cp ${./notifications}/*.qml ${./notifications}/qmldir "$out/lib/qt-6/qml/Ohmansy/Notifications/"
  mkdir -p "$out/lib/qt-6/qml/Ohmansy/Ui"
  cp -r ${./ui}/. "$out/lib/qt-6/qml/Ohmansy/Ui/"
  mkdir -p frame-shader
  cp ${./ui/shaders/frame-surface.frag} frame-shader/frame-surface.frag
  cp ${../compositor/src/rounded-coverage.glsl} frame-shader/rounded-coverage.glsl
  sed '/^uniform /d' ${../compositor/src/frame-lighting.glsl} > frame-shader/frame-lighting.glsl
  qsb --glsl '100 es,120,150' --hlsl 50 --msl 12 \
    -o frame-shader/frame-surface.frag.qsb frame-shader/frame-surface.frag
  # qsb may return success after an output write failure. Check the asset before
  # installing it; copied source subdirectories retain the store's read-only mode.
  test -s frame-shader/frame-surface.frag.qsb
  chmod u+w "$out/lib/qt-6/qml/Ohmansy/Ui/shaders"
  cp frame-shader/frame-surface.frag.qsb "$out/lib/qt-6/qml/Ohmansy/Ui/shaders/"
  cp ${./greeter/scene/Ribbons.qml} "$out/lib/qt-6/qml/Ohmansy/Ui/Ribbons.qml"
  cp ${./desktop/wallpapers/twilight-cat.png} "$out/lib/qt-6/qml/Ohmansy/Ui/wallpaper.png"
  mkdir -p "$out/lib/qt-6/qml/Ohmansy/Displays"
  for component in DisplayView DisplayState QuietButton Theme; do
    cp ${./desktop/quickshell}/"$component.qml" "$out/lib/qt-6/qml/Ohmansy/Displays/"
  done
  cat > "$out/lib/qt-6/qml/Ohmansy/Displays/qmldir" <<'EOF'
  module Ohmansy.Displays
  DisplayView 1.0 DisplayView.qml
  DisplayState 1.0 DisplayState.qml
  EOF
  mkdir -p "$out/lib/qt-6/qml/Ohmansy/Launcher"
  cp -r ${./launcher}/. "$out/lib/qt-6/qml/Ohmansy/Launcher/"
  cat > "$out/lib/qt-6/qml/Ohmansy/Launcher/qmldir" <<'EOF'
  module Ohmansy.Launcher
  CommandLauncher 1.0 CommandLauncher.qml
  EOF
  mkdir -p "$out/lib/qt-6/qml/Ohmansy/Desktop"
  for component in AudioState AppearanceState; do
    cp ${./desktop/quickshell}/"$component.qml" "$out/lib/qt-6/qml/Ohmansy/Desktop/"
  done
  cat > "$out/lib/qt-6/qml/Ohmansy/Desktop/qmldir" <<'EOF'
  module Ohmansy.Desktop
  AudioState 1.0 AudioState.qml
  AppearanceState 1.0 AppearanceState.qml
  EOF
''
