import QtQuick
import QtQuick.Controls

TextField {
    id: control
    implicitHeight: 48
    leftPadding: 14
    rightPadding: 14
    font.family: "IBM Plex Sans"
    font.pixelSize: 17
    color: "#e0def4"
    placeholderTextColor: "#a5a0b6"
    selectionColor: "#645373"
    selectedTextColor: "#ffffff"
    selectByMouse: true
    background: Rectangle {
        color: "#20232c"
        radius: 9
        border.width: control.activeFocus ? 2 : 1
        border.color: control.activeFocus ? "#c4a7e7" : "#55515f"
    }
}
