//@ pragma UseQApplication
import QtQuick
import Quickshell

ShellRoot {
    QtObject {
        id: demo
        property bool busy: false
        property int starts: 0
        property var lastStart: null
        property string error: ""
        property var state: ({status: "idle", stage: "install", device: "/example/demo-disk-1", hostname: "space-potato", log: "Preview only. No disks are touched.", destructive: false})
        property var disks: [{path: "/example/demo-disk-1", model: "Demo disk 1 (not a real disk)", size: 512 * 1073741824, token: "preview-a"}, {path: "/example/demo-disk-2", model: "Demo disk 2 (not a real disk)", size: 256 * 1073741824, token: "preview-b"}]
        function request(action, args) {
            if (action === "start" && Quickshell.env("INSTALLER_FLOW_TEST") === "1") { starts++; lastStart = args; return; }
            if (action === "start") { state = Object.assign({}, state, {status: "running", hostname: args.hostname, device: args.device}); complete.restart(); }
            if (action === "shutdown") error = "Preview only. Your computer is staying right here.";
        }
    }
    Timer { id: complete; interval: 5000; onTriggered: demo.state = Object.assign({}, demo.state, {status: "done", stage: "done"}) }
    FloatingWindow {
        onClosed: Qt.quit()
        visible: true; title: "ohmansy installer preview · no disk access"
        implicitWidth: Number(Quickshell.env("PREVIEW_WIDTH")) || 1180
        implicitHeight: Number(Quickshell.env("PREVIEW_HEIGHT")) || 800
        color: "#171a21"
        InstallerView {
            id: view; anchors.fill: parent; controller: demo
            Component.onCompleted: Qt.callLater(() => { selected = demo.disks[0]; page = Quickshell.env("PREVIEW_PAGE") || "welcome"; })
        }
        Timer {
            running: !!Quickshell.env("PREVIEW_IMAGE")
            interval: 1800
            onTriggered: {
                const bar = view.children.find(item => item.objectName === "installerActions");
                const scroll = view.children.find(item => item.objectName === "installerScroll");
                if (!bar || !scroll || scroll.y + scroll.height > bar.y + 1)
                    throw new Error("Content overlaps the action bar");
                let count = 0;
                function checkActions(item) {
                    if (!item.visible) return;
                    if (item.objectName === "installerAction") {
                        const position = item.mapToItem(view, 0, 0);
                        if (position.x < 0 || position.y < 0 || position.x + item.width > view.width + 1 || position.y + item.height > view.height + 1)
                            throw new Error("Action is outside the window: " + item.text);
                        if (item.contentItem.implicitWidth > item.width - item.leftPadding - item.rightPadding + 1)
                            throw new Error("Action label is clipped: " + item.text);
                        count++;
                    }
                    for (const child of item.children || []) checkActions(child);
                }
                checkActions(bar);
                if (view.page !== "progress" && count === 0) throw new Error("Missing page actions");
                const top = bar.y;
                const previousScroll = scroll.contentY;
                scroll.contentY = Math.max(0, scroll.contentHeight - scroll.height);
                if (bar.y !== top) throw new Error("Action bar moved with scrolling");
                checkActions(bar);
                scroll.contentY = previousScroll;
                view.grabToImage(result => { result.saveToFile(Quickshell.env("PREVIEW_IMAGE")); Qt.quit(); });
            }
        }
        Timer {
            running: Quickshell.env("INSTALLER_FLOW_TEST") === "1"
            interval: 100
            onTriggered: {
                function check(condition, message) { if (!condition) throw new Error(message); }
                view.go("confirm");
                view.start();
                check(demo.starts === 0, "Unacknowledged erasure started");
                view.eraseAcknowledged = true;
                view.go("disks");
                view.go("confirm");
                check(!view.eraseAcknowledged, "Back retained acknowledgement");
                view.eraseAcknowledged = true;
                view.choose(demo.disks[1]);
                check(!view.eraseAcknowledged, "Disk change retained acknowledgement");
                view.eraseAcknowledged = true;
                demo.busy = true;
                view.start();
                check(demo.starts === 0, "Busy controller accepted start");
                demo.busy = false;
                view.start();
                view.start();
                check(demo.starts === 1, "Confirmation did not start exactly once");
                check(demo.lastStart.device === demo.disks[1].path && demo.lastStart.token === demo.disks[1].token && demo.lastStart.confirmation === "ERASE " + demo.disks[1].path, "Confirmation targeted wrong disk");
                view.eraseAcknowledged = true;
                demo.disks = [];
                check(!view.selected && !view.eraseAcknowledged, "Removed disk retained acknowledgement");
                view.start();
                check(demo.starts === 1, "Removed disk accepted start");
                console.log("INSTALLER_FLOW_TEST passed");
                Qt.quit();
            }
        }
    }
}
