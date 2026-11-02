import QtQuick
import QtQuick.Controls

TextField {
    id: control
    property Item backdrop: null
    implicitHeight: 64
    leftPadding: 22
    rightPadding: 22
    font.family: Theme.fontFamily
    font.pixelSize: 19
    font.weight: Font.Medium
    renderType: TextInput.QtRendering
    color: Theme.text
    placeholderTextColor: "#b9b6c8"
    selectionColor: "#645373"
    selectedTextColor: "#ffffff"
    selectByMouse: true
    background: GlassSurface {
        backdrop: control.backdrop
        focused: control.activeFocus
        highlighted: control.hovered
    }
}
