//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma UseQApplication
//@ pragma IconTheme Adwaita
//@ pragma DefaultEnv QT_QPA_PLATFORMTHEME=xdgdesktopportal
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Ohmansy.Ui
import Ohmansy.Displays as Displays
import Ohmansy.Launcher as Launcher
import Ohmansy.Notifications as Notifications
import Ohmansy.Desktop as Desktop

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
    Desktop.AudioState { id: audio }
    Desktop.AppearanceState { id: appearance }
    ColorPalette { id: barColors; dark: appearance.effectivePreference === "prefer-dark" }
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
                    appearance.select(command);
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
                id: workspaceButton
                implicitHeight: 32
                padding: 9
                font.pixelSize: 13
                font.weight: Font.DemiBold
                actionRole: "secondary"
                contentItem: Text {
                    text: workspaceButton.text
                    font: workspaceButton.font
                    color: barColors.text
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    opacity: workspaceButton.dimmed ? 0.45 : 1
                }
                Accessible.name: "Workspace " + text
                Accessible.description: actionRole === "primary" ? "Current workspace" : "Switch to workspace"
                background: FrameSurface {
                    frameSettings: root.state.preferences?.decorations?.frame || ({})
                    animationsEnabled: root.state.preferences?.animations?.enabled !== false
                    active: workspaceButton.actionRole === "primary"
                    highlighted: workspaceButton.hovered
                    pressed: workspaceButton.down
                    focused: workspaceButton.visualFocus
                    Rectangle {
                        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 3 }
                        width: 7; height: 2; radius: 1
                        color: barColors.text
                        opacity: parent.activeAmount * 0.65
                    }
                }
            }
            component BarIcon: Button {
                implicitWidth: 30
                implicitHeight: 32
                padding: 6
                display: AbstractButton.IconOnly
                icon { width: 18; height: 18; color: barColors.text }
                hoverEnabled: true
                Accessible.name: text
                ToolTip.visible: hovered
                ToolTip.delay: 600
                ToolTip.text: text
                HoverHandler { cursorShape: parent.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor }
                background: Rectangle {
                    radius: Theme.radius
                    color: parent.checked || parent.down ? barColors.selection
                        : parent.hovered || parent.visualFocus ? barColors.hover : "transparent"
                    border.width: parent.visualFocus ? 1 : 0
                    border.color: barColors.focusBorder
                }
            }
            RowLayout {
                anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: 10 }
                spacing: 6
                Button {
                    text: "ohmansy"
                    implicitHeight: 32
                    padding: 9
                    background: Item {}
                    contentItem: Text {
                        text: parent.text
                        color: barColors.text
                        font { family: Theme.fontFamily; pixelSize: 13; weight: Font.DemiBold }
                        verticalAlignment: Text.AlignVCenter
                    }
                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                    onClicked: root.launcherScreen = root.launcherScreen ? "" : bar.modelData.name
                }
                Repeater {
                    model: root.state.workspaces || [
                        { name: "1" }, { name: "2" }, { name: "3" }, { name: "4" }
                    ]
                    BarButton {
                        required property int index
                        required property var modelData
                        text: modelData.name
                        actionRole: bar.output.workspace === index + 1 ? "primary" : "secondary"
                        onClicked: root.request("workspace", bar.modelData.name, index + 1)
                    }
                }
            }
            Text {
                anchors.centerIn: parent
                visible: bar.width > 700
                text: "Shine"
                color: barColors.secondary
                font.family: Theme.fontFamily
                font.pixelSize: 13
                font.weight: Font.DemiBold
            }
            RowLayout {
                anchors { right: parent.right; verticalCenter: parent.verticalCenter; rightMargin: 14 }
                spacing: 6
                BarIcon {
                    text: notifications.doNotDisturb ? "Notifications · Do Not Disturb" : "Notifications"
                    icon.name: "preferences-system-notifications-symbolic"
                    checkable: true
                    checked: notifications.historyOutput === bar.modelData.name
                    onClicked: notifications.historyOutput = notifications.historyOutput ? "" : bar.modelData.name
                }
                BarIcon {
                    text: "Light mode"
                    icon.name: "weather-clear-symbolic"
                    Accessible.description: appearance.error
                    checkable: true
                    checked: appearance.effectivePreference === "prefer-light"
                    enabled: !appearance.busy
                    onClicked: appearance.select("prefer-light")
                }
                BarIcon {
                    text: "Dark mode"
                    icon.name: "weather-clear-night-symbolic"
                    Accessible.description: appearance.error
                    checkable: true
                    checked: appearance.effectivePreference === "prefer-dark"
                    enabled: !appearance.busy
                    onClicked: appearance.select("prefer-dark")
                }
                BarIcon {
                    text: !audio.available ? "No audio output" : audio.muted ? "Unmute" : "Mute"
                    icon.name: !audio.available || audio.muted || audio.volume <= 0.01
                        ? "audio-volume-muted-symbolic" : audio.volume > 0.66
                        ? "audio-volume-high-symbolic" : "audio-volume-low-symbolic"
                    enabled: audio.available
                    onClicked: audio.toggleMute()
                }
                Slider {
                    id: volumeSlider
                    Layout.preferredWidth: 80
                    implicitHeight: 32
                    from: 0; to: 1; stepSize: 0.01
                    value: audio.volume
                    enabled: audio.available
                    wheelEnabled: true
                    Accessible.name: "Output volume"
                    onMoved: audio.setVolume(value)
                    background: Rectangle {
                        x: volumeSlider.leftPadding
                        y: (volumeSlider.height - height) / 2
                        width: volumeSlider.availableWidth
                        height: 3; radius: 1.5
                        color: barColors.border
                        Rectangle {
                            width: volumeSlider.visualPosition * parent.width
                            height: parent.height; radius: 1.5
                            color: audio.muted ? barColors.muted : barColors.text
                        }
                    }
                    handle: Rectangle {
                        x: volumeSlider.leftPadding + volumeSlider.visualPosition * (volumeSlider.availableWidth - width)
                        y: (volumeSlider.height - height) / 2
                        width: 9; height: 9; radius: 4.5
                        color: barColors.text
                        opacity: volumeSlider.enabled ? 1 : 0.4
                    }
                }
                Text {
                    text: Qt.formatDateTime(clock.date, "ddd d MMM  HH:mm")
                    color: barColors.text
                    font.family: Theme.fontFamily
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                    Layout.leftMargin: 8
                }
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
