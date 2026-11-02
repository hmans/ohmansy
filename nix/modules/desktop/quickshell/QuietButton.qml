import QtQuick
import QtQuick.Controls

Button {
    id: root
    property bool selected: false
    property string hint: ""
    property bool hoverHighlight: true
    property bool tooltipsEnabled: true
    property bool prominent: false
    property bool onWallpaper: false
    Theme { id: theme; onWallpaper: root.onWallpaper }
    implicitHeight: prominent ? 32 : 28
    implicitWidth: prominent ? 32 : label.implicitWidth + 18
    padding: prominent ? 0 : 8
    hoverEnabled: true
    focusPolicy: Qt.StrongFocus
    contentItem: Text {
        id: label
        text: root.text
        textFormat: Text.PlainText
        font.family: theme.fontFamily
        font.pixelSize: root.prominent ? 22 : theme.barFontSize
        font.weight: root.prominent ? Font.Bold : root.font.weight
        color: root.prominent || root.selected ? theme.text : theme.secondary
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
        renderType: Text.QtRendering
    }
    background: Rectangle {
        radius: root.prominent ? 8 : 6
        color: root.down || root.selected || root.visualFocus ? theme.selection
            : root.hovered && root.hoverHighlight ? theme.hover : "transparent"
        Behavior on color { ColorAnimation { duration: 120 } }
    }
    HoverHandler { cursorShape: Qt.PointingHandCursor }
    ToolTip.visible: root.tooltipsEnabled && hovered && hint !== ""
    ToolTip.text: hint
    ToolTip.delay: 600
}
