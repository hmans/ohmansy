//@ pragma UseQApplication
import QtQuick
import Quickshell

// Standalone visual preview. No authentication service or power operations.
ShellRoot {
    id: preview
    property var users: [{ name: "alex", label: "Alex" }]
    property string powerAction: ""
    function confirmPower() { powerAction = ""; }
    QtObject {
        id: demo
        property bool waiting: true
        property bool busy: false
        property string prompt: "Password"
        property bool echo: false
        property string message: ""
        property string user: "alex"
        signal clearResponse()
        function selectUser(name) { user = name; waiting = name !== ""; clearResponse(); }
        function submit(response) { clearResponse(); message = "Preview only. No password was sent."; }
    }
    FloatingWindow {
        visible: true
        implicitWidth: Number(Quickshell.env("PREVIEW_WIDTH")) || 1100
        implicitHeight: Number(Quickshell.env("PREVIEW_HEIGHT")) || 720
        color: "#171a21"
        GreeterView {
            id: view
            anchors.fill: parent
            controller: preview
            auth: demo
            now: new Date()
            primary: true
        }
        Timer {
            running: Quickshell.env("PREVIEW_IMAGE") !== ""
            interval: 1000
            onTriggered: view.grabToImage(function(result) {
                result.saveToFile(Quickshell.env("PREVIEW_IMAGE"));
                Qt.quit();
            })
        }
    }
}
