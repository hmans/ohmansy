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
    property bool launcherActive: false
    signal launcherRequested()
    signal launcherDismissed()
    Launcher {
        barWindow: bar
        opened: bar.launcherActive
        onDismissed: bar.launcherDismissed()
    }
    property alias audioOpen: saved.audioOpen
    readonly property string installerCommand: Quickshell.env("OHMANSY_INSTALLER") || ""
    readonly property var networkDevices: Networking.devices.values
    readonly property bool online: networkDevices.some(device => device.connected)
    readonly property var wifi: networkDevices.find(device => device.type === DeviceType.Wifi && device.connected)
    readonly property string networkText: wifi ? (wifi.networks.values.find(network => network.connected) || {}).name || "Wi-Fi" : online ? "" : "Offline"
    readonly property string windowTitle: Niri.titleFor(niriState.state, screen ? screen.name : "")
    Theme { id: theme }
    component BarButton: QuietButton {
        font.weight: theme.barFontWeight
        hoverHighlight: true
        tooltipsEnabled: false
    }
    SystemClock { id: clock; precision: SystemClock.Minutes }
    anchors { top: true; left: true; right: true }
    implicitHeight: theme.barHeight
    exclusiveZone: theme.barHeight
    color: "transparent"
    WlrLayershell.namespace: "ohmansy-bar"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    PersistentProperties {
        id: saved
        reloadableId: "bar-state-" + (bar.screen ? bar.screen.name : "")
        property bool audioOpen: false
        property bool appearanceOpen: false
    }
    LazyLoader {
        active: saved.appearanceOpen
        component: AppearancePopup {
            appearance: bar.appearance
            popupState: saved
            anchor.window: bar
            anchor.rect.y: bar.height + theme.edgeGap
            anchor.gravity: Edges.Bottom | Edges.Left
            anchor.onAnchoring: {
                anchor.rect.x = appearanceButton.mapToItem(bar.contentItem, appearanceButton.width, 0).x;
            }
        }
    }
    LazyLoader {
        active: bar.audioOpen
        component: AudioPopup {
            audio: bar.audio
            popupState: saved
            anchor.window: bar
            anchor.rect.y: bar.height + theme.edgeGap
            anchor.gravity: Edges.Bottom | Edges.Left
            anchor.onAnchoring: {
                anchor.rect.x = volume.mapToItem(bar.contentItem, volume.width, 0).x;
            }
        }
    }
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
                text: "Install Ohmansy"
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
                onClicked: Quickshell.execDetached(["niri", "msg", "action", "toggle-overview"])
            }
        }
        BarButton {
            id: dateButton
            anchors.centerIn: parent
            text: Qt.formatDateTime(clock.date, "ddd dd MMM  HH:mm")
            hint: Qt.formatDateTime(clock.date, "dddd, d MMMM yyyy")
            tooltipsEnabled: true
        }
        RowLayout {
            anchors { right: parent.right; top: parent.top; bottom: parent.bottom; rightMargin: 12 }
            spacing: 6
            BarButton {
                visible: bar.networkText !== ""
                text: bar.networkText
                onClicked: Quickshell.execDetached(["foot", "-e", "nmtui"])
            }
            BarButton {
                id: appearanceButton
                text: "Appearance"
                selected: saved.appearanceOpen
                onClicked: {
                    bar.audioOpen = false;
                    saved.appearanceOpen = !saved.appearanceOpen;
                }
            }
            BarButton {
                id: volume
                text: !bar.audio.available ? "Audio" : bar.audio.muted ? "Muted" : "Vol " + Math.round(bar.audio.volume * 100) + "%"
                onClicked: {
                    saved.appearanceOpen = false;
                    bar.audioOpen = !bar.audioOpen;
                }
                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.RightButton
                    cursorShape: Qt.PointingHandCursor
                    onClicked: bar.audio.toggleMute()
                    onWheel: wheel => bar.audio.adjust(wheel.angleDelta.y > 0 ? 0.03 : -0.03)
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
                            layer.effect: MultiEffect { saturation: theme.traySaturation }
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
