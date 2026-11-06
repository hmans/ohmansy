import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Ohmansy.Ui as Ui
import "Search.js" as Search
import "Commands.js" as Commands

PanelWindow {
    id: launcher
    required property bool opened
    // Providers contribute data; the shell owns desktop command execution.
    property var providers: [Commands.desktop]
    signal dismissed()
    signal commandRequested(string command)
    readonly property var applicationItems: DesktopEntries.applications.values.map(app => ({
        id: "app:" + app.id, title: app.name, subtitle: app.genericName || app.comment || "Application",
        icon: app.icon, keywords: [app.genericName || "", app.comment || "", ...(app.keywords || [])],
        provider: "applications", desktopId: app.id
    }))
    readonly property var items: applicationItems.concat(...providers.map(provider => provider.items))
    readonly property var matches: Search.rank(items, search.text)
    property string error: ""
    property string selectedId: ""
    readonly property int selectedIndex: {
        const index = matches.findIndex(item => item.id === selectedId);
        return index >= 0 ? index : matches.length ? 0 : -1;
    }
    readonly property var selectedItem: matches[selectedIndex]
    // A small status interface also lets headless trials inspect real UI state.
    function status() {
        return JSON.stringify({ opened: opened, query: search.text, error: error,
            selected: selectedItem ? selectedItem.id : null, currentIndex: selectedIndex,
            results: matches.slice(0, 12).map(item => ({ id: item.id, title: item.title })) });
    }
    function moveSelection(step) {
        if (!matches.length) return;
        const next = (selectedIndex + step + matches.length) % matches.length;
        selectedId = matches[next].id;
        results.positionViewAtIndex(next, ListView.Contain);
    }
    function activate(item) {
        if (!item || !opened || launch.running) return;
        error = "";
        if (item.provider !== "applications") {
            dismissed();
            commandRequested(item.command);
            return;
        }
        // Close before handing focus to an explicitly requested application.
        dismissed();
        launch.command = [Quickshell.env("OHMANSY_APP_LAUNCHER"), "--", item.desktopId + ".desktop"];
        launch.running = true;
    }
    Process {
        id: launch
        onExited: (code, status) => {
            if (code !== 0 || status !== 0) {
                launcher.error = "Could not open the application. Try again.";
                // Do not reopen asynchronously and steal focus. Show on next open.
            }
        }
    }
    onOpenedChanged: if (opened) {
        search.clear();
        selectedId = "";
        Qt.callLater(() => search.forceActiveFocus());
    }
    Ui.ColorPalette { id: launcherColors; dark: Qt.styleHints.colorScheme === Qt.ColorScheme.Dark }
    anchors { top: true; bottom: true; left: true; right: true }
    exclusiveZone: 0
    color: "transparent"
    // Keep the layer role alive while hidden (including during shell reloads).
    mask: Region { item: launcher.opened ? interaction : null }
    WlrLayershell.namespace: "ohmansy-launcher"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    BackgroundEffect.blurRegion: Region { item: launcher.opened ? surface : null; radius: Ui.Theme.radius }
    Item {
        id: interaction
        anchors.fill: parent
        visible: launcher.opened
        MouseArea { anchors.fill: parent; onClicked: launcher.dismissed() }
        Ui.GlassSurface {
            id: surface
            anchors.horizontalCenter: parent.horizontalCenter
            y: Math.max(24, (parent.height - height) * 0.32)
            width: Math.min(640, parent.width - 48)
            height: Math.min(520, parent.height - 48)
            colors: launcherColors
            tint: launcherColors.surface
            sheen: false
            MouseArea { anchors.fill: parent }
            ColumnLayout {
                anchors { fill: parent; margins: 14 }
                spacing: 10
                Ui.GlassField {
                    id: search
                    Layout.fillWidth: true
                    implicitHeight: 52
                    colors: launcherColors
                    placeholderText: "Search apps and commands…"
                    Accessible.name: "Search apps and commands"
                    onTextEdited: launcher.selectedId = ""
                    onAccepted: launcher.activate(launcher.selectedItem)
                    Keys.onDownPressed: launcher.moveSelection(1)
                    Keys.onUpPressed: launcher.moveSelection(-1)
                    Keys.onEscapePressed: launcher.dismissed()
                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_Space && (event.modifiers & Qt.MetaModifier)) {
                            launcher.dismissed(); event.accepted = true;
                        } else event.accepted = false;
                    }
                }
                ListView {
                    id: results
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    model: launcher.matches
                    currentIndex: launcher.selectedIndex
                    clip: true
                    spacing: 3
                    boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.vertical: ScrollBar {}
                    delegate: ItemDelegate {
                        id: row
                        required property var modelData
                        required property int index
                        width: results.width
                        height: 54
                        padding: 10
                        focusPolicy: Qt.NoFocus
                        Accessible.name: modelData.title + ", " + modelData.subtitle
                        onClicked: launcher.activate(modelData)
                        HoverHandler { cursorShape: Qt.PointingHandCursor }
                        background: Rectangle {
                            radius: Ui.Theme.radius
                            color: row.index === launcher.selectedIndex ? launcherColors.selection : row.hovered ? launcherColors.hover : "transparent"
                        }
                        contentItem: RowLayout {
                            spacing: 12
                            Image {
                                Layout.preferredWidth: 28
                                Layout.preferredHeight: 28
                                source: Quickshell.iconPath(row.modelData.icon || "application-x-executable", "application-x-executable")
                                sourceSize: Qt.size(48, 48)
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2
                                Text {
                                    Layout.fillWidth: true
                                    text: row.modelData.title
                                    textFormat: Text.PlainText
                                    color: launcherColors.text
                                    font { family: Ui.Theme.fontFamily; pixelSize: 16; weight: Font.Medium }
                                    elide: Text.ElideRight
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: row.modelData.subtitle
                                    textFormat: Text.PlainText
                                    color: launcherColors.secondary
                                    font { family: Ui.Theme.fontFamily; pixelSize: 12 }
                                    elide: Text.ElideRight
                                }
                            }
                            Text {
                                text: row.modelData.provider === "applications" ? "App" : "Command"
                                color: launcherColors.secondary
                                font { family: Ui.Theme.fontFamily; pixelSize: 11 }
                            }
                        }
                    }
                    Text {
                        anchors.centerIn: parent
                        visible: !launcher.matches.length
                        text: "No matches"
                        color: launcherColors.secondary
                        font { family: Ui.Theme.fontFamily; pixelSize: 15 }
                    }
                }
                Text {
                    Layout.fillWidth: true
                    text: launcher.error || (launch.running ? "Opening application…" : "↑ ↓  Navigate     Enter  Open     Esc  Close")
                    textFormat: Text.PlainText
                    color: launcherColors.secondary
                    font { family: Ui.Theme.fontFamily; pixelSize: 12 }
                    wrapMode: Text.Wrap
                }
            }
        }
    }
}
