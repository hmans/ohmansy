//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma UseQApplication
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

ShellRoot {
    id: root
    property var users: []
    property string powerAction: ""
    function confirmPower() { power.running = true; }
    Auth { id: authentication }
    FileView {
        path: "/etc/ohmansy/greeter-session"
        onLoaded: authentication.sessionCommand = text().trim()
    }
    Process {
        running: true
        command: ["/etc/ohmansy/greeter-users"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.users = JSON.parse(text); } catch (e) { root.users = []; }
                if (root.users.length) authentication.selectUser(root.users[0].name);
            }
        }
    }
    Process {
        id: power
        command: ["/run/current-system/sw/bin/systemctl", root.powerAction]
        onExited: (code, status) => {
            if (code !== 0) authentication.message = "Could not complete the power request.";
            root.powerAction = "";
        }
    }
    SystemClock { id: clock; precision: SystemClock.Minutes }
    Variants {
        model: Quickshell.screens
        PanelWindow {
            id: window
            required property var modelData
            property bool primary: modelData === Quickshell.screens[0]
            screen: modelData
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: primary ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            color: "#171a21"

            GreeterView {
                anchors.fill: parent
                controller: root
                auth: authentication
                now: clock.date
                primary: window.primary
            }
        }
    }
}
