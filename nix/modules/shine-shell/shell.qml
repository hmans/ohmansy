//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma UseQApplication
//@ pragma IconTheme Adwaita
//@ pragma DefaultEnv QT_QPA_PLATFORMTHEME=xdgdesktopportal
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import Ohmansy.Ui
import Ohmansy.Displays as Displays
import Ohmansy.Launcher as Launcher
import Ohmansy.Notifications as Notifications

ShellRoot {
    id: root
    property var state: ({ outputs: [] })
    property var requests: []
    property string screenshotMessage: ""
    property string screenshotTitle: ""
    property double screenshotResult: 0
    property string screenshotOutput: ""
    property bool displaysOpen: false
    property string launcherScreen: ""
    Notifications.NotificationService {
        id: notifications
        focusedOutput: (root.state.outputs.find(output => output.focused) || root.state.outputs[0] || {}).name || Quickshell.screens[0]?.name || ""
    }
    function toggleLauncher() {
        const output = state.outputs.find(output => output.focused) || state.outputs[0];
        launcherScreen = launcherScreen ? "" : (output ? output.name : Quickshell.screens[0].name);
    }
    IpcHandler {
        target: "launcher"
        function toggle(): void { root.toggleLauncher(); }
        function close(): void { root.launcherScreen = ""; }
        function status(): string {
            const item = launchers.instances.find(item => item.opened);
            return item ? item.status() : JSON.stringify({ opened: false });
        }
    }
    Variants {
        id: launchers
        model: Quickshell.screens
        Launcher.CommandLauncher {
            required property var modelData
            screen: modelData
            opened: root.launcherScreen === modelData.name
            onDismissed: root.launcherScreen = ""
            onCommandRequested: command => {
                if (command === "displays") { root.displaysOpen = true; displayState.refresh(); }
                else if (command === "notifications") notifications.historyOutput = modelData.name;
                else if (command === "terminal") root.request("terminal", modelData.name, null);
                else if (command === "prefer-dark" || command === "prefer-light")
                    Quickshell.execDetached([Quickshell.env("OHMANSY_APPEARANCE"), command]);
            }
        }
    }
    Displays.DisplayState { id: displayState }
    FloatingWindow {
        visible: root.displaysOpen
        title: "ohmansy displays"
        implicitWidth: 600
        implicitHeight: 610
        color: displayColors.surfaceBase
        ColorPalette { id: displayColors; dark: Qt.styleHints.colorScheme === Qt.ColorScheme.Dark }
        onClosed: root.displaysOpen = false
        Displays.DisplayView {
            anchors { fill: parent; margins: 20 }
            controller: displayState
            maximumScale: 2
        }
    }
    onStateChanged: {
        const shot = state.screenshot;
        if (shot && shot.id !== screenshotResult) {
            screenshotResult = shot.id;
            screenshotOutput = shot.output;
            screenshotTitle = shot.error ? "Screenshot failed" : "Screenshot saved";
            screenshotMessage = shot.error ? shot.error
                : shot.path + (shot.clipboard ? "\nCopied to clipboard" : "\nClipboard copy failed")
                    + (shot.annotation_error ? "\nCould not open Satty" : "");
            screenshotTimer.restart();
        }
    }
    Timer { id: screenshotTimer; interval: 8000; onTriggered: root.screenshotMessage = "" }
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
        WallpaperWindow {
            required property var modelData
            screen: modelData
        }
    }
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
            color: "transparent"
            WlrLayershell.namespace: "ohmansy-shine-bar"
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            component BarButton: GlassButton {
                implicitHeight: 32
                padding: 9
                font.pixelSize: 13
                font.weight: Font.DemiBold
                actionRole: "secondary"
            }
            RowLayout {
                anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: 10 }
                spacing: 6
                BarButton { text: "ohmansy"; onClicked: root.launcherScreen = root.launcherScreen ? "" : bar.modelData.name }
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
                BarButton {
                    text: "Displays"
                    onClicked: { root.displaysOpen = true; displayState.refresh(); }
                }
                BarButton {
                    text: notifications.doNotDisturb ? "Notifications · paused" : "Notifications"
                    onClicked: notifications.historyOutput = notifications.historyOutput ? "" : bar.modelData.name
                }
            }
            Text {
                anchors.centerIn: parent
                visible: bar.width > 700
                text: "Shine"
                color: Theme.secondary
                font.family: Theme.fontFamily
                font.pixelSize: 13
                font.weight: Font.DemiBold
            }
            Text {
                anchors { right: parent.right; verticalCenter: parent.verticalCenter; rightMargin: 14 }
                text: Qt.formatDateTime(clock.date, "ddd d MMM  HH:mm")
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: 13
                font.weight: Font.DemiBold
            }
        }
    }
    Variants {
        model: Quickshell.screens
        PanelWindow {
            id: screenshotToast
            required property var modelData
            readonly property bool showMessage: root.screenshotMessage !== "" && modelData.name ===
                root.screenshotOutput
            // Keep the layer role alive: Smithay 0.7 validates a trailing
            // null-buffer commit against the destroyed role's reset size.
            // Hidden feedback is transparent and has an empty input region.
            screen: modelData
            mask: Region { item: screenshotToast.showMessage ? screenshotBackground : null }
            anchors { bottom: true; right: true }
            margins { bottom: 16; right: 16 }
            implicitWidth: Math.min(460, modelData.width - 32)
            implicitHeight: Math.max(160, screenshotContent.implicitHeight + 32)
            exclusiveZone: 0
            color: "transparent"
            WlrLayershell.namespace: "ohmansy-screenshot-result"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            Item {
                id: screenshotBackground
                anchors.fill: parent
                visible: screenshotToast.showMessage
                GlassSurface { anchors.fill: parent; tint: Theme.solidSurface }
                ColumnLayout {
                    id: screenshotContent
                    anchors { fill: parent; margins: 16 }
                    spacing: 8
                    Text {
                        text: root.screenshotTitle
                        color: Theme.text
                        font.family: Theme.fontFamily
                        font.pixelSize: 15
                        font.weight: Font.Medium
                    }
                    Text {
                        Layout.fillWidth: true
                        text: root.screenshotMessage
                        color: Theme.secondary
                        font.family: Theme.fontFamily
                        font.pixelSize: 13
                        wrapMode: Text.WrapAnywhere
                    }
                    GlassButton {
                        text: "Dismiss"
                        actionRole: "secondary"
                        onClicked: { screenshotTimer.stop(); root.screenshotMessage = ""; }
                    }
                }
            }
        }
    }
}
