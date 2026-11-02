//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma UseQApplication
//@ pragma DefaultEnv QT_QPA_PLATFORMTHEME=xdgdesktopportal
import Quickshell
import Quickshell.Io
import QtQuick

ShellRoot {
    id: root
    // Use the same portal-backed Qt preference as the desktop palette.
    readonly property bool darkTheme: Qt.styleHints.colorScheme === Qt.ColorScheme.Dark
    onDarkThemeChanged: terminalTheme.restart()
    Component.onCompleted: terminalTheme.restart()
    Timer {
        id: terminalTheme
        interval: 50
        onTriggered: Quickshell.execDetached([
            Quickshell.env("OHMANSY_TERMINAL_THEME"), root.darkTheme ? "dark" : "light"
        ])
    }
    property string launcherScreen: ""
    function toggleLauncher(screenName) {
        launcherScreen = launcherScreen === screenName ? "" : screenName;
    }
    IpcHandler {
        target: "launcher"
        function toggle(): void {
            root.toggleLauncher(niri.focusedOutput || Quickshell.screens[0].name);
        }
        function close(): void { root.launcherScreen = ""; }
    }
    NiriState { id: niri }
    AudioState { id: audioState }
    AppearanceState { id: appearanceState }
    Variants {
        model: Quickshell.screens
        Bar {
            id: bar
            required property var modelData
            screen: modelData
            niriState: niri
            audio: audioState
            appearance: appearanceState
            launcherActive: root.launcherScreen === modelData.name
            onLauncherRequested: root.toggleLauncher(modelData.name)
            onLauncherDismissed: if (root.launcherScreen === modelData.name) root.launcherScreen = ""
        }
    }
}
