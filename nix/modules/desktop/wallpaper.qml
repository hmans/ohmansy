//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma UseQApplication
//@ pragma DefaultEnv QT_QPA_PLATFORMTHEME=xdgdesktopportal
import QtQuick
import Quickshell
import Quickshell.Wayland
import Ohmansy.Ui as Ui

ShellRoot {
    NiriState { id: niri }
    Variants {
        model: Quickshell.screens
        PanelWindow {
            id: wallpaper
            required property var modelData
            screen: modelData
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Background
            WlrLayershell.namespace: "ohmansy-wallpaper"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            mask: Region {}
            color: "#171a21"
            property bool ribbonFailure: false
            readonly property string imageOverride: Quickshell.env("OHMANSY_WALLPAPER_IMAGE") || ""
            readonly property var workspace: niri.state.workspaces.find(
                w => w.output === modelData.name && w.is_active) || null
            readonly property var activeWindow: workspace ? niri.state.windows.find(
                w => w.id === workspace.active_window_id) || null : null
            readonly property int column: activeWindow && activeWindow.layout
                && activeWindow.layout.pos_in_scrolling_layout
                ? activeWindow.layout.pos_in_scrolling_layout[0] : 1
            // IPC supplies focus destinations, not continuous gesture positions.
            // Bound the drift so even long workspaces never reveal an edge.
            property real driftX: -64 * Math.atan((column - 1) * 0.55)
            property real driftY: -48 * Math.atan(((workspace ? workspace.idx : 1) - 1) * 0.55)
            Behavior on driftX { NumberAnimation { duration: 550; easing.type: Easing.OutCubic } }
            Behavior on driftY { NumberAnimation { duration: 650; easing.type: Easing.OutCubic } }

            Image {
                anchors.fill: parent
                source: wallpaper.imageOverride ? "file://" + wallpaper.imageOverride.split("/").map(encodeURIComponent).join("/") : "file:///etc/ohmansy/wallpaper.png"
                fillMode: Image.PreserveAspectCrop
                visible: animation.status !== Loader.Ready
            }
            Loader {
                id: animation
                // Overscan keeps the animated backdrop opaque during movement.
                width: parent.width + 224
                height: parent.height + 224
                x: -112 + wallpaper.driftX
                y: -112 + wallpaper.driftY
                active: GraphicsInfo.api === GraphicsInfo.OpenGL && !ribbonFailure && !wallpaper.imageOverride
                source: active ? "Ribbons.qml" : ""
                onLoaded: {
                    item.targetLightMix = Qt.binding(() => Ui.Appearance.lightMix);
                    item.lightMix = Ui.Appearance.lightMix;
                }
            }
            Connections {
                target: animation.item
                function onFailedChanged() {
                    if (animation.item && animation.item.failed) ribbonFailure = true;
                }
            }
        }
    }
}
