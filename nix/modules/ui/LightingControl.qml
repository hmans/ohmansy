import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ColumnLayout {
    id: panel
    property string error: ""
    property bool saved: false
    signal edited(var settings, bool save)
    spacing: 12
    function change(direction, strength, highlight, shadow, save) {
        edited({ direction: direction, strength: strength,
            highlight_color: highlight, shadow_color: shadow }, save || false);
    }
    function aim(x, y) {
        const length = Math.max(1, Math.hypot(x, y));
        change([x / length, y / length], Lighting.strength, Lighting.highlight, Lighting.shadow);
    }
    Text { text: "Desktop lighting"; color: Theme.text; font.family: Theme.fontFamily; font.pixelSize: 22 }
    Text { text: "Drag the light around the globe."; color: Theme.secondary; font.pixelSize: 13 }
    Item {
        Layout.alignment: Qt.AlignHCenter
        Layout.preferredWidth: 190
        Layout.preferredHeight: 190
        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: Theme.buttonSecondarySolid
            border.color: Theme.secondary
            border.width: 1
            Canvas {
                id: globe
                anchors.fill: parent
                onPaint: {
                    const ctx = getContext("2d");
                    ctx.clearRect(0, 0, width, height);
                    const x = width * (0.5 + Lighting.direction[0] * 0.32);
                    const y = height * (0.5 + Lighting.direction[1] * 0.32);
                    const gradient = ctx.createRadialGradient(x, y, 0, width/2, height/2, width/2);
                    const c = Lighting.highlight;
                    gradient.addColorStop(0, Qt.rgba(c[0], c[1], c[2], Math.min(0.8, Lighting.strength * 0.45)));
                    gradient.addColorStop(1, Qt.rgba(0, 0, 0, 0.65));
                    ctx.fillStyle = gradient;
                    ctx.beginPath(); ctx.arc(width/2, height/2, width/2-1, 0, Math.PI*2); ctx.fill();
                    ctx.strokeStyle = "#30ffffff"; ctx.lineWidth = 1;
                    ctx.beginPath(); ctx.ellipse(width/2-30, 1, 60, height-2); ctx.stroke();
                    ctx.beginPath(); ctx.ellipse(1, height/2-30, width-2, 60); ctx.stroke();
                }
                Connections {
                    target: Lighting
                    function onSettingsChanged() { globe.requestPaint(); }
                }
            }
        }
        Rectangle {
            x: (parent.width - width) / 2 + Lighting.direction[0] * (parent.width / 2 - 8)
            y: (parent.height - height) / 2 + Lighting.direction[1] * (parent.height / 2 - 8)
            width: 14; height: 14; radius: 7
            color: Qt.rgba(...Lighting.highlight, 1)
            border.color: Theme.text
            border.width: 2
        }
        MouseArea {
            id: aim
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            focus: true
            Accessible.role: Accessible.Slider
            Accessible.name: "Light direction"
            Accessible.description: "Use arrow keys to move the light; Home centers it"
            function move(mouse) { panel.aim((mouse.x - width/2)/(width/2-8), (mouse.y - height/2)/(height/2-8)); }
            onPressed: mouse => { forceActiveFocus(); move(mouse); }
            onPositionChanged: mouse => { if (pressed) move(mouse); }
            Keys.onLeftPressed: panel.aim(Lighting.direction[0]-0.08, Lighting.direction[1])
            Keys.onRightPressed: panel.aim(Lighting.direction[0]+0.08, Lighting.direction[1])
            Keys.onUpPressed: panel.aim(Lighting.direction[0], Lighting.direction[1]-0.08)
            Keys.onDownPressed: panel.aim(Lighting.direction[0], Lighting.direction[1]+0.08)
            Keys.onPressed: event => {
                if (event.key === Qt.Key_Home) { panel.aim(0, 0); event.accepted = true; }
            }
        }
    }
    RowLayout {
        Text { text: "Strength"; color: Theme.text }
        Slider {
            id: strengthSlider
            Layout.fillWidth: true
            implicitHeight: 32
            from: 0; to: 3; stepSize: 0.05
            value: Lighting.strength
            Accessible.name: "Light strength"
            onMoved: panel.change(Lighting.direction, value, Lighting.highlight, Lighting.shadow)
            background: Rectangle {
                x: strengthSlider.leftPadding
                y: (strengthSlider.height - height) / 2
                width: strengthSlider.availableWidth
                height: 3; radius: 1.5
                color: Theme.buttonSecondarySolid
                Rectangle { width: parent.width * strengthSlider.visualPosition; height: parent.height; radius: 1.5; color: Theme.secondary }
            }
            handle: Rectangle {
                x: strengthSlider.leftPadding + strengthSlider.visualPosition * (strengthSlider.availableWidth - width)
                y: (strengthSlider.height - height) / 2
                width: 12; height: 12; radius: 6
                color: Theme.text
                border.width: strengthSlider.visualFocus ? 2 : 0
                border.color: Theme.primaryGlass
            }
        }
        Text { text: Math.round(Lighting.strength * 100) + "%"; color: Theme.secondary; Layout.preferredWidth: 42 }
    }
    RowLayout {
        Repeater {
            model: [
                { name: "Neutral", highlight: [1,1,1], shadow: [0,0,0] },
                { name: "Warm", highlight: [1,0.84,0.64], shadow: [0.04,0.025,0.08] },
                { name: "Cool", highlight: [0.65,0.84,1], shadow: [0.02,0.04,0.10] }
            ]
            GlassButton {
                required property var modelData
                text: modelData.name
                implicitHeight: 32
                padding: 8
                font.pixelSize: 13
                Layout.fillWidth: true
                onClicked: panel.change(Lighting.direction, Lighting.strength, modelData.highlight, modelData.shadow)
            }
        }
    }
    Text {
        Layout.fillWidth: true
        text: panel.error || (panel.saved ? "Saved to config.toml." : "Changes apply live. Save to keep them after login.")
        wrapMode: Text.WordWrap
        color: Theme.secondary
        font.pixelSize: 12
    }
    Item { Layout.fillHeight: true }
    RowLayout {
        GlassButton {
            text: "Reset"
            implicitHeight: 34
            padding: 9
            font.pixelSize: 14
            onClicked: panel.change([-Math.SQRT1_2, -Math.SQRT1_2], 1, [1,1,1], [0,0,0])
        }
        Item { Layout.fillWidth: true }
        GlassButton {
            text: "Save"
            implicitHeight: 34
            padding: 9
            font.pixelSize: 14
            actionRole: "primary"
            onClicked: panel.change(Lighting.direction, Lighting.strength, Lighting.highlight, Lighting.shadow, true)
        }
    }
}
