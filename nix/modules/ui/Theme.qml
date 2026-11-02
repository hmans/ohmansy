pragma Singleton
import QtQuick

QtObject {
    readonly property string fontFamily: "Inter"
    readonly property color text: "#f5f3fa"
    readonly property color secondary: "#c8c4d6"
    readonly property color glass: "#483e4354"
    readonly property color primaryGlass: "#725f467f"
    readonly property color solidSurface: "#ed30333f"
    readonly property int radius: 14
    readonly property url chevron: Qt.resolvedUrl("icons/chevron.svg")
}
