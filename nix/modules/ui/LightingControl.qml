import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ColumnLayout {
    id: panel
    property string error: ""
    property bool saved: false
    property var frameSettings: ({})
    property bool animationsEnabled: true
    signal edited(var settings, bool save)
    signal paletteEdited(var palette)
    signal intensityEdited(real value)
    signal blurEdited(int radius)
    property int blurRadius: 32
    spacing: 10
    function change(direction, strength, highlight, shadow, save) {
        edited({ direction: direction, strength: strength,
            highlight_color: highlight, shadow_color: shadow }, save || false);
    }
    component MaterialSlider: Slider {
        id: slider
        implicitHeight: 32
        background: Rectangle {
            x: slider.leftPadding; y: (slider.height-height)/2
            width: slider.availableWidth; height: 5; radius: 2.5
            color: Theme.buttonSecondarySolid
            Rectangle { width: parent.width*slider.visualPosition; height: parent.height; radius: 2.5; color: Theme.secondary }
        }
        handle: Rectangle {
            x: slider.leftPadding + slider.visualPosition*(slider.availableWidth-width)
            y: (slider.height-height)/2
            width: 14; height: 14; radius: 7
            color: Theme.text
            border.width: slider.visualFocus || slider.pressed ? 2 : 0
            border.color: Theme.buttonPrimarySolid
        }
    }
    function aim(x, y) {
        const length = Math.max(1, Math.hypot(x, y));
        change([x / length, y / length], Lighting.strength, Lighting.highlight, Lighting.shadow);
    }
    Text { text: "Desktop lighting"; color: Theme.text; font.family: Theme.fontFamily; font.pixelSize: 22 }
    Text { text: "Drag the light around the globe."; color: Theme.secondary; font.pixelSize: 13 }
    Item {
        Layout.alignment: Qt.AlignHCenter
        Layout.preferredWidth: 140
        Layout.preferredHeight: 140
        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: Theme.buttonSecondarySolid
            border.color: Theme.secondary
            border.width: 1
            Canvas {
                id: globe
                readonly property string lightingKey: JSON.stringify(Lighting.settings)
                onLightingKeyChanged: requestPaint()
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
        MaterialSlider {
            id: strengthSlider
            Layout.fillWidth: true
            implicitHeight: 32
            from: 0; to: 3; stepSize: 0.05
            value: Lighting.strength
            Accessible.name: "Light strength"
            onMoved: panel.change(Lighting.direction, value, Lighting.highlight, Lighting.shadow)

        }
        Text { text: Math.round(Lighting.strength * 100) + "%"; color: Theme.secondary; Layout.preferredWidth: 42 }
    }
    Text { text: "Theme · " + DesktopPalette.currentName; color: Theme.secondary; font.pixelSize: 13 }
    GridLayout {
        columns: 3
        columnSpacing: 10
        rowSpacing: 10
        Layout.fillWidth: true
        Repeater {
            model: DesktopPalette.themes
            GlassButton {
                id: themeCard
                required property var modelData
                readonly property bool selected: DesktopPalette.matches(modelData.palette)
                implicitHeight: 84
                padding: 10
                actionRole: selected ? "primary" : "secondary"
                Layout.fillWidth: true
                Layout.preferredWidth: 90
                Accessible.name: modelData.name + " theme"
                Accessible.description: selected ? "Selected theme" : "Apply theme"
                onClicked: panel.paletteEdited(modelData.palette)
                scale: down ? 0.97 : hovered ? 1.025 : 1
                Behavior on scale { NumberAnimation { duration: panel.animationsEnabled ? 120 : 0; easing.type: Easing.OutCubic } }
                background: Item {
                    FrameSurface {
                        anchors.fill: parent
                        active: themeCard.selected
                        highlighted: themeCard.hovered
                        pressed: themeCard.down
                        animationsEnabled: panel.animationsEnabled
                        frameSettings: Object.assign({}, panel.frameSettings, {
                            outer_corner_radius: 20, inner_corner_radius: 16,
                            active_color: [Theme.themeCardActive.r, Theme.themeCardActive.g, Theme.themeCardActive.b, Theme.themeCardActive.a],
                            inactive_color: [Theme.themeCardInactive.r, Theme.themeCardInactive.g, Theme.themeCardInactive.b, Theme.themeCardInactive.a]
                        })
                    }
                    Rectangle {
                        anchors.fill: parent
                        radius: 20
                        color: "transparent"
                        border.width: themeCard.selected || themeCard.visualFocus ? 2 : 0
                        border.color: themeCard.visualFocus ? Theme.text : Qt.rgba(
                            DesktopPalette.primary[0] * 0.5 + 0.5,
                            DesktopPalette.primary[1] * 0.5 + 0.5,
                            DesktopPalette.primary[2] * 0.5 + 0.5, 0.9)
                    }
                }
                contentItem: Column {
                    spacing: 9
                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: -8
                        Repeater {
                            model: themeCard.modelData.preview
                            Rectangle {
                                required property var modelData
                                width: 32; height: 32; radius: 16
                                color: DesktopPalette.color(modelData)
                                border.width: 2
                                border.color: Qt.rgba(1,1,1,0.16)
                            }
                        }
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: themeCard.modelData.name
                        color: Theme.text
                        font.family: Theme.fontFamily
                        font.pixelSize: 14
                        font.weight: Font.DemiBold
                    }
                }
                Rectangle {
                    visible: themeCard.selected
                    anchors { right: parent.right; top: parent.top; rightMargin: 5; topMargin: 5 }
                    width: 17; height: 17; radius: 9
                    color: Theme.text
                    Text { anchors.centerIn: parent; text: "✓"; color: Theme.buttonSecondarySolid; font.pixelSize: 12; font.weight: Font.Bold }
                }
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
    Text { text: "Atmosphere · Accent · Companion"; color: Theme.secondary; font.pixelSize: 12 }
    RowLayout {
        Layout.fillWidth: true
        Text { text: "Muted"; color: Theme.secondary; font.pixelSize: 13 }
        MaterialSlider {
            Layout.fillWidth: true
            from: 0; to: 1; value: DesktopPalette.intensity
            Accessible.name: "Color intensity"
            onMoved: panel.intensityEdited(value)
        }
        Text { text: "Vivid"; color: Theme.secondary; font.pixelSize: 13 }
    }
    RowLayout {
        Layout.fillWidth: true
        Text { text: "Backdrop blur"; color: Theme.secondary; font.pixelSize: 13 }
        MaterialSlider {
            Layout.fillWidth: true
            from: 0; to: 64; stepSize: 1; value: panel.blurRadius
            Accessible.name: "Backdrop blur radius"
            onMoved: panel.blurEdited(Math.round(value))
        }
        Text { text: panel.blurRadius + " px"; color: Theme.secondary; font.pixelSize: 13; Layout.preferredWidth: 36 }
    }
    Item { Layout.fillHeight: true }
    RowLayout {
        GlassButton {
            text: "Reset light"
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
