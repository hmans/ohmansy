import QtQuick
import Ohmansy.Welcome

RibbonScene {
    id: scene
    property bool moving: true
    property real motionSpeed: 0.6
    property int frameInterval: 33
    // Default stays dark for the greeter. Desktop supplies the appearance blend.
    property real targetLightMix: 0
    Component.onCompleted: lightMix = targetLightMix
    property double lastTick: 0
    readonly property var renderStats: ({ fps: moving ? framesPerSecond : 0, frameTime: frameTime })
    onMovingChanged: lastTick = 0
    Timer {
        // Consumers can reduce render cadence independently from motion speed.
        interval: scene.frameInterval
        repeat: true
        running: (scene.moving || scene.lightMix !== scene.targetLightMix) && scene.visible && !scene.failed
        onTriggered: {
            const now = Date.now();
            if (scene.moving && scene.lastTick) scene.elapsed += Math.min((now - scene.lastTick) / 1000, 0.1) * scene.motionSpeed;
            // Sample the blend with motion so a theme fade does not double render cadence.
            scene.lightMix = scene.targetLightMix;
            scene.lastTick = now;
        }
    }
}
