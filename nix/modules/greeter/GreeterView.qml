import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

Item {
    id: view
    required property var controller
    required property var auth
    required property date now
    required property bool primary
    readonly property bool compact: height < 560
    property bool motionEnabled: Quickshell.env("OHMANSY_GREETER_STATIC") !== "1"
    readonly property var sceneStats: sculpture.item ? sculpture.item.renderStats : null
    function reveal(item) {
        const bottom = form.y + item.y + item.height;
        if (bottom > viewport.contentY + viewport.height)
            viewport.contentY = bottom - viewport.height;
        else if (form.y + item.y < viewport.contentY)
            viewport.contentY = form.y + item.y;
    }
    Rectangle { anchors.fill: parent; color: "#171a21" }
    Canvas {
        visible: sculpture.status !== Loader.Ready
        anchors.fill: parent
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onPaint: {
            const c = getContext("2d");
            c.reset();
            // Broad, quiet ribbons echo the native host's welcome screen.
            const colors = ["#1c2936", "#242633", "#262532"];
            for (let i = 0; i < 3; i++) {
                c.beginPath();
                c.moveTo(width * (0.55 + i * 0.15), -height * 0.3);
                c.bezierCurveTo(width * 0.15, height * 0.5, width * 1.2,
                    height * 0.4, width * (0.35 + i * 0.2), height * 1.4);
                c.strokeStyle = colors[i];
                c.lineWidth = width * 0.14;
                c.stroke();
            }
        }
    }
    Loader {
        id: sculpture
        anchors.fill: parent
        active: Quickshell.env("OHMANSY_GREETER_STATIC") !== "1"
            && GraphicsInfo.api !== GraphicsInfo.Software
        source: active ? "scene/Sculpture.qml" : ""
        onLoaded: item.moving = Qt.binding(() => view.motionEnabled && view.visible && !auth.busy)
    }
    // Keep the form readable at every point in the sculpture's rotation.
    Rectangle {
        anchors.fill: parent
        visible: sculpture.status === Loader.Ready
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: "#e6171a21" }
            GradientStop { position: 0.5; color: "#aa171a21" }
            GradientStop { position: 1; color: "#18171a21" }
        }
    }
    Text {
        anchors { left: parent.left; top: parent.top; margins: view.compact ? 20 : 32 }
        text: "ohmansy"
        font { family: "IBM Plex Sans"; pixelSize: 24; weight: Font.DemiBold }
        color: "#e0def4"
    }
    Text {
        anchors { right: parent.right; top: parent.top; margins: 32 }
        text: Qt.formatDateTime(view.now, "ddd, d MMM   hh:mm")
        font { family: "IBM Plex Sans"; pixelSize: 14 }
        color: "#b9b5ce"
        visible: parent.width > 500
    }
    Flickable {
        id: viewport
        anchors {
            fill: parent
            topMargin: view.compact ? 64 : 86
            bottomMargin: view.width <= 700 && sculpture.status === Loader.Ready
                ? (view.compact ? 96 : 132) : (view.compact ? 68 : 90)
        }
        contentHeight: form.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
        visible: view.primary && !controller.powerAction
    ColumnLayout {
        id: form
        visible: view.primary && !controller.powerAction
        x: (viewport.width - width) / 2
        y: Math.max(0, (viewport.height - implicitHeight) / 2)
        width: Math.min(320, viewport.width - 48)
        spacing: view.compact ? 8 : 14
        property bool otherUser: controller.users.length === 0
        Text {
            visible: !view.compact
            text: "Welcome back."
            Layout.fillWidth: true
            font { family: "IBM Plex Sans"; pixelSize: 32; weight: Font.Medium }
            color: "#e0def4"
            horizontalAlignment: Text.AlignHCenter
        }
        ComboBox {
            id: accounts
            visible: !form.otherUser
            Layout.fillWidth: true
            implicitHeight: view.compact ? 40 : 44
            model: controller.users
            textRole: "label"
            Accessible.name: "Account"
            font { family: "IBM Plex Sans"; pixelSize: 17 }
            palette { text: "#e0def4"; buttonText: "#e0def4"; button: "#252832"; base: "#252832"; highlight: "#645373"; highlightedText: "#ffffff" }
            background: Rectangle {
                color: "#252832"; radius: 9
                border.color: accounts.visualFocus ? "#c4a7e7" : "#55515f"
                border.width: accounts.visualFocus ? 2 : 1
            }
            onActivated: auth.selectUser(controller.users[currentIndex].name)
        }
        GreeterField {
            id: username
            visible: form.otherUser
            Layout.fillWidth: true
            placeholderText: "Username"
            Accessible.name: "Username"
            onAccepted: auth.selectUser(text)
            Component.onCompleted: if (form.otherUser && view.primary) forceActiveFocus()
        }
        Text {
            visible: auth.waiting && !view.compact
            text: auth.prompt
            color: "#b9b5ce"
            font { family: "IBM Plex Sans"; pixelSize: 14 }
        }
        GreeterField {
            id: response
            Layout.fillWidth: true
            visible: auth.waiting || auth.busy
            enabled: auth.waiting
            implicitHeight: view.compact ? 44 : 48
            placeholderText: view.compact ? auth.prompt : ""
            echoMode: auth.echo ? TextInput.Normal : TextInput.Password
            inputMethodHints: auth.echo ? Qt.ImhNone : Qt.ImhSensitiveData | Qt.ImhNoPredictiveText | Qt.ImhHiddenText
            Accessible.name: auth.prompt
            onAccepted: auth.submit(text)
            onActiveFocusChanged: if (activeFocus) view.reveal(response)
            Keys.onEscapePressed: auth.selectUser(auth.user)
            Connections {
                target: auth
                function onClearResponse() { response.clear(); }
                function onWaitingChanged() {
                    if (auth.waiting && view.primary) {
                        response.forceActiveFocus();
                        viewport.contentY = Math.max(0, response.y + response.height - viewport.height);
                    }
                }
            }
        }
        Text {
            Layout.fillWidth: true
            visible: text !== ""
            text: auth.message
            color: "#edb5bd"
            font { family: "IBM Plex Sans"; pixelSize: 14 }
            wrapMode: Text.Wrap
            horizontalAlignment: Text.AlignHCenter
            Accessible.role: Accessible.AlertMessage
        }
        GreeterButton {
            id: signIn
            Layout.fillWidth: true
            implicitHeight: view.compact ? 40 : 44
            onActiveFocusChanged: if (activeFocus) view.reveal(signIn)
            primary: true
            text: auth.busy ? "Signing in…" : "Sign in"
            enabled: !auth.busy && (auth.waiting || (form.otherUser && username.text.trim() !== ""))
            onClicked: {
                if (auth.waiting) auth.submit(response.text);
                else auth.selectUser(username.text);
            }
        }
        GreeterButton {
            id: otherAccount
            Layout.alignment: Qt.AlignHCenter
            implicitHeight: view.compact ? 32 : 44
            onActiveFocusChanged: if (activeFocus) view.reveal(otherAccount)
            text: form.otherUser && controller.users.length ? "Back to accounts" : "Use another account"
            visible: controller.users.length > 0
            onClicked: {
                form.otherUser = !form.otherUser;
                auth.selectUser(form.otherUser ? "" : controller.users[accounts.currentIndex].name);
                if (form.otherUser) username.forceActiveFocus();
            }
        }
    }
    }
    ColumnLayout {
        visible: view.primary && controller.powerAction !== ""
        anchors.centerIn: parent
        width: Math.min(320, parent.width - 48)
        spacing: 16
        Text {
            text: controller.powerAction === "reboot" ? "Restart this computer?" : "Shut down this computer?"
            color: "#e0def4"
            font { family: "IBM Plex Sans"; pixelSize: 22 }
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            horizontalAlignment: Text.AlignHCenter
        }
        GreeterButton {
            Layout.fillWidth: true
            primary: true
            text: controller.powerAction === "reboot" ? "Restart" : "Shut down"
            onClicked: controller.confirmPower()
        }
        GreeterButton {
            Layout.fillWidth: true
            text: "Cancel"
            onClicked: controller.powerAction = ""
        }
    }
    RowLayout {
        visible: view.primary && !controller.powerAction
        anchors { bottom: parent.bottom; horizontalCenter: parent.horizontalCenter; bottomMargin: view.compact ? 16 : 24 }
        spacing: 12
        GreeterButton { text: "Restart"; implicitHeight: view.compact ? 36 : 44; onClicked: { response.clear(); controller.powerAction = "reboot"; } }
        GreeterButton { text: "Shut down"; implicitHeight: view.compact ? 36 : 44; onClicked: { response.clear(); controller.powerAction = "poweroff"; } }
    }
    GreeterButton {
        anchors { left: parent.left; bottom: parent.bottom; margins: view.compact ? 16 : 24 }
        visible: sculpture.status === Loader.Ready
        implicitHeight: view.compact ? 28 : 44
        anchors.bottomMargin: view.width > 700 ? 24 : (view.compact ? 54 : 76)
        text: view.motionEnabled ? "Pause motion" : "Resume motion"
        onClicked: view.motionEnabled = !view.motionEnabled
    }
}
