import QtQuick
import QtQuick.Controls

Button {
    id: control
    property bool primary: false
    property Item backdrop: null
    implicitHeight: 60
    padding: 18
    font.family: "Inter"
    font.pixelSize: 18
    font.weight: Font.Medium
    hoverEnabled: true
    HoverHandler {
        enabled: control.enabled
        cursorShape: Qt.PointingHandCursor
    }
    contentItem: Text {
        text: control.text
        font: control.font
        color: "#f5f3fa"
        renderType: Text.QtRendering
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        opacity: control.enabled ? 1 : 0.45
    }
    background: GlassSurface {
        backdrop: control.backdrop
        primary: control.primary
        highlighted: control.hovered
        pressed: control.down
        focused: control.visualFocus
        opacity: control.enabled ? 1 : 0.55
    }
}
