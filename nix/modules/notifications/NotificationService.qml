import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQml.Models
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Notifications
import Ohmansy.Ui as Ui
import Ohmansy.NotificationSupport

Scope {
    id: root
    property string focusedOutput: Quickshell.screens[0]?.name || ""
    property string historyOutput: ""
    property var items: []
    property var history: []
    property bool doNotDisturb: false
    property bool ready: false
    property string storageError: ""
    NotificationSupport { id: support }
    Component.onCompleted: {
        const saved = support.load();
        // QVariantList is a QML sequence, not a JavaScript Array.
        history = saved.history ? Array.from(saved.history).slice(0, 100) : [];
        doNotDisturb = saved.doNotDisturb === true;
        ready = true;
    }
    function persist() {
        if (ready && !support.save({ history: history, doNotDisturb: doNotDisturb }))
            storageError = "Could not save notification history.";
    }
    onDoNotDisturbChanged: persist()
    function remember(item) {
        const n = item.notification;
        if (!ready || !item.historyKey) return;
        if (n.transient) { forget(item.historyKey); return; }
        history = [{ key: item.historyKey, id: n.id, summary: n.summary,
            body: support.plainText(n.body), app_name: n.appName, app_icon: n.appIcon,
            urgency: n.urgency, time: Date.now() }]
            .concat(history.filter(entry => entry.key !== item.historyKey)).slice(0, 100);
        persist();
    }
    function forget(key) { history = history.filter(entry => entry.key !== key); persist(); }
    function toggleHistory() { historyOutput = historyOutput ? "" : focusedOutput; }
    NotificationServer {
        id: server
        actionsSupported: true
        bodyMarkupSupported: true
        imageSupported: true
        persistenceSupported: true
        keepOnReload: true
        onNotification: notification => notification.tracked = true
    }
    Instantiator {
        model: server.trackedNotifications
        onObjectAdded: (index, object) => root.items = root.items.concat([object])
        onObjectRemoved: (index, object) => root.items = root.items.filter(item => item !== object)
        delegate: Scope {
            id: item
            required property var modelData
            readonly property var notification: modelData
            property string historyKey: ""
            property string output: root.focusedOutput
            property bool shown: !notification.lastGeneration && !root.doNotDisturb
            property bool hovered: false
            readonly property string body: support.plainText(notification.body)
            readonly property real timeout: notification.expireTimeout < 0
                ? (notification.urgency === NotificationUrgency.Critical ? 0 : 8000)
                : notification.expireTimeout
            function refresh() {
                root.remember(item);
                shown = !root.doNotDisturb;
                expiry.stop();
                if (timeout > 0 && !hovered) expiry.start();
            }
            Component.onCompleted: Qt.callLater(() => {
                const previous = notification.lastGeneration
                    ? root.history.find(entry => entry.id === notification.id && entry.app_name === notification.appName) : null;
                historyKey = previous ? previous.key : Date.now() + "-" + notification.id;
                root.remember(item);
            })
            Connections {
                target: item.notification
                function onSummaryChanged() { item.refresh(); }
                function onBodyChanged() { item.refresh(); }
                function onHintsChanged() { item.refresh(); }
                function onExpireTimeoutChanged() { item.refresh(); }
            }
            Timer {
                id: expiry
                // Quickshell 0.3 passes the protocol's milliseconds through.
                interval: Math.max(1, item.timeout)
                running: item.timeout > 0 && !item.hovered
                onTriggered: item.notification.expire()
            }
            Connections {
                target: root
                function onDoNotDisturbChanged() { if (root.doNotDisturb) item.shown = false; }
            }
        }
    }
    IpcHandler {
        target: "notifications"
        function history(): string { return JSON.stringify(root.history); }
        function status(): string {
            return JSON.stringify({ active: server.trackedNotifications.values.map(n => ({ id: n.id, summary: n.summary })),
                popups: root.items.filter(item => item.shown).map(item => ({ id: item.notification.id, output: item.output })),
                history: root.history, doNotDisturb: root.doNotDisturb, storageError: root.storageError });
        }
        function toggleHistory(): void { root.toggleHistory(); }
        function closeHistory(): void { root.historyOutput = ""; }
        function clear(): void { root.history = []; root.persist(); }
        function setDoNotDisturb(value: bool): void { root.doNotDisturb = value; }
        // Used once when moving a running session from Mako. No actions are restored.
        function importHistory(data: string): int {
            // Wrap the array: Quickshell's CLI expands bracketed list arguments.
            const entries = JSON.parse(data).entries;
            if (!Array.isArray(entries)) return -1;
            root.history = root.history.concat(entries.slice(0, 100).map((entry, index) => ({
                key: "import-" + index, id: entry.id || 0, summary: entry.summary || "Notification",
                body: support.plainText(entry.body || ""), app_name: entry.app_name || "",
                app_icon: entry.app_icon || "", urgency: typeof entry.urgency === "number" ? entry.urgency
                    : ({ low: 0, normal: 1, critical: 2 })[entry.urgency] ?? 1, time: Date.now()
            }))).slice(0, 100);
            root.persist();
            return root.history.length;
        }
    }
    Variants {
        model: Quickshell.screens
        PanelWindow {
            id: panel
            required property var modelData
            readonly property bool historyOpen: root.historyOutput === modelData.name
            readonly property var popups: root.items.filter(item => item.shown &&
                (item.output === modelData.name || (modelData.name === root.focusedOutput &&
                    !Quickshell.screens.some(screen => screen.name === item.output)))).slice(-5).reverse()
            readonly property bool hasContent: historyOpen || popups.length > 0
            screen: modelData
            anchors { top: true; right: true }
            margins { top: 24; right: 24 }
            implicitWidth: Math.min(420, modelData.width - 48)
            implicitHeight: Math.max(1, Math.min(modelData.height - 100,
                historyOpen ? 620 : popupColumn.implicitHeight))
            exclusiveZone: 0
            color: "transparent"
            mask: Region { item: panel.hasContent ? surface : null }
            WlrLayershell.namespace: "ohmansy-notifications"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: panel.historyOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            Item {
                id: surface
                anchors.fill: parent
                visible: panel.hasContent
                ScrollView {
                    id: popupScroll
                    anchors.fill: parent
                    visible: !panel.historyOpen
                    clip: true
                    contentWidth: availableWidth
                    Column {
                        id: popupColumn
                        width: popupScroll.availableWidth
                        spacing: 12
                        Repeater {
                            model: panel.popups
                            NotificationCard {
                                required property var modelData
                                readonly property var notification: modelData.notification
                                width: popupColumn.width
                                summary: notification.summary
                                body: modelData.body
                                appName: notification.appName
                                icon: notification.appIcon
                                image: notification.image
                                urgency: notification.urgency
                                actions: notification.actions
                                actionable: actions.some(action => action.identifier === "default")
                                onHoveredChanged: modelData.hovered = hovered
                                Component.onDestruction: if (modelData) modelData.hovered = false
                                onDismissed: notification.dismiss()
                                onInvoked: action => support.invoke(action, notification.id)
                                onDefaultInvoked: {
                                    const action = actions.find(action => action.identifier === "default");
                                    if (action) support.invoke(action, notification.id);
                                }
                            }
                        }
                    }
                }
                Ui.GlassSurface { anchors.fill: parent; visible: panel.historyOpen; tint: Ui.Theme.solidSurface }
                FocusScope {
                    anchors { fill: parent; margins: 16 }
                    visible: panel.historyOpen
                    focus: panel.historyOpen
                    Keys.onEscapePressed: root.historyOutput = ""
                    ColumnLayout {
                        anchors.fill: parent
                        spacing: 12
                        RowLayout {
                            Layout.fillWidth: true
                            Text {
                                text: "Notifications"
                                Layout.fillWidth: true
                                color: Ui.Theme.text
                                font { family: Ui.Theme.fontFamily; pixelSize: 18; weight: Font.DemiBold }
                            }
                            Ui.GlassButton {
                                text: "Done"; actionRole: "return"; padding: 8; implicitHeight: 34; font.pixelSize: 13
                                onClicked: root.historyOutput = ""
                            }
                        }
                        Ui.GlassButton {
                            Layout.fillWidth: true
                            text: root.doNotDisturb ? "Do Not Disturb: on" : "Do Not Disturb: off"
                            actionRole: root.doNotDisturb ? "primary" : "secondary"
                            implicitHeight: 38; padding: 8; font.pixelSize: 13
                            onClicked: root.doNotDisturb = !root.doNotDisturb
                        }
                        Text {
                            visible: root.history.length === 0
                            text: "No notifications yet"
                            color: Ui.Theme.secondary
                            font { family: Ui.Theme.fontFamily; pixelSize: 14 }
                        }
                        ScrollView {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true
                            contentWidth: availableWidth
                            Column {
                                width: parent.width
                                spacing: 10
                                Repeater {
                                    model: root.history
                                    NotificationCard {
                                        required property var modelData
                                        width: parent.width
                                        summary: modelData.summary
                                        body: modelData.body
                                        appName: modelData.app_name
                                        icon: modelData.app_icon
                                        urgency: modelData.urgency
                                        onDismissed: root.forget(modelData.key)
                                    }
                                }
                            }
                        }
                        Text {
                            visible: root.storageError !== ""
                            text: root.storageError
                            color: Ui.Theme.secondary
                            Layout.fillWidth: true
                            wrapMode: Text.Wrap
                            font { family: Ui.Theme.fontFamily; pixelSize: 13 }
                        }
                        Ui.GlassButton {
                            text: "Clear history"; actionRole: "secondary"; padding: 8; implicitHeight: 34; font.pixelSize: 13
                            enabled: root.history.length > 0
                            onClicked: { root.history = []; root.persist(); }
                        }
                    }
                }
            }
        }
    }
}
