import QtQuick
import Quickshell

ShellRoot {
    Auth {
        id: authentication
        onWaitingChanged: {
            if (!waiting) return;
            Qt.callLater(function() {
                if (Quickshell.env("TEST_SESSION") === "ohmansy")
                    selectSession(1);
                if (Quickshell.env("TEST_CANCEL") === "1" && user === "test-user")
                    selectUser("other-user");
                else
                    submit(echo ? "test-code" : "test-response");
            });
        }
    }
    Component.onCompleted: {
        authentication.configureSessions({default: "niri", sessions: [
            {id: "niri", label: "ohmansy (Niri)", command: "/test/niri-session", desktop: "niri"},
            {id: "ohmansy", label: "Shine (experimental)", command: "/test/ohmansy-session", desktop: "ohmansy"}
        ]});
        authentication.selectUser("test-user");
    }
}
