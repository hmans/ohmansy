import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Ohmansy.Ui as Ui

Item {
    id: view
    required property var controller
    property string selectedName: ""
    readonly property var selected: controller.outputs.find(output => output.name === selectedName) || null
    property real draftScale: 1
    property string draftMode: ""
    readonly property var scales: {
        const values = [0.75, 1, 1.25, 1.5, 1.75, 2, 2.5, 3];
        if (selected && !values.includes(selected.scale)) values.push(selected.scale);
        return values.sort((a, b) => a - b);
    }
    readonly property bool changed: selected !== null &&
        (Math.abs(draftScale - selected.scale) > 0.001 || draftMode !== selected.mode)
    function reset() {
        if (selected) { draftScale = selected.scale; draftMode = selected.mode; }
    }
    onSelectedChanged: reset()
    Connections {
        target: view.controller
        function onOutputsChanged() {
            if (!view.selected) view.selectedName = view.controller.outputs.length ? view.controller.outputs[0].name : "";
            view.reset();
        }
    }
    Theme { id: theme }
    component Label: Text {
        Layout.fillWidth: true
        color: theme.text
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
        font { family: theme.fontFamily; pixelSize: 14 }
    }
    ColumnLayout {
        anchors.fill: parent
        spacing: 14
        RowLayout {
            Layout.fillWidth: true
            Label { text: "Displays"; font { pixelSize: 25; weight: Font.DemiBold } }
            Ui.GlassButton {
                text: "Refresh"
                actionRole: "secondary"
                implicitHeight: 40
                font.pixelSize: 14
                enabled: !view.controller.busy
                onClicked: view.controller.refresh()
            }
        }
        Flickable {
            id: scroll
            objectName: "displayScroll"
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentWidth: width
            contentHeight: settings.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar {}
            ColumnLayout {
                id: settings
                width: scroll.width - 12
                spacing: 16
                Label { text: "Monitor"; font.weight: Font.DemiBold }
                Flow {
                    Layout.fillWidth: true
                    spacing: 6
                    Repeater {
                        model: view.controller.outputs
                        QuietButton {
                            required property var modelData
                            text: modelData.label + " · " + modelData.name
                            width: Math.min(implicitWidth, settings.width)
                            selected: view.selectedName === modelData.name
                            enabled: !view.controller.busy
                            Accessible.name: "Configure " + text
                            onClicked: { view.selectedName = modelData.name; view.reset(); }
                        }
                    }
                }
                Label {
                    visible: !view.selected
                    text: view.controller.busy ? "Reading displays…" : "No active displays found. Connect a monitor and choose Refresh."
                    color: theme.secondary
                }
                Label {
                    visible: !!view.selected
                    text: view.selected ? view.selected.resolution + " pixels" : ""
                    color: theme.secondary
                }
                Label { visible: !!view.selected; text: "UI scale"; font.weight: Font.DemiBold }
                Flow {
                    visible: !!view.selected
                    Layout.fillWidth: true
                    spacing: 6
                    Repeater {
                        model: view.scales
                        QuietButton {
                            required property real modelData
                            text: Math.round(modelData * 100) + "%"
                            selected: Math.abs(view.draftScale - modelData) < 0.001
                            enabled: !view.controller.busy
                            Accessible.name: "UI scale " + text
                            onClicked: view.draftScale = modelData
                        }
                    }
                }
                Label { visible: !!view.selected; text: "Larger scales make text and controls bigger."; color: theme.secondary }
                Label { visible: !!view.selected; text: "Refresh rate"; font.weight: Font.DemiBold }
                Flow {
                    visible: !!view.selected
                    Layout.fillWidth: true
                    spacing: 6
                    Repeater {
                        model: view.selected ? view.selected.rates : []
                        QuietButton {
                            required property var modelData
                            text: modelData.label
                            selected: view.draftMode === modelData.mode
                            enabled: !view.controller.busy
                            Accessible.name: "Refresh rate " + text
                            onClicked: view.draftMode = modelData.mode
                        }
                    }
                }
                Label {
                    visible: !!view.selected
                    text: "Rates supported at the current resolution. Kept settings are restored at login."
                    color: theme.secondary
                }
            }
        }
        Label {
            text: view.controller.pending ? "Keep these display settings? Reverting in " + view.controller.seconds + " seconds."
                : view.controller.error || view.controller.message || "Changes revert after 15 seconds unless you keep them."
            color: view.controller.error ? theme.accent : theme.secondary
        }
        RowLayout {
            objectName: "displayActions"
            Layout.fillWidth: true
            Ui.GlassButton {
                visible: view.controller.pending
                text: "Revert"
                actionRole: "return"
                Layout.fillWidth: true
                implicitHeight: 46
                font.pixelSize: 15
                onClicked: view.controller.decide(false)
            }
            Ui.GlassButton {
                Layout.fillWidth: true
                text: view.controller.pending ? "Keep changes" : "Apply"
                actionRole: "primary"
                implicitHeight: 46
                font.pixelSize: 15
                enabled: view.controller.pending || (view.changed && !view.controller.busy)
                onClicked: {
                    if (view.controller.pending) view.controller.decide(true);
                    else view.controller.apply(view.selectedName, view.draftScale, view.draftMode);
                }
            }
        }
    }
}
