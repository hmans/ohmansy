import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: root
    property var outputs: []
    property string error: ""
    property string message: ""
    property bool pending: false
    property int seconds: 0
    readonly property bool busy: reader.running || writer.running
    readonly property string helper: Quickshell.env("OHMANSY_DISPLAYS")
    function refresh(clearError = true) {
        if (busy) return;
        if (clearError) error = "";
        reader.running = true;
    }
    function apply(name, scale, mode) {
        if (busy) return;
        error = "";
        message = "";
        writer.command = [Quickshell.env("OHMANSY_DISPLAY_PREVIEW"), name, String(scale), mode];
        writer.running = true;
    }
    function decide(keep) {
        if (writer.running) writer.write(keep ? "keep\n" : "revert\n");
    }
    Timer {
        interval: 1000
        repeat: true
        running: root.pending
        onTriggered: root.seconds = Math.max(0, root.seconds - 1)
    }
    Process {
        id: reader
        command: [root.helper, "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text);
                    if (!Array.isArray(data)) throw new Error("Invalid display list");
                    root.outputs = data;
                } catch (error) { root.error = "Could not read displays. Try Refresh."; }
            }
        }
        onExited: (code, status) => {
            if (code !== 0 || status !== 0) root.error = "Could not read displays. Try Refresh.";
        }
    }
    Process {
        id: writer
        stdinEnabled: true
        stdout: SplitParser {
            onRead: data => {
                try {
                    const state = JSON.parse(data);
                    root.pending = state.status === "preview";
                    if (root.pending) root.seconds = state.seconds;
                    if (state.status === "error") root.error = state.message;
                    if (state.status === "kept") root.message = "Display settings saved.";
                    if (state.status === "reverted") root.message = "Previous display settings restored.";
                } catch (error) { root.error = "Could not read the display change result."; }
            }
        }
        onExited: (code, status) => {
            root.pending = false;
            if ((code !== 0 || status !== 0) && !root.error)
                root.error = "Could not change the display. Try Refresh.";
            Qt.callLater(() => root.refresh(false));
        }
    }
}
