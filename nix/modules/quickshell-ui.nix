{ pkgs }:
pkgs.runCommand "ohmansy-quickshell-ui" {} ''
  mkdir -p "$out/lib/qt-6/qml/Ohmansy/Ui"
  cp -r ${./ui}/. "$out/lib/qt-6/qml/Ohmansy/Ui/"
''
