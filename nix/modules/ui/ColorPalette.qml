import QtQuick

// Semantic desktop colors. Alpha belongs to surfaces, never their content.
QtObject {
    property bool dark: Qt.styleHints.colorScheme === Qt.ColorScheme.Dark
    readonly property real surfaceOpacity: 0.85
    readonly property color surfaceBase: dark ? "#202020" : "#ffffff"
    readonly property color surface: Qt.rgba(surfaceBase.r, surfaceBase.g, surfaceBase.b, surfaceOpacity)
    readonly property color text: dark ? "#f5f5f5" : "#202024"
    readonly property color secondary: dark ? "#c6c6cc" : "#50505a"
    readonly property color muted: dark ? "#aaaab4" : "#62626e"
    readonly property color accent: dark ? "#c4a7e7" : "#68478d"
    readonly property color control: dark ? "#0fffffff" : "#08000000"
    readonly property color hover: dark ? "#14ffffff" : "#0c000000"
    readonly property color selection: dark ? "#386f6187" : "#2468478d"
    readonly property color border: dark ? "#24ffffff" : "#20000000"
    readonly property color hoverBorder: dark ? "#30ffffff" : "#2c000000"
    readonly property color focusBorder: dark ? "#48ffffff" : "#40000000"
    readonly property color textSelection: dark ? "#72548d" : "#795a96"
    readonly property color selectedText: "#ffffff"
}
