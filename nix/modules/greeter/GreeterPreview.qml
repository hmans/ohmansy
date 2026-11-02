import QtQuick
import Quickshell

// Standalone visual preview. No authentication service or power operations.
Item {
    id: preview
    property var users: [{ name: "alex", label: "Alex" }, { name: "sam", label: "Sam" }]
    property string powerAction: ""
    function confirmPower() { powerAction = ""; }
    // Exercise both transition directions without invoking real power actions.
    Timer {
        interval: 1200
        running: Quickshell.env("PREVIEW_TRANSITIONS") === "1"
        onTriggered: preview.powerAction = "reboot"
    }
    Timer {
        interval: 2400
        running: Quickshell.env("PREVIEW_TRANSITIONS") === "1"
        onTriggered: preview.powerAction = ""
    }
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
    component PreviewSurface: Item {
        GreeterView {
            id: view
            anchors.fill: parent
            controller: preview
            auth: demo
            now: new Date()
            primary: true
            motionEnabled: Quickshell.env("PREVIEW_MOTION") !== "0"
        }
        Timer {
            running: Quickshell.env("PREVIEW_IMAGE") !== ""
            interval: Number(Quickshell.env("PREVIEW_DELAY")) || 1000
            onTriggered: view.grabToImage(function(result) {
                result.saveToFile(Quickshell.env("PREVIEW_IMAGE"));
                Qt.quit();
            })
        }
        Timer {
            running: Quickshell.env("PREVIEW_STATS") === "1"
            interval: 2000
            repeat: true
            onTriggered: {
                if (view.sceneStats)
                    console.info("3D preview: fps=" + view.sceneStats.fps
                        + " frameTime=" + view.sceneStats.frameTime);
            }
        }
    }
    PreviewSurface { anchors.fill: parent }
}
