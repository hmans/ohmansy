import QtQuick
import Quickshell

ShellRoot {
    Auth {
        id: authentication
        sessionCommand: "/test/niri-session"
        onWaitingChanged: {
            if (!waiting) return;
            Qt.callLater(function() {
                if (Quickshell.env("TEST_CANCEL") === "1" && user === "test-user")
                    selectUser("other-user");
                else
                    submit(echo ? "test-code" : "test-response");
            });
        }
    }
    Component.onCompleted: authentication.selectUser("test-user")
}
