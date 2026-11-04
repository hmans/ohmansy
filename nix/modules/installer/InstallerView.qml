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
    property bool eraseAcknowledged: false
    onPageChanged: eraseAcknowledged = false
    onSelectedChanged: eraseAcknowledged = false
    property bool details: false
    property bool failedGraphics: false
    readonly property bool animated: Quickshell.env("OHMANSY_GREETER_STATIC") !== "1"
    readonly property bool narrow: width < 900
    readonly property var stages: ["prepare", "partition", "format", "configure", "install", "finish", "done"]
    readonly property int stageIndex: Math.max(0, stages.indexOf(controller.state.stage || "prepare"))
    readonly property var stageNames: ({prepare: "Checking the disk", partition: "Partitioning the disk", format: "Creating filesystems", configure: "Configuring the system", install: "Copying the system", finish: "Finishing installation", done: "Installation complete"})
    readonly property var headings: ({welcome: "Welcome to\nohmansy.", disks: "Choose\na disk.", confirm: "Ready to\ninstall?", progress: "Installing\nohmansy.", done: "All done.", failed: "Installation\nfailed."})
    readonly property var captions: ({welcome: "Let’s install your new desktop.\nNo internet connection needed.", disks: "Everything on the selected disk will be erased.", confirm: "Check that you’ve selected the right disk before continuing.", progress: "This may take a few minutes.", done: "Restart from the installed disk to set up your account.", failed: "Check the error and installation log below."})
    function go(next) { controller.error = ""; page = next; details = false; }
    function choose(disk) { selected = disk; eraseAcknowledged = false; }
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
        if (page !== "confirm" || !transition.interactive || controller.busy || !selected || !eraseAcknowledged) return;
        eraseAcknowledged = false;
        controller.request("start", {device: selected.path, token: selected.token, hostname: hostname.text.trim(), confirmation: "ERASE " + selected.path});
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
                view.eraseAcknowledged = false;
            }
        }
    }
    FadeSwitch {
        id: transition
        requestedPage: view.page
        displayedPage: "welcome"
        animated: view.animated
        onSettled: {
            scroll.contentY = 0;
            if (displayedPage === "confirm") acknowledgement.forceActiveFocus();
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
        Text { visible: !view.narrow; text: " /  installer"; color: "#b9abc9"; font { pixelSize: 10; letterSpacing: 1.6 } }
        Item { Layout.fillWidth: true }
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
                Text { Layout.fillWidth: true; text: view.headings[transition.displayedPage] || ""; color: "#f5f0ff"; font { family: Theme.fontFamily; pixelSize: view.narrow ? 42 : 62; weight: Font.Bold; letterSpacing: -2.5 } lineHeight: 0.96; wrapMode: Text.WordWrap }
                Text { Layout.fillWidth: true; text: view.captions[transition.displayedPage] || ""; color: "#c7bdd8"; font { family: Theme.fontFamily; pixelSize: 17 } lineHeight: 1.3; wrapMode: Text.WordWrap }
                Rectangle { visible: !view.narrow; Layout.topMargin: 8; width: 56; height: 3; radius: 1.5; color: "#c9a0ff" }
            }
            ColumnLayout {
                Layout.fillWidth: true; Layout.preferredWidth: 540; spacing: 16
                ColumnLayout {
                    visible: transition.displayedPage === "welcome"; Layout.fillWidth: true; spacing: 18
                    Text { text: "GETTING STARTED"; color: "#cab5e5"; font { pixelSize: 11; letterSpacing: 1.4 } }
                    Repeater {
                        model: [{n: "01", title: "Pick a disk", subtitle: "All data on the selected disk will be erased."}, {n: "02", title: "Install ohmansy", subtitle: "Everything needed is included on the installation media."}, {n: "03", title: "Create your account", subtitle: "Restart after installation to set up your account."}]
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
                    GlassButton { id: welcomeButton; Layout.fillWidth: true; backdrop: blur; actionRole: "primary"; text: "Get started"; onClicked: { view.go("disks"); controller.request("disks"); } }
                }
                ColumnLayout {
                    visible: transition.displayedPage === "disks"; Layout.fillWidth: true; spacing: 12
                    RowLayout {
                        Layout.fillWidth: true
                        Text { Layout.fillWidth: true; text: "AVAILABLE DISKS"; color: "#cab5e5"; font { pixelSize: 11; letterSpacing: 1.4 } }
                        GlassButton { actionRole: "secondary"; backdrop: blur; text: "Refresh"; implicitHeight: 40; font.pixelSize: 13; enabled: !controller.busy; onClicked: controller.request("disks") }
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
                    Text { visible: controller.disks.length === 0; Layout.fillWidth: true; text: controller.busy ? "Looking for disks…" : "No available disk found. Attach a writable disk of at least 24 GiB, then refresh. The live USB and disks currently in use are excluded."; color: "#c7bdd8"; font.pixelSize: 15; wrapMode: Text.WordWrap }
                    Text { text: "COMPUTER NAME"; Layout.topMargin: 8; color: "#cab5e5"; font { pixelSize: 11; letterSpacing: 1.4 } }
                    GlassField { id: hostname; Layout.fillWidth: true; backdrop: blur; text: "ohmansy"; maximumLength: 63; Accessible.name: "Computer name"; onAccepted: if (view.selected && /^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$/.test(text)) view.go("confirm") }
                    Text { text: "Use lowercase letters, numbers, and hyphens."; Layout.fillWidth: true; color: "#b9abc9"; font.pixelSize: 12; wrapMode: Text.WordWrap }
                    GlassButton { Layout.fillWidth: true; backdrop: blur; actionRole: "primary"; text: "Continue"; enabled: !!view.selected && /^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$/.test(hostname.text) && !controller.busy; onClicked: view.go("confirm") }
                    GlassButton { actionRole: "return"; Layout.fillWidth: true; backdrop: blur; implicitHeight: 42; text: "Back"; onClicked: view.go("welcome") }
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
                    CheckBox {
                        id: acknowledgement
                        Layout.fillWidth: true
                        text: "I understand that all data on this disk will be erased."
                        checked: view.eraseAcknowledged
                        enabled: !!view.selected && !controller.busy
                        onToggled: view.eraseAcknowledged = checked
                        padding: 12; spacing: 12
                        indicator: Rectangle {
                            x: acknowledgement.leftPadding
                            y: (acknowledgement.height - height) / 2
                            width: 24; height: 24; radius: 6
                            color: acknowledgement.checked ? "#bda0f1" : "#223b344d"
                            border.color: acknowledgement.visualFocus ? "#ffffff" : "#bda0f1"
                            border.width: acknowledgement.visualFocus ? 2 : 1
                            Text { anchors.centerIn: parent; text: "✓"; visible: acknowledgement.checked; color: "#20172e"; font.pixelSize: 18 }
                        }
                        contentItem: Text {
                            text: acknowledgement.text
                            leftPadding: acknowledgement.indicator.width + acknowledgement.spacing
                            color: "#e8dcf4"; font.pixelSize: 15; wrapMode: Text.WordWrap
                        }
                        background: Rectangle { radius: 12; color: acknowledgement.hovered ? "#223b344d" : "transparent"; border.color: acknowledgement.visualFocus ? "#bda0f1" : "transparent" }
                    }
                    GlassButton { Layout.fillWidth: true; backdrop: blur; actionRole: "primary"; text: "Erase disk and install ohmansy"; enabled: !!view.selected && view.eraseAcknowledged && !controller.busy; onClicked: view.start() }
                    GlassButton { actionRole: "return"; Layout.fillWidth: true; backdrop: blur; implicitHeight: 44; text: "Back"; enabled: !controller.busy; onClicked: { view.go("disks"); controller.request("disks"); } }
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
                    Text { Layout.fillWidth: true; text: "Keep this computer powered on. Copying the system can take several minutes. Closing this window won’t cancel installation; reopen Install ohmansy to return here."; color: "#b9abc9"; font.pixelSize: 13; wrapMode: Text.WordWrap }
                }
                ColumnLayout {
                    visible: transition.displayedPage === "done"; Layout.fillWidth: true; spacing: 18
                    Text { text: "✦  INSTALLATION COMPLETE"; color: "#a4efd5"; font { pixelSize: 12; letterSpacing: 1.2; weight: Font.Bold } }
                    Text { Layout.fillWidth: true; text: (controller.state.hostname || "Your computer") + " is ready."; color: "#f5f0ff"; font { pixelSize: 30; weight: Font.DemiBold } wrapMode: Text.WordWrap }
                    Text { Layout.fillWidth: true; text: "1. Shut down this computer.\n2. Remove the installation USB or ISO.\n3. Start it again and create your account."; color: "#ddd0e9"; font.pixelSize: 18; lineHeight: 1.6; wrapMode: Text.WordWrap }
                    GlassButton { Layout.fillWidth: true; backdrop: blur; actionRole: "primary"; text: "Shut down"; enabled: !controller.busy; onClicked: controller.request("shutdown") }
                    GlassButton { actionRole: "return"; Layout.fillWidth: true; backdrop: blur; implicitHeight: 44; text: "Stay in the live desktop"; onClicked: Qt.quit() }
                }
                ColumnLayout {
                    visible: transition.displayedPage === "failed"; Layout.fillWidth: true; spacing: 16
                    Text { Layout.fillWidth: true; text: controller.state.error || "Installation could not finish."; color: "#ffd0dd"; font { pixelSize: 20; weight: Font.DemiBold } wrapMode: Text.WordWrap }
                    Text { Layout.fillWidth: true; text: controller.state.destructive ? "The selected disk may contain a partial installation. Do not erase it again just to retry. Open the log below and keep this live session running while you investigate." : "No disk changes were made. You can return to disk selection and try again."; color: "#d4c5e1"; font.pixelSize: 15; wrapMode: Text.WordWrap }
                    GlassButton { actionRole: "return"; visible: !controller.state.destructive; Layout.fillWidth: true; backdrop: blur; text: "Back to disk selection"; onClicked: { view.go("disks"); controller.request("disks"); } }
                    GlassButton { actionRole: "return"; Layout.fillWidth: true; backdrop: blur; text: "Return to the live desktop"; onClicked: Qt.quit() }
                }
                Text { visible: !!controller.error; Layout.fillWidth: true; text: controller.error; color: "#ffc5d6"; font.pixelSize: 14; wrapMode: Text.WordWrap; Accessible.role: Accessible.AlertMessage }
                GlassButton { actionRole: "secondary"; visible: ["progress", "done", "failed"].includes(transition.displayedPage); Layout.fillWidth: true; backdrop: blur; implicitHeight: 40; font.pixelSize: 13; text: view.details ? "Hide installation log" : "Show installation log"; onClicked: view.details = !view.details }
                ScrollView {
                    id: logPane
                    visible: view.details; Layout.fillWidth: true; Layout.preferredHeight: 220; clip: true
                    TextArea { text: controller.state.log || "Waiting for installer output…"; readOnly: true; selectByMouse: true; wrapMode: TextEdit.WrapAnywhere; color: "#ddd1ec"; font { family: "monospace"; pixelSize: 11 } background: Rectangle { color: "#b8101220"; radius: 12 } Accessible.name: "Installation log" }
                }
                Text { visible: view.details; Layout.fillWidth: true; text: "Full log: /var/log/ohmansy-install.log · Save it before shutting down the live session."; color: "#b9abc9"; font.pixelSize: 11; wrapMode: Text.WordWrap }
            }
        }
    }
}
