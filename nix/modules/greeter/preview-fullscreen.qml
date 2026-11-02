//@ pragma UseQApplication
import QtQuick
import Quickshell
import Quickshell.Wayland

// Visible Wayland preview for GPU measurements. No authentication or power actions.
ShellRoot {
    PanelWindow {
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: Quickshell.env("PREVIEW_KEYBOARD") === "1"
            ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        color: "#171a21"
        GreeterPreview { anchors.fill: parent }
    }
}
