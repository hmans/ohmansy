import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland

PopupWindow {
    id: popup
    required property var audio
    required property var popupState
    Theme { id: theme }
    visible: popupState.audioOpen
    grabFocus: true
    color: "transparent"
    implicitWidth: 320
    implicitHeight: surface.implicitHeight
    onClosed: popupState.audioOpen = false
    onVisibleChanged: if (visible) Qt.callLater(() => volumeSlider.forceActiveFocus())
    function toggle(): void { popupState.audioOpen = !popupState.audioOpen; }
    function close(): void { popupState.audioOpen = false; }

    Glass {
        id: surface
        anchors.fill: parent
        implicitHeight: content.implicitHeight + 28
        focus: true
        Keys.onEscapePressed: popup.close()
        ColumnLayout {
            id: content
            anchors { fill: parent; margins: 14 }
            spacing: 12
            RowLayout {
                Layout.fillWidth: true
                Text {
                    Layout.fillWidth: true
                    text: "Sound"
                    color: theme.text
                    font { family: theme.fontFamily; pixelSize: 15; weight: Font.DemiBold }
                }
                QuietButton {
                    objectName: "audio-mute"
                    text: popup.audio.muted ? "Unmute" : "Mute"
                    selected: popup.audio.muted
                    enabled: popup.audio.available
                    onClicked: popup.audio.toggleMute()
                }
                QuietButton { text: "×"; implicitWidth: 24; onClicked: popup.close() }
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 12
                Text {
                    text: popup.audio.available ? Math.round(popup.audio.volume * 100) + "%" : "—"
                    color: popup.audio.muted ? theme.muted : theme.text
                    font { family: theme.fontFamily; pixelSize: 28; weight: Font.DemiBold }
                }
                Text {
                    Layout.fillWidth: true
                    text: popup.audio.muted ? "Muted" : popup.audio.label(popup.audio.sink)
                    textFormat: Text.PlainText
                    color: theme.secondary
                    font { family: theme.fontFamily; pixelSize: 13 }
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                }
            }
            Slider {
                id: volumeSlider
                objectName: "audio-volume"
                Layout.fillWidth: true
                from: 0; to: 1; stepSize: 0.01
                value: popup.audio.volume
                enabled: popup.audio.available
                wheelEnabled: true
                implicitHeight: 28
                Accessible.name: "Output volume"
                onMoved: popup.audio.setVolume(value)
                HoverHandler { cursorShape: Qt.PointingHandCursor }
                background: Rectangle {
                    x: volumeSlider.leftPadding
                    y: volumeSlider.topPadding + (volumeSlider.availableHeight - height) / 2
                    width: volumeSlider.availableWidth
                    height: 4
                    radius: 2
                    color: theme.border
                    Rectangle {
                        width: volumeSlider.visualPosition * parent.width
                        height: parent.height
                        radius: 2
                        color: popup.audio.muted ? theme.muted : theme.accent
                    }
                }
                handle: Rectangle {
                    x: volumeSlider.leftPadding + volumeSlider.visualPosition * (volumeSlider.availableWidth - width)
                    y: volumeSlider.topPadding + (volumeSlider.availableHeight - height) / 2
                    width: 14; height: 14; radius: 7
                    color: popup.audio.muted ? theme.secondary : theme.text
                    border { width: 2; color: volumeSlider.activeFocus ? theme.accent : theme.tint }
                }
            }
            Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: theme.hover }
            Text {
                text: "OUTPUT"
                color: theme.muted
                font { family: theme.fontFamily; pixelSize: 10; weight: Font.DemiBold; letterSpacing: 1.2 }
            }
            ListView {
                id: devices
                Layout.fillWidth: true
                implicitHeight: Math.min(5, Math.max(1, count)) * 40
                model: popup.audio.outputs
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                delegate: QuietButton {
                    id: device
                    required property var modelData
                    required property int index
                    objectName: "audio-output-" + index
                    width: devices.width
                    height: 40
                    selected: popup.audio.sink === modelData
                    Accessible.name: popup.audio.label(modelData)
                    onClicked: popup.audio.selectOutput(modelData)
                    contentItem: RowLayout {
                        spacing: 12
                        Rectangle {
                            Layout.alignment: Qt.AlignVCenter
                            width: 8; height: 8; radius: 4
                            color: device.selected ? theme.accent : "transparent"
                            border { width: 1; color: device.selected ? theme.accent : theme.border }
                        }
                        Text {
                            Layout.fillWidth: true
                            text: popup.audio.label(device.modelData)
                            textFormat: Text.PlainText
                            color: device.selected ? theme.text : theme.secondary
                            font { family: theme.fontFamily; pixelSize: 13; weight: device.selected ? Font.DemiBold : Font.Normal }
                            elide: Text.ElideRight
                        }
                    }
                }
                Text {
                    anchors.centerIn: parent
                    visible: devices.count === 0
                    text: "No audio outputs connected"
                    color: theme.muted
                    font { family: theme.fontFamily; pixelSize: 13 }
                }
            }
        }
    }
}
