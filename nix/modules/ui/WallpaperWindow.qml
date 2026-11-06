import QtQuick
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: wallpaper
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Background
    WlrLayershell.namespace: "ohmansy-wallpaper"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    mask: Region {}
    color: "#171a21"
    property bool ribbonFailure: false
    readonly property string imageOverride: Quickshell.env("OHMANSY_WALLPAPER_IMAGE") || ""
    property real driftX: 0
    property real driftY: 0
    Behavior on driftX { NumberAnimation { duration: 550; easing.type: Easing.OutCubic } }
    Behavior on driftY { NumberAnimation { duration: 650; easing.type: Easing.OutCubic } }

    Image {
        anchors.fill: parent
        source: wallpaper.imageOverride ? "file://" + wallpaper.imageOverride.split("/").map(encodeURIComponent).join("/") : "file:///etc/ohmansy/wallpaper.png"
        fillMode: Image.PreserveAspectCrop
        visible: animation.status !== Loader.Ready
        onStatusChanged: {
            // Standalone previews may not have the system wallpaper installed.
            if (status === Image.Error && source !== Qt.resolvedUrl("wallpaper.png"))
                source = Qt.resolvedUrl("wallpaper.png");
        }
    }
    Loader {
        id: animation
        // Overscan keeps the animated backdrop opaque during parallax.
        width: parent.width + 224
        height: parent.height + 224
        x: -112 + wallpaper.driftX
        y: -112 + wallpaper.driftY
        active: GraphicsInfo.api === GraphicsInfo.OpenGL && !wallpaper.ribbonFailure && !wallpaper.imageOverride
        source: active ? "Ribbons.qml" : ""
        onLoaded: {
            item.motionSpeed = 0.15;
            // Reduce shader pixels while preserving window size and cadence.
            item.renderScale = Qt.binding(() => WallpaperQuality.renderScale);
            item.particleLayers = Qt.binding(() => WallpaperQuality.particleLayers);
            item.particleMotionDetail = Qt.binding(() => WallpaperQuality.particleMotionDetail);
            item.moving = Qt.binding(() => WallpaperQuality.moving);
            // About 15 fps at rest; keep the short appearance fade smooth.
            item.frameInterval = Qt.binding(() => Appearance.transitioning ? 16 : 66);
            item.targetLightMix = Qt.binding(() => Appearance.lightMix);
            item.lightMix = Appearance.lightMix;
        }
    }
    Connections {
        target: animation.item
        function onFailedChanged() {
            if (animation.item && animation.item.failed) wallpaper.ribbonFailure = true;
        }
    }
}
