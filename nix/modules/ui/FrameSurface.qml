import QtQuick
import QtQuick.Window

// A compact version of Shine's frame material for workspace tabs. Surface tint
// remains translucent; actual cross-window backdrop blur belongs to the compositor.
Item {
    id: surface
    property var frameSettings: ({})
    property bool active: false
    property bool highlighted: false
    property bool pressed: false
    property bool focused: false
    property bool animationsEnabled: true
    readonly property var bevel: frameSettings.bevel || ({})
    readonly property var glass: frameSettings.glass || ({})
    readonly property real radius: frameSettings.outer_corner_radius ?? 10
    readonly property int duration: animationsEnabled ? (frameSettings.focus_duration_ms ?? 150) : 0
    readonly property int easing: {
        switch (frameSettings.focus_easing) {
        case "linear": return Easing.Linear;
        case "ease-in": return Easing.InCubic;
        case "ease-out": return Easing.OutCubic;
        default: return Easing.InOutCubic;
        }
    }
    property real activeAmount: active ? 1 : 0
    Behavior on activeAmount { NumberAnimation { duration: surface.duration; easing.type: surface.easing } }
    property real interaction: pressed ? -0.035 : highlighted || focused ? 0.035 : 0
    Behavior on interaction { NumberAnimation { duration: surface.animationsEnabled ? 120 : 0 } }
    function rgba(values, fallback) {
        return values && values.length === 4 ? Qt.rgba(values[0], values[1], values[2], values[3]) : fallback;
    }
    readonly property color activeTint: rgba(frameSettings.active_color, Theme.frameActive)
    readonly property color inactiveTint: rgba(frameSettings.inactive_color, Theme.frameInactive)
    readonly property color tint: Qt.rgba(
        inactiveTint.r + (activeTint.r - inactiveTint.r) * activeAmount,
        inactiveTint.g + (activeTint.g - inactiveTint.g) * activeAmount,
        inactiveTint.b + (activeTint.b - inactiveTint.b) * activeAmount,
        inactiveTint.a + (activeTint.a - inactiveTint.a) * activeAmount)
    readonly property bool accelerated: GraphicsInfo.api !== GraphicsInfo.Software
    Loader {
        anchors.fill: parent
        active: surface.accelerated
        sourceComponent: ShaderEffect {
            property vector2d surface_size: Qt.vector2d(width, height)
            property vector4d material_color: Qt.vector4d(surface.tint.r, surface.tint.g, surface.tint.b, surface.tint.a)
            property real radius: surface.radius
            property real density: Screen.devicePixelRatio
            property real noise_strength: surface.glass.enabled === false ? 0 : (surface.glass.noise ?? 0.025)
            property real material_opacity: surface.glass.enabled === false ? 1 : (surface.glass.opacity ?? 0.9)
            property real interaction: surface.interaction
            property vector2d bevel_widths: surface.bevel.enabled === false ? Qt.vector2d(0, 0)
                : Qt.vector2d(surface.bevel.width ?? 1.5, surface.bevel.inner_width ?? 1.0)
            property vector2d bevel_strength: Qt.vector2d(surface.bevel.highlight ?? 0.20, surface.bevel.shadow ?? 0.18)
            property vector2d light_direction: Qt.vector2d(surface.bevel.light_direction?.[0] ?? -1, surface.bevel.light_direction?.[1] ?? -1)
            property real inner_radius: surface.frameSettings.inner_corner_radius ?? 8
            fragmentShader: Qt.resolvedUrl("shaders/frame-surface.frag.qsb")
        }
    }
    Rectangle {
        anchors.fill: parent
        visible: !surface.accelerated
        radius: surface.radius
        color: surface.tint
        border.width: 1
        border.color: surface.focused ? "#70ffffff" : "#22ffffff"
    }
}
