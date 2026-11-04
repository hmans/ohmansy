//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma UseQApplication
import QtQuick
import Quickshell
import Quickshell.Io

ShellRoot {
    id: root
    property bool inFlight: false
    readonly property bool busy: inFlight && operation !== "status"
    property var queued: null
    property string error: ""
    property var state: ({status: "idle"})
    property var disks: []
    property string payload: ""
    property string operation: ""
    function request(action, args) {
        if (inFlight) {
            if (action !== "status" && operation === "status") queued = {action: action, args: args};
            return;
        }
        operation = action;
        if (action !== "status") error = "";
        payload = JSON.stringify(Object.assign({action: action}, args || {})) + "\n";
        inFlight = true;
        deadline.restart();
        backend.connected = true;
    }
    Component.onCompleted: request("status")
    Socket {
        id: backend
        path: "/run/ohmansy-installer.sock"
        onConnectedChanged: if (connected) { write(root.payload); flush(); root.payload = ""; }
        parser: SplitParser {
            onRead: data => {
                deadline.stop();
                backend.connected = false;
                root.inFlight = false;
                try {
                    const reply = JSON.parse(data);
                    if (!reply.ok) root.error = reply.error || "The installer could not complete that request.";
                    else {
                        if (reply.status) root.state = reply;
                        if (reply.disks) root.disks = reply.disks;
                        if (root.operation === "status" && root.error.startsWith("Connection")) root.error = "";
                    }
                } catch (e) { root.error = "Connection lost. Reconnecting to the installer; any running installation continues."; }
                if (root.queued) {
                    const pending = root.queued;
                    root.queued = null;
                    Qt.callLater(() => root.request(pending.action, pending.args));
                }
            }
        }
    }
    Timer { id: deadline; interval: 8000; onTriggered: { backend.connected = false; root.payload = ""; root.queued = null; root.inFlight = false; root.error = "Connection unavailable. Reconnecting; do not restart an installation that may already be running."; } }
    Timer { interval: 1500; running: true; repeat: true; onTriggered: if (!root.inFlight && !root.queued) root.request("status") }
    FloatingWindow {
        onClosed: Qt.quit()
        title: "Install ohmansy"
        visible: true
        implicitWidth: 1180
        implicitHeight: 800
        color: "#171a21"
        InstallerView { anchors.fill: parent; controller: root }
    }
}
