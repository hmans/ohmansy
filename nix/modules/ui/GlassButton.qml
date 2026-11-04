import QtQuick
import QtQuick.Controls

Button {
    id: control
    property bool primary: false
    // Keep primary compatible with existing consumers; new code uses actionRole.
    property string actionRole: primary ? "primary" : "secondary"
    readonly property color fillColor: actionRole === "primary" ? Theme.buttonPrimary : actionRole === "return" ? Theme.buttonReturn : Theme.buttonSecondary
    readonly property color solidFillColor: actionRole === "primary" ? Theme.buttonPrimarySolid : actionRole === "return" ? Theme.buttonReturnSolid : Theme.buttonSecondarySolid
    readonly property color labelColor: actionRole === "primary" ? Theme.buttonPrimaryText : actionRole === "return" ? Theme.buttonReturnText : Theme.buttonSecondaryText
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
        color: control.labelColor
        renderType: Text.QtRendering
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        opacity: control.dimmed ? 0.45 : 1
    }
    background: GlassSurface {
        backdrop: control.backdrop
        primary: control.actionRole === "primary"
        tint: control.fillColor
        fallbackTint: control.solidFillColor
        highlighted: control.hovered
        pressed: control.down
        focused: control.visualFocus
        opacity: control.dimmed ? 0.55 : 1
    }
}
