import Quickshell
import Quickshell.Io

Scope {
    id: root
    property string preference: ""
    property string error: ""
    readonly property bool busy: writer.running
    readonly property string helper: Quickshell.env("OHMANSY_APPEARANCE")
    function select(value) {
        if (writer.running) return;
        error = "";
        writer.command = [helper, value];
        writer.running = true;
    }
    Process {
        id: reader
        command: [root.helper, "read"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: root.preference = text.trim().replace(/'/g, "")
        }
        onExited: (code, status) => {
            if (code !== 0 || status !== 0) root.error = "Could not read appearance settings.";
        }
    }
    Process {
        id: writer
        onExited: (code, status) => {
            if (code !== 0 || status !== 0) root.error = "Could not save appearance. Try again.";
            reader.running = true;
        }
    }
    Process {
        command: [root.helper, "monitor"]
        running: true
        stdout: SplitParser { onRead: data => reader.running = true }
    }
}
