import QtQuick
import QtQuick.Layouts
import Quickshell
import Ohmansy.Ui as Ui

Item {
    id: card
    required property string summary
    required property string body
    property string appName: ""
    property string icon: ""
    property string image: ""
    property int urgency: 1
    property var actions: []
    property bool actionable: false
    readonly property bool hovered: hover.hovered
    signal dismissed()
    signal invoked(var action)
    signal defaultInvoked()
    implicitHeight: content.implicitHeight + 36
    Ui.GlassSurface {
        anchors.fill: parent
        tint: Ui.Theme.solidSurface
        highlighted: card.hovered
        focused: card.urgency === 2
    }
    HoverHandler { id: hover }
    // Never request keyboard focus just to show a notification.
    ColumnLayout {
        id: content
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 18 }
        spacing: 10
        RowLayout {
            spacing: 12
            Image {
                visible: card.icon !== ""
                source: card.icon === "" ? "" : card.icon.startsWith("/") || card.icon.includes(":")
                    ? card.icon : Quickshell.iconPath(card.icon)
                Layout.preferredWidth: 36
                Layout.preferredHeight: 36
                fillMode: Image.PreserveAspectFit
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4
                TapHandler { onTapped: if (card.actionable) card.defaultInvoked() }
                Text {
                    visible: text !== ""
                    Layout.fillWidth: true
                    text: (card.urgency === 2 ? "Urgent · " : "") + card.appName
                    textFormat: Text.PlainText
                    color: Ui.Theme.secondary
                    font { family: Ui.Theme.fontFamily; pixelSize: 12 }
                    elide: Text.ElideRight
                }
                Text {
                    Layout.fillWidth: true
                    text: card.summary || "Notification"
                    textFormat: Text.PlainText
                    color: Ui.Theme.text
                    font { family: Ui.Theme.fontFamily; pixelSize: 16; weight: Font.DemiBold }
                    wrapMode: Text.Wrap
                    maximumLineCount: 3
                    elide: Text.ElideRight
                }
            }
            Ui.GlassButton {
                text: "×"
                Accessible.name: "Dismiss notification"
                actionRole: "return"
                implicitWidth: 28
                implicitHeight: 28
                padding: 4
                font.pixelSize: 18
                onClicked: card.dismissed()
            }
        }
        Text {
            TapHandler { onTapped: if (card.actionable) card.defaultInvoked() }
            visible: text !== ""
            Layout.fillWidth: true
            text: card.body
            textFormat: Text.PlainText
            color: Ui.Theme.secondary
            font { family: Ui.Theme.fontFamily; pixelSize: 14 }
            wrapMode: Text.WrapAnywhere
            maximumLineCount: 8
            elide: Text.ElideRight
        }
        Image {
            TapHandler { onTapped: if (card.actionable) card.defaultInvoked() }
            visible: card.image !== ""
            source: card.image
            Layout.fillWidth: true
            Layout.preferredHeight: visible ? Math.min(150, implicitHeight) : 0
            fillMode: Image.PreserveAspectFit
        }
        Flow {
            Layout.fillWidth: true
            spacing: 6
            Repeater {
                model: card.actions.filter(action => action.identifier !== "default")
                Ui.GlassButton {
                    required property var modelData
                    text: modelData.text
                    actionRole: "secondary"
                    implicitHeight: 34
                    width: Math.min(implicitWidth, content.width)
                    padding: 8
                    font.pixelSize: 13
                    onClicked: card.invoked(modelData)
                }
            }
        }
    }
}
