import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Ohmansy.Ui as Ui
import "DesktopMenus.js" as Menus

PanelWindow {
    id: launcher
    Theme { id: theme }
    required property var barWindow
    required property bool opened
    required property var niriState
    property string requestedMode: "apps"
    property string mode: requestedMode
    property string pendingAction: ""
    property var historyEntries: []
    property string notificationBody: ""
    readonly property string prompt: ({ apps: "Search applications…", windows: "Find an open window…",
        clipboard: "Search clipboard history…", notifications: "Notification history…",
        power: "Power", controls: "Desktop controls", confirm: "Confirm action" })[mode] || "Search…"
    function resetMode() {
        mode = requestedMode;
        pendingAction = "";
        notificationBody = "";
        launchError = "";
        search.clear();
        historyEntries = [];
        if (mode === "clipboard" || mode === "notifications") {
            historyQuery.running = false;
            historyQuery.queryMode = mode;
            historyQuery.command = [Quickshell.env("OHMANSY_DESKTOP"), mode === "clipboard" ? "clipboard-list" : "notifications"];
            historyQuery.running = true;
        }
        Qt.callLater(() => search.forceActiveFocus());
    }
    onRequestedModeChanged: if (opened) resetMode()
    Process {
        id: historyQuery
        property string queryMode: ""
        stdout: StdioCollector {
            onStreamFinished: {
                if (!launcher.opened || launcher.mode !== historyQuery.queryMode) return;
                try {
                    launcher.historyEntries = historyQuery.queryMode === "clipboard"
                        ? Menus.clipboardEntries(text) : Menus.notificationEntries(text);
                } catch (error) { launcher.launchError = "Could not read history."; }
            }
        }
        onExited: (code, status) => {
            if (launcher.opened && launcher.mode === queryMode && (code !== 0 || status !== 0))
                launcher.launchError = "Could not read history.";
        }
    }
    signal dismissed()
    property string launchError: ""
    property string launchingName: ""
    Process {
        id: appLaunch
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0 && exitStatus === 0) launcher.dismissed();
            else launcher.launchError = "Could not open " + launcher.launchingName + ". Try again.";
        }
    }
    property real reveal: opened ? 1 : 0
    readonly property var matches: {
        const words = search.text.trim().toLowerCase().split(/\s+/).filter(Boolean);
        const entries = mode === "apps" ? DesktopEntries.applications.values
            : mode === "windows" ? niriState.state.windows.map(w => ({ kind: "action", id: w.id,
                name: w.title || w.app_id || "Untitled window", comment: w.app_id || "",
                icon: DesktopEntries.heuristicLookup(w.app_id || "")?.icon || "application-x-executable",
                args: ["focus-window", String(w.id)] }))
            : mode === "clipboard" || mode === "notifications" ? historyEntries : Menus.entries(mode, pendingAction);
        const filtered = entries.filter(app => {
            const text = [app.name, app.genericName, app.comment, app.body, ...(app.keywords || [])].join(" ").toLowerCase();
            return words.every(word => text.includes(word));
        });
        if (mode !== "apps" && mode !== "windows") return filtered;
        return filtered.sort((a, b) => {
            const query = search.text.trim().toLowerCase();
            const aFirst = query && a.name.toLowerCase().startsWith(query) ? 0 : 1;
            const bFirst = query && b.name.toLowerCase().startsWith(query) ? 0 : 1;
            return aFirst - bFirst || a.name.localeCompare(b.name);
        });
    }
    onMatchesChanged: results.currentIndex = matches.length ? 0 : -1
    function launch(app) {
        if (!app || !opened || appLaunch.running) return;
        if (app.kind === "back") { mode = "power"; search.clear(); return; }
        if (app.confirm) { pendingAction = app.id; mode = "confirm"; search.clear(); return; }
        if (app.kind === "notification") {
            notificationBody = app.name + "\n\n" + app.body;
            return;
        }
        launchError = "";
        launchingName = app.name;
        // GIO resolves the desktop ID and handles activation, Exec codes,
        // working directories, and terminal selection.
        appLaunch.command = app.kind === "action"
            ? [Quickshell.env("OHMANSY_DESKTOP"), ...app.args]
            : [Quickshell.env("OHMANSY_APP_LAUNCHER"), "--", app.id + ".desktop"];
        appLaunch.running = true;
    }
    function moveSelection(step) {
        if (!matches.length) return;
        results.currentIndex = (results.currentIndex + step + matches.length) % matches.length;
        results.positionViewAtIndex(results.currentIndex, ListView.Contain);
    }
    onOpenedChanged: {
        if (opened) resetMode();
        else {
            historyQuery.running = false;
            historyEntries = [];
            notificationBody = "";
        }
    }
    Behavior on reveal { NumberAnimation { duration: launcher.opened ? 260 : 140; easing.type: Easing.OutQuint } }
    visible: opened || reveal > 0.001
    color: "transparent"
    screen: barWindow.screen
    anchors { top: true; bottom: true; left: true; right: true }
    exclusiveZone: -1
    WlrLayershell.namespace: "ohmansy-launcher"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    BackgroundEffect.blurRegion: Region { item: surface; radius: surface.radius }

    MouseArea { anchors.fill: parent; onClicked: launcher.dismissed() }

    Ui.GlassSurface {
        id: surface
        anchors.centerIn: parent
        width: Math.min(460, launcher.width - 48)
        height: Math.min(420, launcher.height - 96)
        radius: 16
        tint: theme.shellGlassTint
        colors: theme.colors
        sheen: false
        opacity: launcher.reveal
        enabled: launcher.opened
        MouseArea { anchors.fill: parent }
        Keys.onEscapePressed: launcher.dismissed()
        ColumnLayout {
            anchors { fill: parent; margins: 12 }
            spacing: 8
            Ui.GlassField {
                id: search
                colors: theme.colors
                Layout.fillWidth: true
                implicitHeight: 46
                leftPadding: 16
                rightPadding: 16
                font.pixelSize: 17
                placeholderText: launcher.prompt
                Accessible.name: launcher.prompt
                onAccepted: launcher.launch(launcher.matches[results.currentIndex])
                Keys.onDownPressed: launcher.moveSelection(1)
                Keys.onUpPressed: launcher.moveSelection(-1)
                Keys.onEscapePressed: launcher.dismissed()
                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Space && (event.modifiers & Qt.MetaModifier)) {
                        launcher.dismissed();
                        event.accepted = true;
                    } else event.accepted = false;
                }
            }
            ListView {
                id: results
                Layout.fillWidth: true
                Layout.fillHeight: true
                model: launcher.matches
                clip: true
                spacing: 2
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                delegate: ItemDelegate {
                    id: row
                    required property var modelData
                    required property int index
                    width: results.width
                    height: 48
                    padding: 8
                    focusPolicy: Qt.NoFocus
                    Accessible.name: modelData.name
                    onClicked: launcher.launch(modelData)
                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                    background: Rectangle {
                        radius: 10
                        color: row.index === results.currentIndex ? theme.selection : row.hovered ? theme.hover : "transparent"
                    }
                    contentItem: RowLayout {
                        spacing: 10
                        Image {
                            Layout.preferredWidth: 28
                            Layout.preferredHeight: 28
                            source: Quickshell.iconPath(row.modelData.icon, "application-x-executable")
                            sourceSize: Qt.size(64, 64)
                            layer.enabled: (row.modelData.icon || "").endsWith("-symbolic")
                            layer.effect: MultiEffect { colorization: 1; colorizationColor: theme.text }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1
                            Text {
                                Layout.fillWidth: true
                                text: row.modelData.name
                                textFormat: Text.PlainText
                                color: theme.text
                                font { family: Ui.Theme.fontFamily; pixelSize: 15; weight: Font.Medium }
                                elide: Text.ElideRight
                            }
                            Text {
                                Layout.fillWidth: true
                                text: row.modelData.genericName || row.modelData.comment || ""
                                textFormat: Text.PlainText
                                visible: text !== ""
                                color: theme.secondary
                                font { family: Ui.Theme.fontFamily; pixelSize: 11 }
                                elide: Text.ElideRight
                            }
                        }
                    }
                }
                Text {
                    anchors.centerIn: parent
                    visible: launcher.matches.length === 0
                    text: historyQuery.running ? "Loading…" : "No entries found"
                    color: theme.secondary
                    font { family: Ui.Theme.fontFamily; pixelSize: 15 }
                }
            }
            ScrollView {
                visible: launcher.notificationBody !== ""
                Layout.fillWidth: true
                Layout.preferredHeight: 120
                TextArea {
                    text: launcher.notificationBody
                    textFormat: TextEdit.PlainText
                    readOnly: true
                    wrapMode: TextEdit.Wrap
                    color: theme.text
                    font { family: Ui.Theme.fontFamily; pixelSize: 13 }
                    background: Item {}
                }
            }
            Text {
                Layout.leftMargin: 8
                Layout.fillWidth: true
                text: launcher.launchError || (appLaunch.running ? "Opening " + launcher.launchingName + "…" : "↑ ↓  Navigate     Enter  Open     Esc  Close")
                textFormat: Text.PlainText
                wrapMode: Text.Wrap
                color: theme.secondary
                font { family: Ui.Theme.fontFamily; pixelSize: 12 }
            }
        }
    }
}
