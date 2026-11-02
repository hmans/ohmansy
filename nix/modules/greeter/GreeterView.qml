import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Ohmansy.Ui

Item {
    id: view
    required property var controller
    required property var auth
    required property date now
    required property bool primary
    readonly property bool compact: height < 560
    property bool motionEnabled: Quickshell.env("OHMANSY_GREETER_STATIC") !== "1"
    property bool ribbonFailure: false
    readonly property bool passwordPrompt: /^password\s*:?\s*$/i.test(auth.prompt.trim())
    readonly property var sceneStats: sculpture.item ? sculpture.item.renderStats : null
    function entranceOpacity(delay) {
        return entrance.opacityAt(delay);
    }
    StaggeredEntrance {
        id: entrance
        animated: Quickshell.env("OHMANSY_GREETER_STATIC") !== "1"
    }
    FadeSwitch {
        id: pageFade
        requestedPage: controller.powerMenuOpen ? "power" : ""
        animated: Quickshell.env("OHMANSY_GREETER_STATIC") !== "1"
        onSettled: {
            if (!view.primary) return;
            if (displayedPage !== "") cancelPower.forceActiveFocus();
            else if (auth.waiting) response.forceActiveFocus();
            else if (form.otherUser) username.forceActiveFocus();
            else accounts.forceActiveFocus();
        }
    }
    Connections {
        target: controller
        function onPowerMenuOpenChanged() { accounts.popup.close(); }
    }
    function reveal(item) {
        const bottom = form.y + item.y + item.height;
        if (bottom > viewport.contentY + viewport.height)
            viewport.contentY = bottom - viewport.height;
        else if (form.y + item.y < viewport.contentY)
            viewport.contentY = form.y + item.y;
    }
    Item {
    id: backdropScene
    anchors.fill: parent
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
        active: Quickshell.env("OHMANSY_GREETER_STATIC") !== "1" && !view.ribbonFailure
            && GraphicsInfo.api === GraphicsInfo.OpenGL
        source: active ? "scene/Ribbons.qml" : ""
        onLoaded: item.moving = Qt.binding(() => view.motionEnabled && view.visible && !auth.busy)
    }
    Connections {
        target: sculpture.item
        function onFailedChanged() {
            if (sculpture.item && sculpture.item.failed) view.ribbonFailure = true;
        }
    }
    }
    ShaderEffectSource {
        id: backdropTexture
        anchors.fill: parent
        sourceItem: GraphicsInfo.api !== GraphicsInfo.Software ? backdropScene : null
        textureSize: Qt.size(Math.max(1, width / 2), Math.max(1, height / 2))
        visible: false
    }
    MultiEffect {
        id: blurredBackdrop
        anchors.fill: parent
        source: backdropTexture
        visible: false
        blurEnabled: true
        blurMax: 32
        blur: 1
        autoPaddingEnabled: false
        layer.enabled: GraphicsInfo.api !== GraphicsInfo.Software
        layer.textureSize: Qt.size(Math.max(1, width / 2), Math.max(1, height / 2))
        property string layoutRevision: [view.width, view.height, viewport.contentY,
            form.y, form.implicitHeight, accounts.popup.visible].join(":")
    }
    Text {
        anchors { left: parent.left; top: parent.top; margins: view.compact ? 20 : 32 }
        text: "ohmansy"
        opacity: view.entranceOpacity(280)
        font { family: "IBM Plex Sans"; pixelSize: 24; weight: Font.DemiBold }
        color: "#e0def4"
    }
    Text {
        anchors { right: parent.right; top: parent.top; margins: 32 }
        text: Qt.formatDateTime(view.now, "ddd, d MMM   hh:mm")
        opacity: view.entranceOpacity(280)
        font { family: "IBM Plex Sans"; pixelSize: 14 }
        color: "#b9b5ce"
        visible: parent.width > 500
    }
    Flickable {
        id: viewport
        anchors {
            fill: parent
            topMargin: view.compact ? 64 : 86
            bottomMargin: view.compact ? 76 : 96
        }
        contentHeight: form.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
        visible: view.primary && pageFade.displayedPage === ""
        opacity: pageFade.contentOpacity
        enabled: pageFade.interactive
    ColumnLayout {
        id: form
        visible: view.primary
        x: (viewport.width - width) / 2
        y: Math.max(0, (viewport.height - implicitHeight) / 2)
        width: Math.min(380, viewport.width - 48)
        spacing: view.compact ? 12 : 18
        property bool otherUser: controller.users.length === 0
        Text {
            visible: !view.compact
            text: "Rise and/or shine."
            opacity: view.entranceOpacity(0)
            Layout.fillWidth: true
            font { family: "Inter"; pixelSize: 32; weight: Font.Medium }
            color: "#f5f3fa"
            Layout.bottomMargin: 8
            horizontalAlignment: Text.AlignHCenter
        }
        ComboBox {
            id: accounts
            opacity: view.entranceOpacity(90)
            HoverHandler {
                enabled: accounts.enabled
                cursorShape: Qt.PointingHandCursor
            }
            visible: !form.otherUser
            Layout.fillWidth: true
            implicitHeight: view.compact ? 56 : 64
            model: controller.users
            textRole: "label"
            Accessible.name: "Account"
            font { family: "Inter"; pixelSize: 19; weight: Font.Medium }
            palette { text: "#e0def4"; buttonText: "#e0def4"; button: "#252832"; base: "#252832"; highlight: "#645373"; highlightedText: "#ffffff" }
            leftPadding: 22
            rightPadding: 60
            indicator: Image {
                x: accounts.width - width - 20
                y: (accounts.height - height) / 2
                width: 24
                height: 24
                source: Theme.chevron
                sourceSize: Qt.size(48, 48)
                opacity: accounts.hovered || accounts.popup.visible ? 0.95 : 0.65
                rotation: accounts.popup.visible ? 180 : 0
                Behavior on opacity { NumberAnimation { duration: 120 } }
                Behavior on rotation { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
            }
            contentItem: Text {
                text: accounts.displayText
                font: accounts.font
                color: "#f5f3fa"
                renderType: Text.QtRendering
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight
            }
            background: GlassSurface {
                backdrop: blurredBackdrop
                highlighted: accounts.hovered
                pressed: accounts.down
                focused: accounts.visualFocus
            }
            delegate: ItemDelegate {
                id: accountOption
                HoverHandler {
                    enabled: accountOption.enabled
                    cursorShape: Qt.PointingHandCursor
                }
                required property var modelData
                required property int index
                width: accounts.width - 12
                height: 56
                leftPadding: 16
                text: modelData.label
                font: accounts.font
                highlighted: accounts.highlightedIndex === index
                contentItem: Text {
                    text: parent.text
                    font: accounts.font
                    color: "#f0eaf8"
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideRight
                }
                background: Rectangle {
                    radius: 8
                    color: parent.highlighted ? "#496e598d" : "transparent"
                }
            }
            popup: Popup {
                y: accounts.height + 6
                width: accounts.width
                padding: 6
                implicitHeight: Math.min(contentItem.implicitHeight + 12, 240)
                background: GlassSurface { backdrop: blurredBackdrop; highlighted: true }
                contentItem: ListView {
                    clip: true
                    implicitHeight: contentHeight
                    model: accounts.popup.visible ? accounts.delegateModel : null
                    currentIndex: accounts.highlightedIndex
                    ScrollIndicator.vertical: ScrollIndicator {}
                }
            }
            onActivated: auth.selectUser(controller.users[currentIndex].name)
        }
        GreeterField {
            id: username
            opacity: view.entranceOpacity(90)
            backdrop: blurredBackdrop
            visible: form.otherUser
            Layout.fillWidth: true
            placeholderText: "Username"
            Accessible.name: "Username"
            onAccepted: auth.selectUser(text)
            Component.onCompleted: if (form.otherUser && view.primary) forceActiveFocus()
        }
        Text {
            visible: auth.waiting && !view.compact && !view.passwordPrompt
            text: auth.prompt
            opacity: view.entranceOpacity(180)
            color: "#c8c4d6"
            font { family: "Inter"; pixelSize: 14 }
            Layout.leftMargin: 4
        }
        GreeterField {
            id: response
            opacity: view.entranceOpacity(180)
            backdrop: blurredBackdrop
            Layout.fillWidth: true
            visible: auth.waiting || auth.busy
            enabled: auth.waiting
            implicitHeight: view.compact ? 56 : 64
            placeholderText: view.compact && !view.passwordPrompt ? auth.prompt : ""
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
                    if (auth.waiting && view.primary && pageFade.interactive && pageFade.displayedPage === "") {
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
            opacity: view.entranceOpacity(270)
            backdrop: blurredBackdrop
            Layout.fillWidth: true
            implicitHeight: view.compact ? 56 : 64
            onActiveFocusChanged: if (activeFocus) view.reveal(signIn)
            primary: true
            text: auth.busy ? "Signing in…" : "Sign in"
            enabled: !auth.busy && (auth.waiting || (form.otherUser && username.text.trim() !== ""))
            dimmed: auth.busy || !(auth.waiting || (form.otherUser && username.text.trim() !== ""))
            onClicked: {
                if (auth.waiting) auth.submit(response.text);
                else auth.selectUser(username.text);
            }
        }
    }
    }
    ColumnLayout {
        visible: view.primary && pageFade.displayedPage !== ""
        opacity: pageFade.contentOpacity
        enabled: pageFade.interactive
        anchors.centerIn: parent
        width: Math.min(320, parent.width - 48)
        spacing: 16
        GreeterButton {
            backdrop: blurredBackdrop
            Layout.fillWidth: true
            text: "Restart"
            primary: true
            dimmed: false
            onClicked: controller.confirmPower("reboot")
        }
        GreeterButton {
            backdrop: blurredBackdrop
            Layout.fillWidth: true
            text: "Shut down"
            primary: true
            dimmed: false
            onClicked: controller.confirmPower("poweroff")
        }
        GreeterButton {
            id: cancelPower
            backdrop: blurredBackdrop
            Layout.fillWidth: true
            Layout.topMargin: 8
            text: "Cancel"
            dimmed: false
            onClicked: controller.powerMenuOpen = false
            Keys.onEscapePressed: controller.powerMenuOpen = false
        }
    }
    RowLayout {
        opacity: view.entranceOpacity(360) * pageFade.contentOpacity
        visible: view.primary && pageFade.displayedPage === ""
        enabled: pageFade.interactive
        anchors { bottom: parent.bottom; right: parent.right; margins: view.compact ? 16 : 24 }
        spacing: 8
        PowerButton { text: "Power"; symbol: "power"; onClicked: { response.clear(); controller.powerMenuOpen = true; } }
    }
}
