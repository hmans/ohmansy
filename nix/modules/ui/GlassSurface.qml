import QtQuick
import QtQuick.Effects

Item {
    id: glass
    property Item backdrop: null
    property ColorPalette colors: null
    property bool highlighted: false
    property bool pressed: false
    property bool focused: false
    property bool primary: false
    property color tint: primary ? Theme.primaryGlass : Theme.glass
    property color fallbackTint: colors ? colors.surfaceBase : Theme.solidSurface
    property bool sheen: true
    property real radius: Theme.radius
    readonly property bool accelerated: GraphicsInfo.api !== GraphicsInfo.Software
    ShaderEffectSource {
        id: sample
        visible: false
        sourceItem: glass.accelerated ? glass.backdrop : null
        sourceRect: {
            if (!glass.backdrop) return Qt.rect(0, 0, glass.width, glass.height);
            // Recalculate when the form scrolls or changes layout.
            const revision = glass.backdrop.layoutRevision || "";
            const origin = glass.mapToItem(glass.backdrop, 0, 0);
            return Qt.rect(origin.x, origin.y, glass.width, glass.height);
        }
        textureSize: Qt.size(Math.max(1, glass.width), Math.max(1, glass.height))
    }
    Rectangle {
        id: mask
        anchors.fill: parent
        radius: glass.radius
        color: "white"
        layer.enabled: glass.accelerated
        visible: false
    }
    MultiEffect {
        anchors.fill: parent
        visible: glass.accelerated && glass.backdrop !== null
        source: sample
        maskEnabled: true
        maskSource: mask
        autoPaddingEnabled: false
    }
    Rectangle {
        anchors.fill: parent
        radius: glass.radius
        color: glass.accelerated
            ? glass.tint : glass.fallbackTint
    }
    Rectangle {
        anchors.fill: parent
        radius: glass.radius
        visible: glass.sheen
        gradient: Gradient {
            GradientStop { position: 0; color: glass.primary ? "#18e6d7ff" : "#0affffff" }
            GradientStop { position: 1; color: "#01ffffff" }
        }
        opacity: glass.pressed ? 0.4 : (glass.highlighted ? 1 : 0.65)
        Behavior on opacity { NumberAnimation { duration: 120 } }
    }
    // A crisp half-point rim catches light without a heavy control outline.
    Rectangle {
        anchors.fill: parent
        radius: glass.radius
        color: "transparent"
        border.width: 0.5
        border.pixelAligned: false
        border.color: glass.colors
            ? (glass.focused ? glass.colors.focusBorder : glass.highlighted ? glass.colors.hoverBorder : glass.colors.border)
            : (glass.focused ? "#32e8e0f3" : glass.highlighted ? "#26e8e0f3" : "#18e8e0f3")
        Behavior on border.color { ColorAnimation { duration: 120 } }
    }
}
