import QtQuick
import QtQuick.Controls

Button {
    id: control
    required property string symbol
    implicitWidth: 48
    implicitHeight: 48
    padding: 12
    hoverEnabled: true
    HoverHandler {
        enabled: control.enabled
        cursorShape: Qt.PointingHandCursor
    }
    Accessible.name: text
    ToolTip.visible: hovered
    ToolTip.delay: 600
    ToolTip.text: text
    contentItem: Image {
        source: "icons/" + control.symbol + ".svg"
        sourceSize: Qt.size(48, 48)
        fillMode: Image.PreserveAspectFit
        opacity: control.down ? 0.55 : (control.hovered || control.visualFocus ? 1 : 0.72)
        Behavior on opacity { NumberAnimation { duration: 120 } }
    }
    background: Rectangle {
        radius: 14
        color: control.hovered || control.visualFocus ? "#16ffffff" : "transparent"
        border.width: control.visualFocus ? 1 : 0
        border.color: "#32e8e0f3"
    }
}
