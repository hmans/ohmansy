pragma Singleton
import QtQuick

QtObject {
    id: root
    // One transition per process, shared by every monitor and bar control.
    readonly property bool dark: Qt.styleHints.colorScheme === Qt.ColorScheme.Dark
    property real lightMix: dark ? 0 : 1
    property bool initialized: false
    Component.onCompleted: initialized = true
    Behavior on lightMix {
        enabled: root.initialized
        NumberAnimation { duration: 800; easing.type: Easing.InOutCubic }
    }
    function mixColor(night: color, day: color): color {
        const t = lightMix;
        return Qt.rgba(night.r + (day.r - night.r) * t,
                       night.g + (day.g - night.g) * t,
                       night.b + (day.b - night.b) * t,
                       night.a + (day.a - night.a) * t);
    }
}
