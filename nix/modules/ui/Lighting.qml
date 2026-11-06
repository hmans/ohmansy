pragma Singleton
import QtQuick

QtObject {
    // Direction is a point on the visible hemisphere: screen x/y, z toward you.
    property var settings: ({})
    readonly property var direction: settings.direction || [-Math.SQRT1_2, -Math.SQRT1_2]
    readonly property real strength: settings.strength ?? 1
    readonly property var highlight: settings.highlight_color || [1, 1, 1]
    readonly property var shadow: settings.shadow_color || [0, 0, 0]
}
