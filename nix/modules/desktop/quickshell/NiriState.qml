import QtQuick
import Quickshell
import Quickshell.Io
import "Niri.js" as Niri

Scope {
    id: root
    property var state: ({ workspaces: [], windows: [] })
    readonly property string command: Quickshell.env("OHMANSY_NIRI") || "niri"
    readonly property string focusedOutput: {
        var focused = state.workspaces.find(w => w.is_focused);
        return focused ? focused.output || "" : "";
    }
    property var workspaceQueue: []
    function focusWorkspace(id: int): void {
        workspaceQueue = workspaceQueue.concat([id]);
        if (!workspaceAction.connected) workspaceAction.connected = true;
    }
    // The CLI accepts indices/names; the socket also accepts stable workspace IDs
    // and focuses the correct monitor in the same action.
    Socket {
        id: workspaceAction
        path: Quickshell.env("NIRI_SOCKET") || ""
        onConnectedChanged: if (connected && root.workspaceQueue.length) {
            write(JSON.stringify({ Action: { FocusWorkspace: { reference: { Id: root.workspaceQueue[0] } } } }) + "\n");
            flush();
        }
        parser: SplitParser {
            onRead: data => {
                workspaceAction.connected = false;
                root.workspaceQueue = root.workspaceQueue.slice(1);
                if (root.workspaceQueue.length) Qt.callLater(() => workspaceAction.connected = true);
            }
        }
    }
    Process {
        id: events
        running: true
        command: [root.command, "msg", "--json", "event-stream"]
        stdout: SplitParser {
            onRead: data => {
                try { root.state = Niri.update(root.state, JSON.parse(data)); }
                catch (error) { console.warn("Niri event:", error); }
            }
        }
        onExited: retry.start()
    }
    Timer { id: retry; interval: 1000; onTriggered: events.running = true }
}
