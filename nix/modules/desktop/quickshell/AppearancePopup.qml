import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland

PopupWindow {
    id: popup
    required property var appearance
    required property var popupState
    Theme { id: theme }
    visible: popupState.appearanceOpen
    grabFocus: true
    color: "transparent"
    implicitWidth: 280
    implicitHeight: content.implicitHeight + 28
    BackgroundEffect.blurRegion: Region { item: surface; radius: surface.radius }
    onClosed: popupState.appearanceOpen = false
    onVisibleChanged: if (visible) Qt.callLater(() => surface.forceActiveFocus())
    Glass {
        id: surface
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: popup.popupState.appearanceOpen = false
        ColumnLayout {
            id: content
            anchors { fill: parent; margins: 14 }
            spacing: 6
            Text {
                text: "Appearance"
                color: theme.text
                font { family: theme.fontFamily; pixelSize: 15; weight: Font.DemiBold }
                Layout.bottomMargin: 6
            }
            Repeater {
                model: [
                    { label: "Light", value: "prefer-light" },
                    { label: "Dark", value: "prefer-dark" }
                ]
                QuietButton {
                    required property var modelData
                    Layout.fillWidth: true
                    implicitHeight: 40
                    text: modelData.label
                    selected: popup.appearance.effectivePreference === modelData.value
                    enabled: !popup.appearance.busy
                    Accessible.name: modelData.label
                    Accessible.checkable: true
                    Accessible.checked: selected
                    onClicked: popup.appearance.select(modelData.value)
                }
            }
            Text {
                Layout.fillWidth: true
                Layout.topMargin: 6
                visible: popup.appearance.error !== ""
                text: popup.appearance.error
                wrapMode: Text.Wrap
                color: theme.secondary
                font { family: theme.fontFamily; pixelSize: 12 }
            }
        }
    }
}
