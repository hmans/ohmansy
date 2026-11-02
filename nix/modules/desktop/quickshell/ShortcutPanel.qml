import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Ohmansy.Ui as Ui
import "Shortcuts.js" as Shortcuts

PanelWindow {
    id: panel
    required property var barWindow
    required property bool opened
    signal dismissed()
    property var groups: []
    property string loadError: ""
    property real reveal: opened ? 1 : 0
    readonly property var sections: Shortcuts.sections(groups, search.text)
    readonly property bool twoColumns: surface.width >= 780
    Theme { id: theme }
    FileView {
        path: "/etc/ohmansy/shortcuts.json"
        onLoaded: {
            try { panel.groups = JSON.parse(text()); panel.loadError = ""; }
            catch (error) { panel.loadError = "Could not read keyboard shortcuts."; }
        }
        onLoadFailed: panel.loadError = "Could not load keyboard shortcuts."
    }
    onOpenedChanged: if (opened) {
        search.clear();
        scroll.contentY = 0;
        Qt.callLater(() => search.forceActiveFocus());
    }
    Behavior on reveal { NumberAnimation { duration: panel.opened ? 240 : 140; easing.type: Easing.OutQuint } }
    visible: opened || reveal > 0
    screen: barWindow.screen
    color: "transparent"
    anchors { top: true; bottom: true; left: true; right: true }
    exclusiveZone: -1
    // Share the launcher's existing compositor glass rule.
    WlrLayershell.namespace: "ohmansy-launcher"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    BackgroundEffect.blurRegion: Region { item: surface; radius: surface.radius }
    MouseArea { anchors.fill: parent; onClicked: panel.dismissed() }
    // Shape-only shadows avoid rendering the scrolling text into a texture.
    // The broad shadow lifts the panel; the tight one defines its lower edge.
    Item {
        anchors.fill: surface
        opacity: panel.reveal
        visible: GraphicsInfo.api !== GraphicsInfo.Software
        RectangularShadow {
            anchors.fill: parent
            radius: surface.radius
            blur: 32
            spread: -4
            offset.y: 12
            color: theme.colors.dark ? "#70000000" : "#34000000"
        }
        RectangularShadow {
            anchors.fill: parent
            radius: surface.radius
            blur: 8
            spread: -2
            offset.y: 3
            color: theme.colors.dark ? "#40000000" : "#24000000"
        }
    }
    Ui.GlassSurface {
        id: surface
        anchors.centerIn: parent
        width: Math.min(1040, panel.width - 80)
        height: Math.min(740, panel.height - 80)
        radius: 20
        tint: theme.shellGlassTint
        colors: theme.colors
        sheen: false
        opacity: panel.reveal
        enabled: panel.opened
        MouseArea { anchors.fill: parent }
        Keys.onEscapePressed: panel.dismissed()
        ColumnLayout {
            anchors { fill: parent; margins: 24 }
            spacing: 16
            RowLayout {
                Layout.fillWidth: true
                Text {
                    Layout.fillWidth: true
                    text: "Keyboard shortcuts"
                    color: theme.text
                    font { family: theme.fontFamily; pixelSize: 25; weight: Font.DemiBold }
                }
                QuietButton {
                    text: "Esc  ·  Close"
                    Accessible.name: "Close keyboard shortcuts"
                    onClicked: panel.dismissed()
                }
            }
            Ui.GlassField {
                id: search
                Layout.fillWidth: true
                implicitHeight: 46
                colors: theme.colors
                leftPadding: 14
                font.pixelSize: 16
                placeholderText: "Find an action or key…"
                Accessible.name: "Search keyboard shortcuts"
                onTextChanged: scroll.contentY = 0
                Keys.onEscapePressed: panel.dismissed()
                Keys.onDownPressed: scroll.step(44)
                Keys.onUpPressed: scroll.step(-44)
                Keys.onPressed: event => {
                    if (event.key === Qt.Key_PageDown || event.key === Qt.Key_PageUp) {
                        scroll.step(scroll.height * (event.key === Qt.Key_PageDown ? 0.85 : -0.85));
                        event.accepted = true;
                    } else event.accepted = false;
                }
            }
            Flickable {
                id: scroll
                Layout.fillWidth: true
                Layout.fillHeight: true
                contentWidth: width
                contentHeight: columns.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                function step(delta) { contentY = Math.max(0, Math.min(Math.max(0, contentHeight - height), contentY + delta)); }
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                Row {
                    id: columns
                    width: scroll.width - 12
                    spacing: 32
                    Repeater {
                        model: panel.twoColumns ? 2 : 1
                        Column {
                            id: column
                            required property int index
                            width: (columns.width - (panel.twoColumns ? columns.spacing : 0)) / (panel.twoColumns ? 2 : 1)
                            spacing: 24
                            Repeater {
                                model: panel.sections.filter(group => !panel.twoColumns || group.column === column.index)
                                Column {
                                    id: section
                                    required property var modelData
                                    width: column.width
                                    spacing: 8
                                    Text {
                                        text: section.modelData.title
                                        color: theme.accent
                                        font { family: theme.fontFamily; pixelSize: 15; weight: Font.DemiBold }
                                    }
                                    Column {
                                        width: parent.width
                                        Repeater {
                                            model: section.modelData.rows
                                            Item {
                                                id: row
                                                required property var modelData
                                                width: parent.width
                                                height: Math.max(40, label.implicitHeight + 16, combinations.implicitHeight + 12)
                                                Accessible.role: Accessible.StaticText
                                                Accessible.name: modelData.title + ": " + modelData.keys.map(Shortcuts.keycaps).map(keys => keys.join(" + ")).join(" or ")
                                                Text {
                                                    id: label
                                                    anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                                                    width: Math.max(80, parent.width - combinations.width - 12)
                                                    text: row.modelData.title
                                                    textFormat: Text.PlainText
                                                    wrapMode: Text.Wrap
                                                    color: theme.text
                                                    font { family: theme.fontFamily; pixelSize: 13 }
                                                }
                                                Column {
                                                    id: combinations
                                                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                                                    spacing: 4
                                                    Repeater {
                                                        model: row.modelData.keys
                                                        Row {
                                                            id: chord
                                                            required property string modelData
                                                            anchors.right: parent.right
                                                            spacing: 3
                                                            Repeater {
                                                                model: Shortcuts.keycaps(chord.modelData)
                                                                Rectangle {
                                                                    required property string modelData
                                                                    width: keyLabel.implicitWidth + 12
                                                                    height: 25
                                                                    radius: 5
                                                                    color: theme.colors.control
                                                                    border { width: 0.5; color: theme.border }
                                                                    Text {
                                                                        id: keyLabel
                                                                        anchors.centerIn: parent
                                                                        text: parent.modelData
                                                                        color: theme.secondary
                                                                        font { family: theme.fontFamily; pixelSize: 11; weight: Font.Medium }
                                                                    }
                                                                }
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                Text {
                    anchors.centerIn: parent
                    visible: panel.loadError !== "" || panel.sections.length === 0
                    text: panel.loadError || "No matching shortcuts"
                    color: theme.secondary
                    font { family: theme.fontFamily; pixelSize: 15 }
                }
            }
            Text {
                text: "Super is your desktop modifier.   ↑ ↓ Scroll"
                color: theme.muted
                font { family: theme.fontFamily; pixelSize: 12 }
            }
        }
    }
}
