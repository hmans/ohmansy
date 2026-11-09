//@ pragma Env QS_NO_RELOAD_POPUP=1
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

ShellRoot {
    id: root
    property int phase: 0
    IpcHandler {
        target: "fixture"
        function advance(): void { root.phase++; }
    }
    Variants {
        model: Quickshell.screens
        PanelWindow {
            required property var modelData
            screen: modelData
            anchors { top: true; bottom: true; left: true; right: true }
            color: "black"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Background
            WlrLayershell.namespace: "ohmansy-wallpaper"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            mask: Region {}
            Canvas {
                id: pattern
                anchors.fill: parent
                readonly property int phase: root.phase
                onPhaseChanged: requestPaint()
                onWidthChanged: requestPaint()
                onHeightChanged: requestPaint()
                onPaint: {
                    const ctx = getContext("2d");
                    for (let y = 0; y < height; y += 16) {
                        for (let x = 0; x < width; x += 16) {
                            const odd = ((x+y)/16)%2;
                            ctx.fillStyle = phase%2 ? (odd ? "#ffff00" : "#00ffff") : (odd ? "#ff0000" : "#0000ff");
                            ctx.fillRect(x,y,16,16);
                        }
                    }
                    // Break vertical symmetry so a flipped import cannot pass
                    // the screen-coordinate sampling checks.
                    const shade = ctx.createLinearGradient(0,0,0,height);
                    shade.addColorStop(0,"rgba(255,255,255,0)");
                    shade.addColorStop(1,"rgba(255,255,255,0.2)");
                    ctx.fillStyle = shade;
                    ctx.fillRect(0,0,width,height);
                }
            }
        }
    }
}
