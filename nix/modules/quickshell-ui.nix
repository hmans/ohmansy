{ pkgs }:
pkgs.runCommand "ohmansy-quickshell-ui" {} ''
  mkdir -p "$out/lib/qt-6/qml/Ohmansy/Ui"
  cp -r ${./ui}/. "$out/lib/qt-6/qml/Ohmansy/Ui/"
  cp ${./greeter/scene/Ribbons.qml} "$out/lib/qt-6/qml/Ohmansy/Ui/Ribbons.qml"
  cp ${./desktop/wallpapers/twilight-cat.png} "$out/lib/qt-6/qml/Ohmansy/Ui/wallpaper.png"
''
