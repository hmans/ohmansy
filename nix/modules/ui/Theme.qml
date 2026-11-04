pragma Singleton
import QtQuick

QtObject {
    readonly property string fontFamily: "Inter"
    readonly property color text: "#f5f3fa"
    readonly property color secondary: "#c8c4d6"
    readonly property color glass: "#483e4354"
    readonly property color primaryGlass: "#725f467f"
    readonly property color solidSurface: "#ed30333f"
    readonly property color buttonPrimary: primaryGlass
    readonly property color buttonPrimarySolid: "#51405f"
    readonly property color buttonPrimaryText: text
    readonly property color buttonSecondary: glass
    readonly property color buttonSecondarySolid: "#30333f"
    readonly property color buttonSecondaryText: "#f5f3fa"
    readonly property color buttonReturn: "#283e4354"
    readonly property color buttonReturnSolid: "#252835"
    readonly property color buttonReturnText: secondary
    readonly property int radius: 14
    readonly property url chevron: Qt.resolvedUrl("icons/chevron.svg")
}
