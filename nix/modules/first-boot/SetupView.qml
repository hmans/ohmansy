import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Ohmansy.Ui

Item {
    id: view
    required property var controller
    property bool primary: true
    property string page: "welcome"
    property bool failed: false
    readonly property bool animated: Quickshell.env("OHMANSY_GREETER_STATIC") !== "1"
    readonly property var headings: ({welcome: "OH.\nYOU’RE HERE.", identity: "Name your\naccomplice.", password: "Give the chaos\na password.", done: "A human.\nFinally."})
    function reveal(item) {
        if (!item.activeFocus) return;
        const position = item.mapToItem(form, 0, 0);
        const bottom = form.y + position.y + item.height;
        if (bottom > scroll.contentY + scroll.height) scroll.contentY = bottom - scroll.height + 12;
        else if (form.y + position.y < scroll.contentY) scroll.contentY = Math.max(0, form.y + position.y - 12);
    }
    function advance() {
        if (controller.busy || !pages.interactive) return;
        controller.error = "";
        if (page === "welcome") page = "identity";
        else if (page === "identity") {
            if (!name.text.trim()) { controller.error = "What should we call you?"; name.forceActiveFocus(); return; }
            if (!/^[a-z][a-z0-9_-]{0,30}$/.test(username.text)) {
                controller.error = "Username: lowercase letters, digits, - or _. Start with a letter.";
                username.forceActiveFocus(); return;
            }
            page = "password";
        } else if (page === "password") {
            if (password.text.length < 8) { controller.error = "Give it at least 8 characters."; return; }
            if (password.text !== confirmation.text) { controller.error = "Those passwords don’t match yet."; return; }
            controller.request("create", username.text, name.text.trim(), password.text);
            password.clear(); confirmation.clear();
        } else if (page === "done") Qt.quit();
    }
    Connections {
        target: controller
        function onPendingUserChanged() { if (controller.pendingUser) username.text = controller.pendingUser; }
        function onCreated() { password.clear(); confirmation.clear(); view.page = "done"; }
    }
    FadeSwitch {
        id: pages
        requestedPage: view.page
        displayedPage: "welcome"
        animated: view.animated
        onSettled: Qt.callLater(() => {
            if (!view.primary) return;
            if (displayedPage === "identity") name.forceActiveFocus();
            else if (displayedPage === "password") password.forceActiveFocus();
            else forward.forceActiveFocus();
        })
    }
    Item {
        id: background
        anchors.fill: parent
        Rectangle { anchors.fill: parent; color: "#171a21" }
        Image { anchors.fill: parent; source: "file:///etc/ohmansy/wallpaper.png"; fillMode: Image.PreserveAspectCrop; visible: ribbons.status !== Loader.Ready }
        Loader {
            id: ribbons
            anchors.fill: parent
            active: view.animated && !view.failed && GraphicsInfo.api === GraphicsInfo.OpenGL
            source: active ? "file:///etc/ohmansy/greeter/scene/Ribbons.qml" : ""
            onLoaded: item.moving = Qt.binding(() => view.visible && !controller.busy)
        }
        Connections { target: ribbons.item; function onFailedChanged() { if (ribbons.item && ribbons.item.failed) view.failed = true; } }
        Rectangle { anchors.fill: parent; color: "#25101924" }
    }
    ShaderEffectSource {
        id: texture
        anchors.fill: parent
        sourceItem: GraphicsInfo.api !== GraphicsInfo.Software ? background : null
        textureSize: Qt.size(Math.max(1, width / 2), Math.max(1, height / 2))
        visible: false
    }
    MultiEffect {
        id: blur
        anchors.fill: parent
        source: texture
        visible: false
        blurEnabled: true
        blurMax: 32
        blur: 1
        autoPaddingEnabled: false
        layer.enabled: GraphicsInfo.api !== GraphicsInfo.Software
        property string layoutRevision: [view.width, view.height, scroll.contentY, form.y, form.height, pages.displayedPage].join(":")
    }
    Text {
        anchors { left: parent.left; top: parent.top; margins: 28 }
        text: "ohmansy"
        color: Theme.text
        font { family: Theme.fontFamily; pixelSize: 22; weight: Font.DemiBold }
    }
    Text {
        anchors { right: parent.right; top: parent.top; margins: 30 }
        text: "A SMALL CEREMONY FOR A NEW COMPUTER"
        visible: view.width > 800
        color: "#b9b6c8"
        font { family: Theme.fontFamily; pixelSize: 11; letterSpacing: 1.5 }
    }
    Flickable {
        id: scroll
        anchors { fill: parent; topMargin: 80; bottomMargin: 28; leftMargin: 28; rightMargin: 28 }
        contentHeight: Math.max(height, form.implicitHeight + 40)
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar {}
        visible: view.primary
        ColumnLayout {
            id: form
            width: Math.min(520, scroll.width)
            x: (scroll.width - width) / 2
            y: Math.max(12, (scroll.height - implicitHeight) / 2)
            spacing: 18
            opacity: pages.contentOpacity
            enabled: pages.interactive && !controller.busy
            Text {
                Layout.fillWidth: true
                text: view.headings[pages.displayedPage] || ""
                color: Theme.text
                font { family: Theme.fontFamily; pixelSize: view.height < 650 ? 44 : 64; weight: Font.Bold; letterSpacing: -2 }
                lineHeight: 0.95
                wrapMode: Text.WordWrap
            }
            Text {
                Layout.fillWidth: true
                Layout.bottomMargin: 10
                text: pages.displayedPage === "welcome" ? "Fresh pixels. Questionable amounts of purple.\nA whole computer with your name on it. Almost."
                    : pages.displayedPage === "identity" ? "Every mildly unhinged desktop needs a responsible adult.\nYou’ll do."
                    : pages.displayedPage === "password" ? "For logging in. For unlocking things.\nFor keeping the gremlins out."
                    : "Your computer has acquired a human.\nPlease use your newfound powers irresponsibly responsibly."
                color: "#cbc6dc"
                font { family: Theme.fontFamily; pixelSize: 17 }
                wrapMode: Text.WordWrap
                lineHeight: 1.25
            }
            ColumnLayout {
                visible: pages.displayedPage === "identity"
                Layout.fillWidth: true
                spacing: 12
                GlassField { id: name; Layout.fillWidth: true; backdrop: blur; placeholderText: "Your name"; maximumLength: 80; Accessible.name: "Your name"; onActiveFocusChanged: view.reveal(this); onAccepted: username.forceActiveFocus() }
                GlassField { id: username; Layout.fillWidth: true; backdrop: blur; placeholderText: "Username"; maximumLength: 31; readOnly: !!controller.pendingUser; Accessible.name: "Username"; onActiveFocusChanged: view.reveal(this); onAccepted: view.advance() }
                Text { Layout.fillWidth: true; text: controller.pendingUser ? "We saved your place. Let’s finish this account." : "Lowercase. No spaces. Your future terminal identity."; color: "#b9b6c8"; font.pixelSize: 13; wrapMode: Text.WordWrap }
            }
            ColumnLayout {
                visible: pages.displayedPage === "password"
                Layout.fillWidth: true
                spacing: 12
                GlassField { id: password; Layout.fillWidth: true; backdrop: blur; placeholderText: "Password · at least 8 characters"; maximumLength: 1024; echoMode: TextInput.Password; Accessible.name: "Password"; onActiveFocusChanged: view.reveal(this); onAccepted: confirmation.forceActiveFocus() }
                GlassField { id: confirmation; Layout.fillWidth: true; backdrop: blur; placeholderText: "Once more, with feeling"; maximumLength: 1024; echoMode: TextInput.Password; Accessible.name: "Confirm password"; onActiveFocusChanged: view.reveal(this); onAccepted: view.advance() }
            }
            Text { Layout.fillWidth: true; visible: !!controller.error; text: controller.error; color: "#ffc2cf"; font.pixelSize: 15; wrapMode: Text.WordWrap; Accessible.role: Accessible.AlertMessage }
            GlassButton {
                id: forward
                Layout.fillWidth: true
                backdrop: blur
                primary: true
                text: controller.busy ? "Summoning your account…" : pages.displayedPage === "welcome" ? "Let me in."
                    : pages.displayedPage === "identity" ? "That’s me. Allegedly."
                    : pages.displayedPage === "password" ? "Make this computer mine."
                    : "Unleash the desktop."
                onClicked: view.advance()
            }
            GlassButton {
                Layout.fillWidth: true
                backdrop: blur
                visible: pages.displayedPage === "identity" || pages.displayedPage === "password"
                implicitHeight: 44
                text: "Back"
                onClicked: { controller.error = ""; password.clear(); confirmation.clear(); view.page = view.page === "password" ? "identity" : "welcome"; }
            }
            Text {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: 8
                text: pages.displayedPage === "done" ? "SETUP COMPLETE · NO SACRIFICES REQUIRED" : "STEP " + (pages.displayedPage === "welcome" ? "1" : pages.displayedPage === "identity" ? "2" : "3") + " OF 3 · ENTIRELY ON THIS COMPUTER"
                color: "#aaa4bd"
                font { family: Theme.fontFamily; pixelSize: 11; letterSpacing: 0.8 }
            }
        }
    }
}
