{ pkgs }:
pkgs.runCommand "ohmansy-quickshell-ui" {} ''
  mkdir -p "$out/lib/qt-6/qml/Ohmansy/Ui"
  cp -r ${./ui}/. "$out/lib/qt-6/qml/Ohmansy/Ui/"
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
''
