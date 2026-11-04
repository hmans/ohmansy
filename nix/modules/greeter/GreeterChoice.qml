import QtQuick
import QtQuick.Controls
import Ohmansy.Ui

ComboBox {
    id: control
    property Item backdrop: null
    HoverHandler {
        enabled: control.enabled
        cursorShape: Qt.PointingHandCursor
    }
    implicitHeight: 64
    textRole: "label"
    font { family: "Inter"; pixelSize: 19; weight: Font.Medium }
    palette { text: "#e0def4"; buttonText: "#e0def4"; button: "#252832"; base: "#252832"; highlight: "#645373"; highlightedText: "#ffffff" }
    leftPadding: 22
    rightPadding: 60
    indicator: Image {
        x: control.width - width - 20
        y: (control.height - height) / 2
        width: 24
        height: 24
        source: Theme.chevron
        sourceSize: Qt.size(48, 48)
        opacity: control.hovered || control.popup.visible ? 0.95 : 0.65
        rotation: control.popup.visible ? 180 : 0
        Behavior on opacity { NumberAnimation { duration: 120 } }
        Behavior on rotation { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
    }
    contentItem: Text {
        text: control.displayText
        font: control.font
        color: "#f5f3fa"
        renderType: Text.QtRendering
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }
    background: GlassSurface {
        backdrop: control.backdrop
        highlighted: control.hovered
        pressed: control.down
        focused: control.visualFocus
    }
    delegate: ItemDelegate {
        id: accountOption
        HoverHandler {
            enabled: accountOption.enabled
            cursorShape: Qt.PointingHandCursor
        }
        required property var modelData
        required property int index
        width: control.width - 12
        height: 56
        leftPadding: 16
        text: modelData.label
        font: control.font
        highlighted: control.highlightedIndex === index
        contentItem: Text {
            text: parent.text
            font: control.font
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
        y: control.height + 6
        width: control.width
        padding: 6
        implicitHeight: Math.min(contentItem.implicitHeight + 12, 240)
        background: GlassSurface { backdrop: control.backdrop; highlighted: true }
        contentItem: ListView {
            clip: true
            implicitHeight: contentHeight
            model: control.popup.visible ? control.delegateModel : null
            currentIndex: control.highlightedIndex
            ScrollIndicator.vertical: ScrollIndicator {}
        }
    }
}
