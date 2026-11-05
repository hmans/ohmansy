//@ pragma Env QS_NO_RELOAD_POPUP=1
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import Ohmansy.Ui

ShellRoot {
    id: root
    property var state: ({ outputs: [] })
    property var requests: []
    function request(action, output, value) {
        requests = requests.concat([{ action: action, output: output, value: value }]);
        if (!control.connected) control.connected = true;
    }
    Socket {
        id: control
        readonly property string controlPath: Quickshell.env("OHMANSY_COMPOSITOR_CONTROL")
        path: controlPath.startsWith("/") ? controlPath : Quickshell.env("PWD") + "/" + controlPath
        onConnectedChanged: if (connected) {
            const request = root.requests.length ? root.requests[0] : { action: "status" };
            if (root.requests.length) root.requests = root.requests.slice(1);
            write(JSON.stringify(request) + "\n");
            flush();
        }
        parser: SplitParser {
            onRead: data => {
                try {
                    const reply = JSON.parse(data);
                    if (reply.ok) root.state = reply.state;
                    else console.warn("Shine:", reply.error);
                } catch (error) { console.warn("Shine:", error); }
                control.connected = false;
                if (root.requests.length) Qt.callLater(() => control.connected = true);
            }
        }
    }
    Timer { interval: 250; running: true; repeat: true; triggeredOnStart: true; onTriggered: if (!control.connected) control.connected = true }
    SystemClock { id: clock; precision: SystemClock.Minutes }
    Variants {
        model: Quickshell.screens
        PanelWindow {
            id: bar
            required property var modelData
            screen: modelData
            readonly property var output: root.state.outputs.find(o => o.name === modelData.name) || ({ workspace: 1 })
            anchors { top: true; left: true; right: true }
            implicitHeight: 44
            exclusiveZone: 44
            color: Theme.buttonSecondarySolid
            WlrLayershell.namespace: "ohmansy-shine-bar"
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            component BarButton: GlassButton {
                implicitHeight: 32
                padding: 9
                font.pixelSize: 13
                actionRole: "secondary"
            }
            RowLayout {
                anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: 10 }
                spacing: 6
                Text { text: "ohmansy"; color: Theme.text; font.family: Theme.fontFamily; font.pixelSize: 14; font.weight: Font.Medium; Layout.rightMargin: 12 }
                Repeater {
                    model: 4
                    BarButton {
                        required property int index
                        text: String(index + 1)
                        actionRole: bar.output.workspace === index + 1 ? "primary" : "secondary"
                        onClicked: root.request("workspace", bar.modelData.name, index + 1)
                    }
                }
                BarButton { text: "Terminal"; onClicked: root.request("terminal", bar.modelData.name, null) }
            }
            Text {
                anchors.centerIn: parent
                visible: bar.width > 700
                text: "Shine"
                color: Theme.secondary
                font.family: Theme.fontFamily
                font.pixelSize: 13
            }
            Text {
                anchors { right: parent.right; verticalCenter: parent.verticalCenter; rightMargin: 14 }
                text: Qt.formatDateTime(clock.date, "ddd d MMM  HH:mm")
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: 13
            }
        }
    }
}
