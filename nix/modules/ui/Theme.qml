pragma Singleton
import QtQuick

QtObject {
    readonly property string fontFamily: "Inter"
    readonly property color text: DesktopPalette.color(DesktopPalette.materials.text)
    readonly property color secondary: DesktopPalette.color(DesktopPalette.materials.muted_text)
    readonly property color glass: DesktopPalette.color(DesktopPalette.materials.surface, 0.45)
    readonly property color primaryGlass: DesktopPalette.frameTint(0.55)
    // Shared with Shine's default frame material; live frame settings may override.
    readonly property color frameActive: DesktopPalette.frameTint(0.55)
    readonly property color frameInactive: DesktopPalette.inactiveTint(0.40)
    readonly property color themeCardActive: DesktopPalette.frameTint(0.96)
    readonly property color themeCardInactive: DesktopPalette.inactiveTint(0.96)
    readonly property color solidSurface: DesktopPalette.color(DesktopPalette.materials.surface, 0.93)
    readonly property color buttonPrimary: primaryGlass
    readonly property color buttonPrimarySolid: DesktopPalette.frameTint(1)
    readonly property color buttonPrimaryText: text
    readonly property color buttonSecondary: glass
    readonly property color buttonSecondarySolid: DesktopPalette.color(DesktopPalette.materials.surface)
    readonly property color buttonSecondaryText: text
    readonly property color buttonReturn: DesktopPalette.inactiveTint(0.16)
    readonly property color buttonReturnSolid: DesktopPalette.inactiveTint(1)
    readonly property color buttonReturnText: secondary
    readonly property int radius: 14
    readonly property url chevron: Qt.resolvedUrl("icons/chevron.svg")
}
