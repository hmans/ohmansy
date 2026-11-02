import QtQuick
import Ohmansy.Welcome

RibbonScene {
    id: scene
    property bool moving: true
    property double lastTick: 0
    readonly property var renderStats: ({ fps: moving ? framesPerSecond : 0, frameTime: frameTime })
    onMovingChanged: lastTick = 0
    Timer {
        // Keep the launcher's 30 fps pacing, but advance motion at 60% speed.
        interval: 33
        repeat: true
        running: scene.moving && scene.visible && !scene.failed
        onTriggered: {
            const now = Date.now();
            if (scene.lastTick) scene.elapsed += Math.min((now - scene.lastTick) / 1000, 0.1) * 0.6;
            scene.lastTick = now;
        }
    }
}
