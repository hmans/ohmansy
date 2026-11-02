import QtQuick

// Shared entrance timeline for any number of items via opacityAt(delay).
Item {
    id: entrance
    property bool animated: true
    property real elapsed: animated ? 0 : 1000
    function opacityAt(delay) {
        const progress = Math.max(0, Math.min(1, (elapsed - delay) / 520));
        return 1 - Math.pow(1 - progress, 5);
    }
    NumberAnimation on elapsed {
        from: 0
        to: 1000
        duration: 1000
        running: entrance.animated
    }
}
