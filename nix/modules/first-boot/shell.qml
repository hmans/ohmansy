//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma UseQApplication
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

ShellRoot {
    id: root
    property bool busy: false
    property string error: ""
    property string pendingUser: ""
    property string payload: ""
    property string operation: ""
    signal created()
    function request(action, username, name, password) {
        if (busy) return;
        error = "";
        operation = action;
        payload = JSON.stringify({action: action, username: username || "", name: name || "", password: password || ""}) + "\n";
        busy = true;
        deadline.restart();
        backend.connected = true;
    }
    Component.onCompleted: request("status")
    Socket {
        id: backend
        path: "/run/ohmansy-first-boot.sock"
        onConnectedChanged: if (connected) {
            write(root.payload);
            flush();
            root.payload = "";
        }
        parser: SplitParser {
            onRead: data => {
                deadline.stop();
                backend.connected = false;
                root.busy = false;
                try {
                    const reply = JSON.parse(data);
                    if (!reply.ok) root.error = reply.error || "Setup could not finish. Try again.";
                    else if (reply.complete) root.created();
                    else if (root.operation === "status") root.pendingUser = reply.pending || "";
                    else root.created();
                } catch (e) { root.error = "Setup lost its connection. Please try again."; }
            }
        }
    }
    Timer {
        id: deadline
        interval: 15000
        onTriggered: {
            backend.connected = false;
            root.payload = "";
            root.busy = false;
            root.error = "Setup is taking too long. Please try again.";
        }
    }
    Variants {
        model: Quickshell.screens
        PanelWindow {
            required property var modelData
            screen: modelData
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: modelData === Quickshell.screens[0] ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            color: "#171a21"
            SetupView { anchors.fill: parent; controller: root; primary: modelData === Quickshell.screens[0] }
        }
    }
}
