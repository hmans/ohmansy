import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.SystemTray
import Quickshell.Networking
import "Niri.js" as Niri

PanelWindow {
    id: bar
    required property var niriState
    required property var audio
    required property var appearance
    required property var displays
    property bool launcherActive: false
    property string launcherMode: "apps"
    signal launcherRequested()
    signal launcherDismissed()
    signal displayRequested()
    Launcher {
        barWindow: bar
        opened: bar.launcherActive && bar.launcherMode !== "shortcuts" && bar.launcherMode !== "displays"
        requestedMode: bar.launcherMode
        niriState: bar.niriState
        onDismissed: bar.launcherDismissed()
        onDisplayRequested: bar.displayRequested()
    }
    ShortcutPanel {
        barWindow: bar
        opened: bar.launcherActive && bar.launcherMode === "shortcuts"
        onDismissed: bar.launcherDismissed()
    }
    DisplayPanel {
        barWindow: bar
        controller: bar.displays
        opened: bar.launcherActive && bar.launcherMode === "displays"
        onDismissed: bar.launcherDismissed()
    }
    readonly property string installerCommand: Quickshell.env("OHMANSY_INSTALLER") || ""
    readonly property var networkDevices: Networking.devices.values
    readonly property bool online: networkDevices.some(device => device.connected)
    readonly property var wifi: networkDevices.find(device => device.type === DeviceType.Wifi && device.connected)
    readonly property string networkText: wifi ? (wifi.networks.values.find(network => network.connected) || {}).name || "Wi-Fi" : online ? "" : "Offline"
    readonly property string windowTitle: Niri.titleFor(niriState.state, screen ? screen.name : "")
    Theme { id: theme; onWallpaper: true }
    component BarButton: QuietButton {
        onWallpaper: true
        font.weight: theme.barFontWeight
        hoverHighlight: true
        tooltipsEnabled: false
    }
    component BarIcon: Button {
        implicitWidth: 28
        implicitHeight: 28
        padding: 5
        display: AbstractButton.IconOnly
        icon.width: 18
        icon.height: 18
        icon.color: enabled ? theme.text : theme.muted
        hoverEnabled: true
        background: Rectangle {
            radius: 6
            color: parent.down || parent.visualFocus ? theme.selection
                : parent.hovered ? theme.hover : "transparent"
        }
        HoverHandler { cursorShape: parent.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor }
    }
    SystemClock { id: clock; precision: SystemClock.Minutes }
    anchors { top: true; left: true; right: true }
    implicitHeight: theme.barHeight
    exclusiveZone: theme.barHeight
    color: "transparent"
    WlrLayershell.namespace: "ohmansy-bar"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    Item {
        anchors.fill: parent
        RowLayout {
            anchors { left: parent.left; top: parent.top; bottom: parent.bottom; leftMargin: 12 }
            width: Math.max(0, bar.width / 2 - dateButton.width / 2 - 36)
            spacing: 8
            BarButton {
                text: "ohmansy"
                onClicked: bar.launcherRequested()
            }
            BarButton {
                visible: bar.installerCommand !== ""
                text: "Install ohmansy"
                onClicked: Quickshell.execDetached([bar.installerCommand])
            }
            Row {
                spacing: 3
                Repeater {
                    model: Niri.workspacesFor(bar.niriState.state, bar.screen ? bar.screen.name : "")
                    BarButton {
                        required property var modelData
                        text: String(modelData.idx)
                        selected: modelData.is_active
                        hint: modelData.name || "Workspace " + modelData.idx
                        implicitWidth: 26
                        onClicked: bar.niriState.focusWorkspace(modelData.id)
                    }
                }
            }
            BarButton {
                Layout.fillWidth: true
                text: Niri.shortTitle(bar.windowTitle)
                background: Item {}
                contentItem: Text {
                    text: Niri.shortTitle(bar.windowTitle)
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    verticalAlignment: Text.AlignVCenter
                    color: theme.secondary
                    font { family: theme.fontFamily; pixelSize: theme.barFontSize; weight: theme.barFontWeight }
                }
                onClicked: Quickshell.execDetached([bar.niriState.command, "msg", "action", "toggle-overview"])
            }
        }
        BarButton {
            id: dateButton
            anchors.centerIn: parent
            text: Qt.formatDateTime(clock.date, "ddd dd MMM  HH:mm")
        }
        RowLayout {
            anchors { right: parent.right; top: parent.top; bottom: parent.bottom; rightMargin: 12 }
            spacing: 6
            BarButton {
                visible: bar.networkText !== ""
                text: bar.networkText
                onClicked: Quickshell.execDetached([
                    Quickshell.env("OHMANSY_TERMINAL") || "ohmansy-terminal",
                    Quickshell.env("OHMANSY_NMTUI") || "nmtui"
                ])
            }
            BarIcon {
                id: appearanceButton
                readonly property bool dark: bar.appearance.effectivePreference === "prefer-dark"
                icon.name: dark ? "weather-clear-night-symbolic" : "weather-clear-symbolic"
                text: dark ? "Switch to light mode" : "Switch to dark mode"
                Accessible.name: text
                Accessible.description: bar.appearance.error
                enabled: !bar.appearance.busy
                onClicked: bar.appearance.select(dark ? "prefer-light" : "prefer-dark")
            }
            BarIcon {
                id: volume
                icon.name: !bar.audio.available || bar.audio.muted ? "audio-volume-muted-symbolic"
                    : bar.audio.volume > 0.66 ? "audio-volume-high-symbolic"
                    : bar.audio.volume > 0.01 ? "audio-volume-low-symbolic" : "audio-volume-muted-symbolic"
                text: !bar.audio.available ? "No audio output" : bar.audio.muted ? "Unmute" : "Mute"
                Accessible.name: text
                enabled: bar.audio.available
                onClicked: bar.audio.toggleMute()
                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.RightButton
                    cursorShape: Qt.PointingHandCursor
                    onClicked: bar.audio.toggleMute()
                    onWheel: wheel => { if (wheel.angleDelta.y !== 0) bar.audio.adjust(wheel.angleDelta.y > 0 ? 0.03 : -0.03); }
                }
            }
            Slider {
                id: volumeSlider
                Layout.preferredWidth: 72
                implicitHeight: 28
                from: 0; to: 1; stepSize: 0.01
                value: bar.audio.volume
                enabled: bar.audio.available
                wheelEnabled: true
                Accessible.name: "Output volume"
                onMoved: bar.audio.setVolume(value)
                HoverHandler { cursorShape: parent.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor }
                background: Rectangle {
                    x: volumeSlider.leftPadding
                    y: (volumeSlider.height - height) / 2
                    width: volumeSlider.availableWidth
                    height: 3; radius: 1.5
                    color: theme.border
                    Rectangle {
                        width: volumeSlider.visualPosition * parent.width
                        height: parent.height; radius: 1.5
                        color: bar.audio.muted ? theme.muted : theme.secondary
                    }
                }
                handle: Rectangle {
                    x: volumeSlider.leftPadding + volumeSlider.visualPosition * (volumeSlider.availableWidth - width)
                    y: (volumeSlider.height - height) / 2
                    width: 9; height: 9; radius: 4.5
                    color: bar.audio.muted || !volumeSlider.enabled ? theme.muted : theme.text
                }
            }
            Row {
                spacing: 8
                Repeater {
                    model: SystemTray.items.values.filter(item => item.status !== Status.Passive)
                    Item {
                        id: trayItem
                        required property var modelData
                        width: 20; height: theme.barHeight
                        Image {
                            anchors.centerIn: parent
                            width: 16; height: 16
                            source: trayItem.modelData.icon
                            sourceSize { width: 20; height: 20 }
                            layer.enabled: true
                            layer.effect: MultiEffect { saturation: -1; brightness: 1 - 2 * theme.lightMix }
                        }
                        MouseArea {
                            id: trayMouse
                            anchors.fill: parent
                            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                            cursorShape: Qt.PointingHandCursor
                            hoverEnabled: true
                            onClicked: event => {
                                if (event.button === Qt.MiddleButton) trayItem.modelData.secondaryActivate();
                                else if (event.button === Qt.RightButton || trayItem.modelData.onlyMenu) {
                                    if (trayItem.modelData.hasMenu) {
                                        var point = trayItem.mapToItem(bar.contentItem, 0, trayItem.height);
                                        trayItem.modelData.display(bar, point.x, point.y);
                                    }
                                } else trayItem.modelData.activate();
                            }
                            onWheel: wheel => trayItem.modelData.scroll(wheel.angleDelta.y, false)
                        }
                    }
                }
            }
        }
    }
}
