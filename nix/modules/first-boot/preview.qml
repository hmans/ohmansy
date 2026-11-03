//@ pragma UseQApplication
import QtQuick
import Quickshell

ShellRoot {
    QtObject {
        id: demo
        property bool busy: false
        property string error: ""
        property string pendingUser: ""
        signal created()
        function request(action, username, name, password) { created(); }
    }
    FloatingWindow {
        visible: true
        implicitWidth: Number(Quickshell.env("PREVIEW_WIDTH")) || 1100
        implicitHeight: Number(Quickshell.env("PREVIEW_HEIGHT")) || 800
        color: "#171a21"
        SetupView {
            id: view
            anchors.fill: parent
            controller: demo
            Component.onCompleted: Qt.callLater(() => { page = Quickshell.env("PREVIEW_PAGE") || "welcome"; })
        }
        Timer {
            running: Quickshell.env("PREVIEW_IMAGE") !== ""
            interval: 1500
            onTriggered: view.grabToImage(result => {
                result.saveToFile(Quickshell.env("PREVIEW_IMAGE"));
                Qt.quit();
            })
        }
    }
}
