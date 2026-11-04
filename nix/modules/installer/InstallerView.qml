import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import QtQuick.Window
import Quickshell
import Ohmansy.Ui

Item {
    id: view
    required property var controller
    property string page: "welcome"
    property var selected: null
    property bool details: false
    property bool failedGraphics: false
    property int quip: 0
    readonly property bool animated: Quickshell.env("OHMANSY_GREETER_STATIC") !== "1"
    readonly property bool narrow: width < 900
    readonly property var stages: ["prepare", "partition", "format", "configure", "install", "finish", "done"]
    readonly property int stageIndex: Math.max(0, stages.indexOf(controller.state.stage || "prepare"))
    readonly property var stageNames: ({prepare: "Checking the landing zone", partition: "Making room for a new life", format: "Fresh filesystem. Fresh delusions.", configure: "Giving this computer an identity", install: "Moving in. Bringing the whole desktop.", finish: "Tucking in the last few bytes", done: "The computer is ready for its human"})
    readonly property var quips: ["Teaching the pixels to behave. Results inconclusive.", "A reasonable operating system. An unreasonable amount of purple.", "Your internet connection has been respectfully excluded.", "Installing the desktop. Not a subscription to the desktop.", "The gremlins are arranging the furniture.", "Still working. The drama is purely decorative."]
    readonly property var headings: ({welcome: "A new life.\nFor this\ncomputer.", disks: "Choose your\nlanding zone.", confirm: "One last\nvery serious\nquestion.", progress: "Do not feed\nthe installer.", done: "It lives.\nIT LIVES.", failed: "Well.\nThat was not\nthe plan."})
    readonly property var captions: ({welcome: "An offline desktop installation.\nA small, tasteful act of computer possession.", disks: "Pick one whole disk. We’ll make it home.\nEverything on that disk will be erased.", confirm: "The jokes stop at your data.\nCheck the disk. Read the warning. Mean it.", progress: "The actual work is happening locally.\nThe theatrics are complimentary.", done: "Ohmansy has moved in.\nYou get to be the interesting part now.", failed: "The installer stopped.\nYour next move should be informed, not heroic."})
    function go(next) { controller.error = ""; page = next; details = false; }
    function choose(disk) { selected = disk; confirmation.clear(); }
    function reveal(item) {
        if (!item || !item.activeFocus) return;
        let ancestor = item;
        while (ancestor && ancestor !== content) ancestor = ancestor.parent;
        if (!ancestor) return;
        ancestor = item;
        while (ancestor && ancestor !== content) {
            if (ancestor === logPane) { item = logPane; break; }
            ancestor = ancestor.parent;
        }
        const point = item.mapToItem(content, 0, 0);
        const top = content.y + point.y;
        if (top + item.height > scroll.contentY + scroll.height) scroll.contentY = Math.max(0, top + item.height - scroll.height + 16);
        else if (top < scroll.contentY) scroll.contentY = Math.max(0, top - 16);
        scroll.contentY = Math.min(scroll.contentY, Math.max(0, scroll.contentHeight - scroll.height));
    }
    Connections {
        target: view.Window.window
        function onActiveFocusItemChanged() { Qt.callLater(() => view.reveal(view.Window.window.activeFocusItem)); }
    }
    function start() {
        if (!selected || confirmation.text !== "ERASE " + selected.path) return;
        controller.request("start", {device: selected.path, token: selected.token, hostname: hostname.text.trim(), confirmation: confirmation.text});
    }
    Connections {
        target: controller
        function onStateChanged() {
            const status = controller.state.status;
            if (status === "running") view.page = "progress";
            else if (status === "done") view.page = "done";
            else if (status === "failed") view.page = "failed";
        }
        function onDisksChanged() {
            if (view.selected && !controller.disks.some(d => d.token === view.selected.token)) {
                view.selected = null;
                confirmation.clear();
            }
        }
    }
    Timer { interval: 7000; running: view.page === "progress" && view.animated; repeat: true; onTriggered: view.quip = (view.quip + 1) % view.quips.length }
    FadeSwitch {
        id: transition
        requestedPage: view.page
        displayedPage: "welcome"
        animated: view.animated
        onSettled: {
            scroll.contentY = 0;
            if (displayedPage === "confirm") confirmation.forceActiveFocus();
            else if (displayedPage === "welcome") welcomeButton.forceActiveFocus();
        }
    }
    Item {
        id: background
        anchors.fill: parent
        Rectangle { anchors.fill: parent; gradient: Gradient { GradientStop { position: 0; color: "#101320" } GradientStop { position: 1; color: "#302646" } } }
        Loader {
            id: ribbons
            anchors.fill: parent
            active: view.animated && !view.failedGraphics && GraphicsInfo.api === GraphicsInfo.OpenGL
            source: active ? (Quickshell.env("OHMANSY_RIBBONS") || "file:///etc/ohmansy/greeter/scene/Ribbons.qml") : ""
        }
        Connections { target: ribbons.item; function onFailedChanged() { if (ribbons.item && ribbons.item.failed) view.failedGraphics = true; } }
        Rectangle { anchors.fill: parent; color: "#68101420" }
    }
    ShaderEffectSource { id: texture; anchors.fill: parent; sourceItem: GraphicsInfo.api !== GraphicsInfo.Software ? background : null; textureSize: Qt.size(Math.max(1, width / 2), Math.max(1, height / 2)); visible: false }
    MultiEffect {
        id: blur
        anchors.fill: parent; source: texture; visible: false
        blurEnabled: true; blurMax: 32; blur: 1; autoPaddingEnabled: false
        layer.enabled: GraphicsInfo.api !== GraphicsInfo.Software
        property string layoutRevision: [view.width, view.height, scroll.contentY, transition.displayedPage, controller.disks.length, view.details].join(":")
    }
    RowLayout {
        anchors { top: parent.top; left: parent.left; right: parent.right; margins: view.narrow ? 22 : 36 }
        Text { text: "ohmansy"; color: "#f5f0ff"; font { family: Theme.fontFamily; pixelSize: 24; weight: Font.Bold; letterSpacing: -0.6 } }
        Text { visible: !view.narrow; text: " /  DEPARTMENT OF NEW BEGINNINGS"; color: "#b9abc9"; font { pixelSize: 10; letterSpacing: 1.6 } }
        Item { Layout.fillWidth: true }
        Rectangle {
            implicitWidth: badge.implicitWidth + 24; implicitHeight: 30; radius: 15; color: "#2227cdb2"; border.color: "#504ce2c0"
            Text { id: badge; anchors.centerIn: parent; text: "●  100% OFFLINE"; color: "#9cf0d5"; font { pixelSize: 10; weight: Font.DemiBold; letterSpacing: 1 } }
        }
    }
    Flickable {
        id: scroll
        anchors { fill: parent; leftMargin: view.narrow ? 22 : 48; rightMargin: view.narrow ? 22 : 48; topMargin: 100; bottomMargin: 48 }
        contentHeight: Math.max(height, content.implicitHeight + 24)
        boundsBehavior: Flickable.StopAtBounds; clip: true
        ScrollBar.vertical: ScrollBar {}
        GridLayout {
            id: content
            width: Math.min(1160, scroll.width)
            x: (scroll.width - width) / 2
            y: Math.max(12, (scroll.height - implicitHeight) / 2)
            columns: view.narrow ? 1 : 2
            columnSpacing: 56; rowSpacing: 28
            opacity: transition.contentOpacity
            enabled: transition.interactive
            ColumnLayout {
                Layout.fillWidth: true; Layout.preferredWidth: 430; Layout.alignment: Qt.AlignTop
                spacing: 24
                Text { text: ({welcome: "01 / THE INVITATION", disks: "02 / THE DESTINATION", confirm: "03 / THE POINT OF NO RETURN", progress: "04 / CONTROLLED CHAOS", done: "05 / A NEW BEGINNING", failed: "PAUSE / NOT A DISAPPEARING ACT"})[transition.displayedPage]; color: "#f1b8cb"; font { pixelSize: 10; letterSpacing: 1.7; weight: Font.DemiBold } }
                Text { Layout.fillWidth: true; text: view.headings[transition.displayedPage] || ""; color: "#f5f0ff"; font { family: Theme.fontFamily; pixelSize: view.narrow ? 42 : 62; weight: Font.Bold; letterSpacing: -2.5 } lineHeight: 0.96; wrapMode: Text.WordWrap }
                Text { Layout.fillWidth: true; text: view.captions[transition.displayedPage] || ""; color: "#c7bdd8"; font { family: Theme.fontFamily; pixelSize: 17 } lineHeight: 1.3; wrapMode: Text.WordWrap }
                Rectangle { visible: !view.narrow; Layout.topMargin: 8; width: 56; height: 3; radius: 1.5; color: "#c9a0ff" }
                Text { visible: !view.narrow; text: "NO CLOUD. NO DOWNLOADS.\nJUST A COMPUTER GETTING ITS ACT TOGETHER."; color: "#998daa"; font { pixelSize: 10; letterSpacing: 1 } lineHeight: 1.5 }
            }
            ColumnLayout {
                Layout.fillWidth: true; Layout.preferredWidth: 540; spacing: 16
                ColumnLayout {
                    visible: transition.displayedPage === "welcome"; Layout.fillWidth: true; spacing: 18
                    Text { text: "THE PLAN, ALLEGEDLY"; color: "#cab5e5"; font { pixelSize: 11; letterSpacing: 1.4 } }
                    Repeater {
                        model: [{n: "01", title: "Pick a disk", subtitle: "One whole disk. A fresh start. Nothing left behind."}, {n: "02", title: "Install the good stuff", subtitle: "The desktop is already on this USB. No downloads."}, {n: "03", title: "Meet your new computer", subtitle: "Boot from the disk. Create your account. Cause a little joy."}]
                        RowLayout {
                            required property var modelData
                            Layout.fillWidth: true; spacing: 18
                            Rectangle { width: 46; height: 46; radius: 14; color: "#26b795e6"; Text { anchors.centerIn: parent; text: modelData.n; color: "#e1cbff"; font { pixelSize: 16; weight: Font.Bold } } }
                            ColumnLayout { Layout.fillWidth: true; spacing: 5
                                Text { Layout.fillWidth: true; text: modelData.title; color: "#f5f0ff"; font { pixelSize: 20; weight: Font.DemiBold } wrapMode: Text.WordWrap }
                                Text { Layout.fillWidth: true; text: modelData.subtitle; color: "#bdb1cd"; font.pixelSize: 14; wrapMode: Text.WordWrap }
                            }
                        }
                    }
                    Text { Layout.fillWidth: true; Layout.topMargin: 12; text: "This installer erases the disk you choose. It does not install alongside another operating system."; color: "#f2c0cd"; font.pixelSize: 14; wrapMode: Text.WordWrap }
                    GlassButton { id: welcomeButton; Layout.fillWidth: true; backdrop: blur; primary: true; text: "Let’s make questionable history."; onClicked: { view.go("disks"); controller.request("disks"); } }
                }
                ColumnLayout {
                    visible: transition.displayedPage === "disks"; Layout.fillWidth: true; spacing: 12
                    RowLayout {
                        Layout.fillWidth: true
                        Text { Layout.fillWidth: true; text: "AVAILABLE DISKS"; color: "#cab5e5"; font { pixelSize: 11; letterSpacing: 1.4 } }
                        GlassButton { backdrop: blur; text: "Refresh"; implicitHeight: 40; font.pixelSize: 13; enabled: !controller.busy; onClicked: controller.request("disks") }
                    }
                    Repeater {
                        model: controller.disks
                        Button {
                            id: diskButton
                            required property var modelData
                            readonly property bool chosen: view.selected !== null && view.selected.token === modelData.token
                            Layout.fillWidth: true; implicitHeight: 106; padding: 18; hoverEnabled: true
                            Accessible.name: modelData.model + ", " + (modelData.size / 1073741824).toFixed(1) + " GiB, " + modelData.path
                            onClicked: view.choose(modelData)
                            background: Rectangle { radius: 20; color: diskButton.chosen ? "#523e5e80" : diskButton.hovered ? "#363b344d" : "#223b344d"; border.width: diskButton.chosen || diskButton.visualFocus ? 2 : 1; border.color: diskButton.chosen ? "#bda0f1" : diskButton.visualFocus ? "#e9daff" : "#48685a7c"; Behavior on color { ColorAnimation { duration: 150 } } }
                            contentItem: RowLayout {
                                spacing: 15
                                Rectangle { width: 40; height: 44; radius: 10; color: "#3bc4a6ed"; Rectangle { width: 24; height: 3; radius: 1; anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 10 } color: "#dbc6fa" } }
                                ColumnLayout { Layout.fillWidth: true; spacing: 6
                                    Text { Layout.fillWidth: true; text: modelData.model; color: "#f5f0ff"; font { pixelSize: 17; weight: Font.DemiBold } elide: Text.ElideRight }
                                    Text { text: (modelData.size / 1073741824).toFixed(1) + " GiB  ·  " + modelData.path; color: "#c6b6d8"; font.pixelSize: 13 }
                                }
                                Text { text: diskButton.chosen ? "●" : "○"; color: "#d5b7ff"; font.pixelSize: 25 }
                            }
                        }
                    }
                    Text { visible: controller.disks.length === 0; Layout.fillWidth: true; text: controller.busy ? "Looking for somewhere to land…" : "No available disk found. Attach a writable disk of at least 24 GiB, then refresh. The live USB and disks currently in use are excluded."; color: "#c7bdd8"; font.pixelSize: 15; wrapMode: Text.WordWrap }
                    Text { text: "COMPUTER NAME"; Layout.topMargin: 8; color: "#cab5e5"; font { pixelSize: 11; letterSpacing: 1.4 } }
                    GlassField { id: hostname; Layout.fillWidth: true; backdrop: blur; text: "ohmansy"; maximumLength: 63; Accessible.name: "Computer name"; onAccepted: if (view.selected && /^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$/.test(text)) view.go("confirm") }
                    Text { text: "Lowercase letters, numbers, and hyphens. Make it weird. Make it pronounceable. Pick one."; Layout.fillWidth: true; color: "#b9abc9"; font.pixelSize: 12; wrapMode: Text.WordWrap }
                    GlassButton { Layout.fillWidth: true; backdrop: blur; primary: true; text: "This is the place."; enabled: !!view.selected && /^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$/.test(hostname.text) && !controller.busy; onClicked: view.go("confirm") }
                    GlassButton { Layout.fillWidth: true; backdrop: blur; implicitHeight: 42; text: "Back"; onClicked: view.go("welcome") }
                }
                ColumnLayout {
                    visible: transition.displayedPage === "confirm"; Layout.fillWidth: true; spacing: 16
                    Rectangle {
                        Layout.fillWidth: true; implicitHeight: warning.implicitHeight + 36; radius: 20; color: "#30ec7891"; border.color: "#8ce897ad"
                        ColumnLayout { id: warning; anchors { left: parent.left; right: parent.right; top: parent.top; margins: 18 } spacing: 10
                            Text { Layout.fillWidth: true; text: "ALL DATA ON THIS DISK WILL BE ERASED"; color: "#ffd2dc"; font { pixelSize: 13; weight: Font.Bold } wrapMode: Text.WordWrap }
                            Text { Layout.fillWidth: true; text: view.selected ? view.selected.model + "\n" + (view.selected.size / 1073741824).toFixed(1) + " GiB  ·  " + view.selected.path : ""; color: "#fff0f4"; font { pixelSize: 21; weight: Font.DemiBold } wrapMode: Text.WordWrap }
                            Text { Layout.fillWidth: true; text: "Files, partitions, and existing operating systems will be deleted. This cannot be undone. Back up anything you need before continuing."; color: "#f0c3d1"; font.pixelSize: 14; wrapMode: Text.WordWrap }
                        }
                    }
                    Text { Layout.fillWidth: true; text: "To confirm, type " + (view.selected ? "ERASE " + view.selected.path : "the disk confirmation") + " below."; color: "#e8dcf4"; font.pixelSize: 15; wrapMode: Text.WordWrap }
                    GlassField { id: confirmation; Layout.fillWidth: true; backdrop: blur; placeholderText: "Type the confirmation exactly"; Accessible.name: "Erase confirmation"; maximumLength: 200; onAccepted: view.start() }
                    GlassButton { Layout.fillWidth: true; backdrop: blur; primary: true; text: "Erase disk and install Ohmansy"; enabled: !!view.selected && confirmation.text === "ERASE " + view.selected.path && !controller.busy; onClicked: view.start() }
                    GlassButton { Layout.fillWidth: true; backdrop: blur; implicitHeight: 44; text: "Back. I have questions."; enabled: !controller.busy; onClicked: { confirmation.clear(); view.go("disks"); controller.request("disks"); } }
                }
                ColumnLayout {
                    visible: transition.displayedPage === "progress"; Layout.fillWidth: true; spacing: 20
                    Item {
                        Layout.alignment: Qt.AlignHCenter; width: 142; height: 142
                        Rectangle { anchors.centerIn: parent; width: 118; height: 118; radius: 59; color: "#1bb48ae0"; border.color: "#60d1b5f5"; border.width: 1 }
                        Item { anchors.fill: parent
                            RotationAnimation on rotation { from: 0; to: 360; duration: 6500; loops: Animation.Infinite; running: view.page === "progress" && view.animated }
                            Rectangle { anchors { horizontalCenter: parent.horizontalCenter; top: parent.top } width: 14; height: 14; radius: 7; color: "#dab5ff" }
                        }
                        Text { anchors.centerIn: parent; text: "oh."; color: "#f6ecff"; font { pixelSize: 42; weight: Font.Bold; letterSpacing: -2 } }
                    }
                    Text { Layout.fillWidth: true; text: view.stageNames[controller.state.stage] || "Preparing the installation"; color: "#f5f0ff"; font { pixelSize: 24; weight: Font.DemiBold } wrapMode: Text.WordWrap; horizontalAlignment: Text.AlignHCenter; Accessible.role: Accessible.StaticText }
                    RowLayout {
                        Layout.fillWidth: true; spacing: 6
                        Repeater { model: 6; Rectangle { required property int index; Layout.fillWidth: true; height: 5; radius: 2.5; color: index < view.stageIndex ? "#bba1e8" : index === view.stageIndex ? "#f0dcff" : "#384053" } }
                    }
                    Text { Layout.fillWidth: true; text: "STAGE " + Math.min(6, view.stageIndex + 1) + " OF 6  ·  " + (controller.state.device || ""); color: "#b9abc9"; font { pixelSize: 11; letterSpacing: 1 } horizontalAlignment: Text.AlignHCenter }
                    Text { Layout.fillWidth: true; text: view.quips[view.quip]; color: "#d9c0ee"; font.pixelSize: 16; wrapMode: Text.WordWrap; horizontalAlignment: Text.AlignHCenter }
                    Text { Layout.fillWidth: true; text: "Keep this computer powered on. Copying the system can take several minutes. Closing this window won’t cancel installation; reopen Install Ohmansy to return here."; color: "#b9abc9"; font.pixelSize: 13; wrapMode: Text.WordWrap }
                }
                ColumnLayout {
                    visible: transition.displayedPage === "done"; Layout.fillWidth: true; spacing: 18
                    Text { text: "✦  SUCCESSFULLY SUMMONED"; color: "#a4efd5"; font { pixelSize: 12; letterSpacing: 1.2; weight: Font.Bold } }
                    Text { Layout.fillWidth: true; text: (controller.state.hostname || "Your computer") + " is ready."; color: "#f5f0ff"; font { pixelSize: 30; weight: Font.DemiBold } wrapMode: Text.WordWrap }
                    Text { Layout.fillWidth: true; text: "1. Shut down this computer.\n2. Remove the installation USB or ISO.\n3. Start it again and create your account."; color: "#ddd0e9"; font.pixelSize: 18; lineHeight: 1.6; wrapMode: Text.WordWrap }
                    Text { Layout.fillWidth: true; text: "Your desktop is installed. Your main-character era is pending first boot."; color: "#c6abd9"; font.pixelSize: 15; wrapMode: Text.WordWrap }
                    GlassButton { Layout.fillWidth: true; backdrop: blur; primary: true; text: "Shut down. It’s time."; enabled: !controller.busy; onClicked: controller.request("shutdown") }
                    GlassButton { Layout.fillWidth: true; backdrop: blur; implicitHeight: 44; text: "Stay in the live desktop"; onClicked: Qt.quit() }
                }
                ColumnLayout {
                    visible: transition.displayedPage === "failed"; Layout.fillWidth: true; spacing: 16
                    Text { Layout.fillWidth: true; text: controller.state.error || "Installation could not finish."; color: "#ffd0dd"; font { pixelSize: 20; weight: Font.DemiBold } wrapMode: Text.WordWrap }
                    Text { Layout.fillWidth: true; text: controller.state.destructive ? "The selected disk may contain a partial installation. Do not erase it again just to retry. Open the log below and keep this live session running while you investigate." : "No disk changes were made. You can return to disk selection and try again."; color: "#d4c5e1"; font.pixelSize: 15; wrapMode: Text.WordWrap }
                    GlassButton { visible: !controller.state.destructive; Layout.fillWidth: true; backdrop: blur; text: "Back to disk selection"; onClicked: { view.go("disks"); controller.request("disks"); } }
                    GlassButton { Layout.fillWidth: true; backdrop: blur; text: "Return to the live desktop"; onClicked: Qt.quit() }
                }
                Text { visible: !!controller.error; Layout.fillWidth: true; text: controller.error; color: "#ffc5d6"; font.pixelSize: 14; wrapMode: Text.WordWrap; Accessible.role: Accessible.AlertMessage }
                GlassButton { visible: ["progress", "done", "failed"].includes(transition.displayedPage); Layout.fillWidth: true; backdrop: blur; implicitHeight: 40; font.pixelSize: 13; text: view.details ? "Hide the machinery" : "Show installation log"; onClicked: view.details = !view.details }
                ScrollView {
                    id: logPane
                    visible: view.details; Layout.fillWidth: true; Layout.preferredHeight: 220; clip: true
                    TextArea { text: controller.state.log || "Waiting for installer output…"; readOnly: true; selectByMouse: true; wrapMode: TextEdit.WrapAnywhere; color: "#ddd1ec"; font { family: "monospace"; pixelSize: 11 } background: Rectangle { color: "#b8101220"; radius: 12 } Accessible.name: "Installation log" }
                }
                Text { visible: view.details; Layout.fillWidth: true; text: "Full log: /var/log/ohmansy-install.log · Save it before shutting down the live session."; color: "#b9abc9"; font.pixelSize: 11; wrapMode: Text.WordWrap }
            }
        }
    }
    Text { anchors { bottom: parent.bottom; left: parent.left; margins: 22 } text: "OHMANSY INSTALLER   /   LOCAL BY DESIGN. DRAMATIC BY CHOICE."; color: "#9889a7"; font { pixelSize: 9; letterSpacing: 1 } visible: width < view.width - 44 }
}
