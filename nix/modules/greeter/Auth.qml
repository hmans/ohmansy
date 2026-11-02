import QtQuick
import Quickshell.Services.Greetd

QtObject {
    id: root
    property string user: ""
    property string prompt: "Password"
    property string message: ""
    property bool echo: false
    property bool waiting: false
    property bool busy: false
    property string sessionCommand: ""
    signal clearResponse()

    function selectUser(name) {
        retry.stop();
        user = name.trim();
        waiting = false;
        busy = false;
        message = "";
        clearResponse();
        if (Greetd.state !== GreetdState.Inactive) Greetd.cancelSession();
        if (user !== "") retry.start();
    }
    function submit(response) {
        if (!waiting || busy) return;
        waiting = false;
        busy = true;
        message = "";
        Greetd.respond(response);
        clearResponse();
    }
    property Timer retry: Timer {
        interval: 80
        repeat: true
        onTriggered: {
            if (!Greetd.available) {
                stop();
                root.message = "The login service is unavailable.";
            } else if (Greetd.state === GreetdState.Inactive) {
                stop();
                root.busy = true;
                Greetd.createSession(root.user);
            }
        }
    }
    property Connections connection: Connections {
        target: Greetd
        function onAuthMessage(message, error, responseRequired, echoResponse) {
            root.busy = !responseRequired;
            if (responseRequired) {
                root.prompt = message.trim().replace(/:\s*$/, "") || "Password";
                root.echo = echoResponse;
                root.clearResponse();
                root.waiting = true;
            } else {
                root.waiting = false;
                root.message = message;
            }
        }
        function onAuthFailure(message) {
            root.clearResponse();
            root.waiting = false;
            root.busy = false;
            root.message = "Sign-in failed. Check your details and try again.";
            root.retry.start();
        }
        function onError(error) {
            root.clearResponse();
            root.waiting = false;
            root.busy = false;
            root.message = "Could not sign in. Select your account to try again.";
        }
        function onReadyToLaunch() {
            root.clearResponse();
            root.waiting = false;
            root.busy = true;
            if (!root.sessionCommand) {
                root.message = "The desktop session is unavailable.";
                Greetd.cancelSession();
                root.busy = false;
                return;
            }
            Greetd.launch([root.sessionCommand], ["XDG_SESSION_TYPE=wayland", "XDG_CURRENT_DESKTOP=niri"]);
        }
    }
}
