pragma Singleton
import QtQuick
import Quickshell.Io

QtObject {
    id: root
    property real renderScale: 0.75
    property int particleLayers: 2
    property real particleMotionDetail: 1
    property bool moving: true

    function status(): string {
        return JSON.stringify({ renderScale, particleLayers, particleMotionDetail, moving });
    }
    function configure(scale: real, layers: int, motion: real): string {
        if (!Number.isFinite(scale) || scale < 0.25 || scale > 1
            || layers < 0 || layers > 3 || !Number.isFinite(motion) || motion < 0 || motion > 1)
            return JSON.stringify({ error: "Use scale 0.25–1, layers 0–3 and motion detail 0–1." });
        renderScale = scale;
        particleLayers = layers;
        particleMotionDetail = motion;
        return status();
    }
    property QtObject control: IpcHandler {
        target: "wallpaper"
        function status(): string { return root.status(); }
        function configure(scale: real, layers: int, motion: real): string {
            return root.configure(scale, layers, motion);
        }
        function quality(name: string): string {
            if (name === "high") return root.configure(1, 3, 1);
            if (name === "balanced") return root.configure(0.75, 2, 1);
            if (name === "low") return root.configure(0.5, 1, 0);
            return JSON.stringify({ error: "Choose high, balanced or low." });
        }
        function pause(paused: bool): string {
            root.moving = !paused;
            return root.status();
        }
    }
}
