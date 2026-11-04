import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Ohmansy.Ui as Ui

PanelWindow {
    id: panel
    required property var barWindow
    required property var controller
    required property bool opened
    signal dismissed()
    onOpenedChanged: {
        if (opened) { controller.refresh(); Qt.callLater(() => view.forceActiveFocus()); }
        else controller.decide(false);
    }
    visible: opened
    screen: barWindow.screen
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusiveZone: -1
    WlrLayershell.namespace: "ohmansy-launcher"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    BackgroundEffect.blurRegion: Region { item: surface; radius: surface.radius }
    Theme { id: theme }
    MouseArea { anchors.fill: parent; onClicked: panel.dismissed() }
    Ui.GlassSurface {
        id: surface
        anchors.centerIn: parent
        width: Math.min(600, panel.width - 32)
        height: Math.min(610, panel.height - 48)
        colors: theme.colors
        tint: theme.shellGlassTint
        sheen: false
        MouseArea { anchors.fill: parent }
        ColumnLayout {
            anchors { fill: parent; margins: 20 }
            spacing: 10
            DisplayView {
                id: view
                Layout.fillWidth: true
                Layout.fillHeight: true
                controller: panel.controller
                Keys.onEscapePressed: panel.dismissed()
            }
            QuietButton {
                text: "Esc · Close"
                Accessible.name: "Close display settings"
                Layout.alignment: Qt.AlignRight
                onClicked: panel.dismissed()
            }
        }
    }
}
