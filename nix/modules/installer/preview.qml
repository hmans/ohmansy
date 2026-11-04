//@ pragma UseQApplication
import QtQuick
import Quickshell

ShellRoot {
    QtObject {
        id: demo
        property bool busy: false
        property string error: ""
        property var state: ({status: "idle", stage: "install", device: "/dev/nvme0n1", hostname: "space-potato", log: "Preview only. No disks are touched.", destructive: false})
        property var disks: [{path: "/dev/nvme0n1", model: "Example NVMe · definitely a demo", size: 512 * 1073741824, token: "preview-a"}, {path: "/dev/sda", model: "Example external SSD", size: 256 * 1073741824, token: "preview-b"}]
        function request(action, args) {
            if (action === "start") { state = Object.assign({}, state, {status: "running", hostname: args.hostname, device: args.device}); complete.restart(); }
            if (action === "shutdown") error = "Preview only. Your computer is staying right here.";
        }
    }
    Timer { id: complete; interval: 5000; onTriggered: demo.state = Object.assign({}, demo.state, {status: "done", stage: "done"}) }
    FloatingWindow {
        onClosed: Qt.quit()
        visible: true; title: "Ohmansy installer preview · no disk access"
        implicitWidth: Number(Quickshell.env("PREVIEW_WIDTH")) || 1180
        implicitHeight: Number(Quickshell.env("PREVIEW_HEIGHT")) || 800
        color: "#171a21"
        InstallerView {
            id: view; anchors.fill: parent; controller: demo
            Component.onCompleted: Qt.callLater(() => { selected = demo.disks[0]; page = Quickshell.env("PREVIEW_PAGE") || "welcome"; })
        }
        Timer { running: Quickshell.env("PREVIEW_IMAGE") !== ""; interval: 1800; onTriggered: view.grabToImage(result => { result.saveToFile(Quickshell.env("PREVIEW_IMAGE")); Qt.quit(); }) }
    }
}
