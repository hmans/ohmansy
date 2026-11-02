import QtQuick
import QtQuick.Controls

Button {
    id: control
    property bool primary: false
    implicitHeight: 44
    padding: 12
    font.family: "IBM Plex Sans"
    font.pixelSize: 15
    hoverEnabled: true
    contentItem: Text {
        text: control.text
        font: control.font
        color: control.primary ? "#20232c" : "#e0def4"
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        opacity: control.enabled ? 1 : 0.45
    }
    background: Rectangle {
        radius: 9
        color: control.primary ? (control.down ? "#ab8ece" : "#c4a7e7") :
            (control.hovered || control.down ? "#353844" : "#252832")
        opacity: control.enabled ? 1 : 0.55
        border.width: control.visualFocus ? 2 : 1
        border.color: control.visualFocus ? "#e0def4" : "#484552"
    }
}
