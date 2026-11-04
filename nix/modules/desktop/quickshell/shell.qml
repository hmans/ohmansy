//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma UseQApplication
//@ pragma IconTheme Adwaita
//@ pragma DefaultEnv QT_QPA_PLATFORMTHEME=xdgdesktopportal
import Quickshell
import Quickshell.Io
import QtQuick

ShellRoot {
    id: root
    // Use the same portal-backed Qt preference as the desktop palette.
    readonly property bool darkTheme: Qt.styleHints.colorScheme === Qt.ColorScheme.Dark
    onDarkThemeChanged: desktopTheme.restart()
    Component.onCompleted: desktopTheme.restart()
    Timer {
        id: desktopTheme
        interval: 50
        onTriggered: {
            const mode = root.darkTheme ? "dark" : "light";
            Quickshell.execDetached([Quickshell.env("OHMANSY_TERMINAL_THEME"), mode]);
            Quickshell.execDetached([Quickshell.env("OHMANSY_NIRI_THEME"), mode]);
        }
    }
    property string launcherScreen: ""
    property string launcherMode: "apps"
    function toggleLauncher(screenName, mode = "apps") {
        const closing = launcherScreen === screenName && launcherMode === mode;
        launcherMode = mode;
        launcherScreen = closing ? "" : screenName;
    }
    IpcHandler {
        target: "launcher"
        function toggle(): void {
            root.toggleLauncher(niri.focusedOutput || Quickshell.screens[0].name);
        }
        function close(): void { root.launcherScreen = ""; }
        function ping(): string { return "ready"; }
        function openMenu(mode: string): void {
            if (!["apps", "windows", "clipboard", "power", "controls", "notifications", "shortcuts", "displays"].includes(mode)) return;
            root.toggleLauncher(niri.focusedOutput || Quickshell.screens[0].name, mode);
        }
    }
    NiriState { id: niri }
    AudioState { id: audioState }
    AppearanceState { id: appearanceState }
    DisplayState { id: displayState }
    Variants {
        model: Quickshell.screens
        Bar {
            id: bar
            required property var modelData
            screen: modelData
            niriState: niri
            audio: audioState
            appearance: appearanceState
            displays: displayState
            launcherActive: root.launcherScreen === modelData.name
            launcherMode: root.launcherMode
            onLauncherRequested: root.toggleLauncher(modelData.name)
            onDisplayRequested: root.toggleLauncher(modelData.name, "displays")
            onLauncherDismissed: if (root.launcherScreen === modelData.name) root.launcherScreen = ""
        }
    }
}
