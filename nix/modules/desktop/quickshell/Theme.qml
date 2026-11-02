import QtQuick
import Ohmansy.Ui as Ui

// Shared design tokens. Saving any QML/JS file reloads the running shell.
QtObject {
    readonly property Ui.ColorPalette colors: Ui.ColorPalette {}
    readonly property string fontFamily: Ui.Theme.fontFamily
    readonly property int fontSize: 15
    readonly property int searchFontSize: 18
    readonly property int panelWidth: 560
    readonly property int visibleRows: 7
    readonly property int iconSize: 24

    readonly property color tint: colors.surfaceBase
    readonly property real glassOpacity: colors.surfaceOpacity
    readonly property color background: colors.surface
    readonly property color notificationBackground: colors.surface
    readonly property color notificationBorder: colors.border
    readonly property color text: colors.text
    readonly property color secondary: colors.secondary
    readonly property color muted: colors.muted
    readonly property color accent: colors.accent
    readonly property color border: colors.border
    readonly property color selection: colors.selection
    readonly property color hover: colors.hover
    readonly property int radius: Ui.Theme.radius
    readonly property int rowHeight: 42
    readonly property int barHeight: 38
    readonly property int barFontSize: 14
    readonly property int barFontWeight: Font.Medium
    readonly property color barBackground: "transparent"
    readonly property color shellGlassTint: colors.surface
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
