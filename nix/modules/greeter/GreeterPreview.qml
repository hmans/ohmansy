import QtQuick
import Quickshell

// Standalone visual preview. No authentication service or power operations.
Item {
    id: preview
    property var users: [{ name: "alex", label: "Alex" }, { name: "sam", label: "Sam" }]
    property bool powerMenuOpen: false
    function confirmPower(action) { powerMenuOpen = false; }
    // Exercise both transition directions without invoking real power actions.
    Timer {
        interval: 1200
        running: Quickshell.env("PREVIEW_TRANSITIONS") === "1"
        onTriggered: preview.powerMenuOpen = true
    }
    Timer {
        interval: 2400
        running: Quickshell.env("PREVIEW_TRANSITIONS") === "1"
        onTriggered: preview.powerMenuOpen = false
    }
    QtObject {
        id: demo
        property bool waiting: true
        property bool busy: false
        property string prompt: "Password"
        property bool echo: false
        property string message: ""
        property string user: "alex"
        property var sessions: [{ id: "niri", label: "ohmansy (Niri)" },
            { id: "ohmansy", label: "Shine (experimental)" }]
        property int sessionIndex: Quickshell.env("PREVIEW_SESSION") === "ohmansy" ? 1 : 0
        signal clearResponse()
        function selectSession(index) { if (!busy) { sessionIndex = index; clearResponse(); } }
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
            running: Quickshell.env("GREETER_FLOW_TEST") === "1"
            interval: 200
            onTriggered: {
                const picker = view.sessionPicker;
                if (picker.count !== 2 || picker.currentIndex !== 0)
                    throw new Error("Default session missing");
                picker.currentIndex = 1;
                picker.activated(1);
                if (demo.sessionIndex !== 1 || picker.currentText !== "Shine (experimental)")
                    throw new Error("Session selection failed");
                demo.busy = true;
                if (picker.enabled) throw new Error("Session selection enabled during authentication");
                demo.busy = false;
                console.info("GREETER_FLOW_TEST passed");
                Qt.quit();
            }
        }
        Timer {
            running: Quickshell.env("PREVIEW_SESSION_MENU") === "1"
            interval: 300
            onTriggered: view.sessionPicker.popup.open()
        }
        Timer {
            running: !!Quickshell.env("PREVIEW_IMAGE")
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
