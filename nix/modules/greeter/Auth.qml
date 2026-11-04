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
    property var sessions: []
    property int sessionIndex: -1
    readonly property var selectedSession: sessionIndex >= 0 && sessionIndex < sessions.length
        ? sessions[sessionIndex] : null
    signal clearResponse()

    function configureSessions(configuration) {
        const entries = configuration.sessions;
        if (!Array.isArray(entries) || !entries.length
                || entries.some(entry => !entry.id || !entry.label
                    || typeof entry.command !== "string" || !entry.command.startsWith("/")
                    || typeof entry.desktop !== "string" || !/^[A-Za-z0-9_:-]+$/.test(entry.desktop))) {
            message = "Desktop sessions are unavailable.";
            return;
        }
        const index = entries.findIndex(entry => entry.id === configuration.default);
        if (index < 0) {
            message = "The default desktop session is unavailable.";
            return;
        }
        sessions = entries;
        sessionIndex = index;
    }
    function selectSession(index) {
        if (busy || index < 0 || index >= sessions.length) return;
        sessionIndex = index;
        clearResponse();
    }

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
            const session = root.selectedSession;
            if (!session) {
                root.message = "The desktop session is unavailable.";
                Greetd.cancelSession();
                root.busy = false;
                return;
            }
            Greetd.launch([session.command], ["XDG_SESSION_TYPE=wayland",
                "XDG_CURRENT_DESKTOP=" + session.desktop, "XDG_SESSION_DESKTOP=" + session.id]);
        }
    }
}
