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
        Ui.WallpaperWindow {
            required property var modelData
            screen: modelData
            readonly property var workspace: niri.state.workspaces.find(
                w => w.output === modelData.name && w.is_active) || null
            readonly property var activeWindow: workspace ? niri.state.windows.find(
                w => w.id === workspace.active_window_id) || null : null
            readonly property int column: activeWindow && activeWindow.layout
                && activeWindow.layout.pos_in_scrolling_layout
                ? activeWindow.layout.pos_in_scrolling_layout[0] : 1
            // IPC supplies focus destinations, not continuous gesture positions.
            // Bound the drift so even long workspaces never reveal an edge.
            driftX: -64 * Math.atan((column - 1) * 0.55)
            // Workspace parallax stays within the 112-point overscan margin.
            driftY: -64 * Math.atan(((workspace ? workspace.idx : 1) - 1) * 0.55)
        }
    }
}
