import QtQuick
import QtQuick.Controls

Button {
    id: control
    property bool primary: false
    // A transition may block input without changing the button's appearance.
    property bool dimmed: !enabled
    property Item backdrop: null
    implicitHeight: 60
    padding: 18
    font.family: Theme.fontFamily
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
        color: Theme.text
        renderType: Text.QtRendering
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        opacity: control.dimmed ? 0.45 : 1
    }
    background: GlassSurface {
        backdrop: control.backdrop
        primary: control.primary
        highlighted: control.hovered
        pressed: control.down
        focused: control.visualFocus
        opacity: control.dimmed ? 0.55 : 1
    }
}
