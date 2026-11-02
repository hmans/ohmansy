import QtQuick
import Ohmansy.Ui as Ui

// Shared design tokens. Saving any QML/JS file reloads the running shell.
QtObject {
    readonly property string fontFamily: Ui.Theme.fontFamily
    readonly property int fontSize: 15
    readonly property int searchFontSize: 18
    readonly property int panelWidth: 560
    readonly property int visibleRows: 7
    readonly property int iconSize: 24

    // Match Ghostty's dark surface. Tint only the surface, keeping text opaque.
    // Qt.rgba uses 0–1 components; QML hex alpha comes FIRST (#AARRGGBB).
    readonly property color tint: "#282c34"
    readonly property real glassOpacity: 0.76
    readonly property color background: Qt.rgba(tint.r, tint.g, tint.b, glassOpacity)
    readonly property color notificationBackground: Qt.rgba(tint.r, tint.g, tint.b, 0.28)
    readonly property color notificationBorder: Qt.rgba(224 / 255, 222 / 255, 244 / 255, 0.38)
    readonly property color text: Ui.Theme.text
    readonly property color secondary: Ui.Theme.secondary
    readonly property color muted: "#908caa"
    readonly property color accent: "#c4a7e7"
    readonly property color border: Qt.rgba(224 / 255, 222 / 255, 244 / 255, 0.16)
    readonly property color selection: "#1ac4a7e7"
    readonly property color hover: "#08e0def4"
    readonly property int radius: Ui.Theme.radius
    readonly property int rowHeight: 42
    readonly property int barHeight: 38
    readonly property int barFontSize: 14
    readonly property int barFontWeight: Font.Medium
    readonly property color barBackground: "transparent"
    readonly property real traySaturation: -1
    readonly property int notificationWidth: 420
    readonly property int notificationGap: 12
    readonly property int notificationEdgeGap: 24
    readonly property int notificationShadowPadding: 24
    readonly property color notificationShadow: "#30000000"
    readonly property int edgeGap: 12
    readonly property int notificationTitleSize: 16
    readonly property int notificationBodySize: 15
}
