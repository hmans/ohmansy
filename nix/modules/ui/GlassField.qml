import QtQuick
import QtQuick.Controls

TextField {
    id: control
    property Item backdrop: null
    property ColorPalette colors: null
    implicitHeight: 64
    leftPadding: 22
    rightPadding: 22
    font.family: Theme.fontFamily
    font.pixelSize: 19
    font.weight: Font.Medium
    renderType: TextInput.QtRendering
    color: colors ? colors.text : Theme.text
    placeholderTextColor: colors ? colors.secondary : "#b9b6c8"
    selectionColor: colors ? colors.textSelection : "#645373"
    selectedTextColor: colors ? colors.selectedText : "#ffffff"
    selectByMouse: true
    background: GlassSurface {
        backdrop: control.backdrop
        colors: control.colors
        tint: control.colors ? control.colors.control : Theme.glass
        sheen: !control.colors
        focused: control.activeFocus
        highlighted: control.hovered
    }
}
