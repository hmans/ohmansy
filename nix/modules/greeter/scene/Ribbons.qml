import QtQuick
import Ohmansy.Welcome

RibbonScene {
    id: scene
    property bool moving: true
    // Default stays dark for the greeter. Desktop supplies the appearance blend.
    property real targetLightMix: 0
    Component.onCompleted: lightMix = targetLightMix
    property double lastTick: 0
    readonly property var renderStats: ({ fps: moving ? framesPerSecond : 0, frameTime: frameTime })
    onMovingChanged: lastTick = 0
    Timer {
        // Keep the launcher's 30 fps pacing, but advance motion at 60% speed.
        interval: 33
        repeat: true
        running: (scene.moving || scene.lightMix !== scene.targetLightMix) && scene.visible && !scene.failed
        onTriggered: {
            const now = Date.now();
            if (scene.moving && scene.lastTick) scene.elapsed += Math.min((now - scene.lastTick) / 1000, 0.1) * 0.6;
            // Sample the blend with motion so a theme fade does not double render cadence.
            scene.lightMix = scene.targetLightMix;
            scene.lastTick = now;
        }
    }
}
