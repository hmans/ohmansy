//@ pragma UseQApplication
import QtQuick
import Quickshell

ShellRoot {
    FloatingWindow {
        visible: true
        implicitWidth: Number(Quickshell.env("PREVIEW_WIDTH")) || 1100
        implicitHeight: Number(Quickshell.env("PREVIEW_HEIGHT")) || 720
        color: "#171a21"
        GreeterPreview { anchors.fill: parent }
    }
}
