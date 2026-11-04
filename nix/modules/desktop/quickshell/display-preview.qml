//@ pragma UseQApplication
import QtQuick
import Quickshell
import Ohmansy.Ui as Ui

ShellRoot {
    Theme { id: previewTheme }
    QtObject {
        id: demo
        property bool busy: false
        property bool pending: false
        property int seconds: 15
        property string error: ""
        property string message: ""
        property var outputs: [
            {name: "DP-1", label: "Example 27-inch display", resolution: "2560 × 1440", scale: 1,
                mode: "2560x1440@59.951", rates: [
                    {mode: "2560x1440@59.951", label: "59.951 Hz"},
                    {mode: "2560x1440@143.973", label: "143.973 Hz"}]},
            {name: "HDMI-A-1", label: "Example ultrawide", resolution: "3440 × 1440", scale: 1.25,
                mode: "3440x1440@99.982", rates: [{mode: "3440x1440@99.982", label: "99.982 Hz"}]}]
        property string changedName: ""
        property real changedScale: 1
        property string changedMode: ""
        function refresh() { outputs = outputs.slice(); }
        function apply(name, scale, mode) {
            changedName = name; changedScale = scale; changedMode = mode;
            pending = true; busy = true; seconds = 15;
        }
        function decide(keep) {
            if (keep) outputs = outputs.map(output => output.name === changedName
                ? Object.assign({}, output, {scale: changedScale, mode: changedMode}) : output);
            pending = false; busy = false;
            message = keep ? "Display settings saved." : "Previous display settings restored.";
        }
    }
    // Instantiate the real controller too, without issuing any commands.
    DisplayState {}
    FloatingWindow {
        id: window
        visible: true
        title: "ohmansy display preview"
        implicitWidth: Number(Quickshell.env("PREVIEW_WIDTH")) || 600
        implicitHeight: Number(Quickshell.env("PREVIEW_HEIGHT")) || 610
        color: previewTheme.colors.surfaceBase
        onClosed: Qt.quit()
        Rectangle {
            id: previewSurface
            anchors.fill: parent
            color: previewTheme.colors.surfaceBase
            DisplayView {
                id: view
                anchors { fill: parent; margins: 20 }
                controller: demo
                Component.onCompleted: selectedName = demo.outputs[0].name
            }
        }
        Timer {
            interval: 1200
            running: !!Quickshell.env("PREVIEW_IMAGE")
            onTriggered: {
                if (Quickshell.env("PREVIEW_STATE") === "pending") {
                    view.draftScale = 1.5;
                    view.draftMode = "2560x1440@143.973";
                    demo.apply("DP-1", view.draftScale, view.draftMode);
                }
                if (Quickshell.env("PREVIEW_STATE") === "empty") demo.outputs = [];
                if (Quickshell.env("PREVIEW_STATE") === "error") demo.error = "The display was disconnected. Refresh the display list.";
                Qt.callLater(() => {
                    function find(item, name) {
                        if (item.objectName === name) return item;
                        for (const child of item.children || []) {
                            const match = find(child, name);
                            if (match) return match;
                        }
                        return null;
                    }
                    const actions = find(view, "displayActions");
                    const scroll = find(view, "displayScroll");
                    if (!actions || !scroll || actions.y + actions.height > view.height + 1
                        || scroll.y + scroll.height > actions.y)
                        throw new Error("Display actions overlap the scrolling settings");
                    for (const button of actions.children) {
                        if (!button.visible || !button.text) continue;
                        if (button.x < 0 || button.x + button.width > actions.width + 1)
                            throw new Error("Display action is outside the panel");
                        if (button.contentItem.implicitWidth > button.width - button.leftPadding - button.rightPadding + 1)
                            throw new Error("Display action label is clipped");
                    }
                    previewSurface.grabToImage(result => {
                        result.saveToFile(Quickshell.env("PREVIEW_IMAGE")); Qt.quit();
                    });
                });
            }
        }
        Timer {
            interval: 100
            running: Quickshell.env("DISPLAY_FLOW_TEST") === "1"
            onTriggered: {
                function check(condition, message) { if (!condition) throw new Error(message); }
                check(!view.changed, "Initial draft differs");
                view.draftScale = 1.5;
                view.draftMode = "2560x1440@143.973";
                check(view.changed, "Draft did not change");
                demo.apply(view.selectedName, view.draftScale, view.draftMode);
                check(demo.pending, "Missing confirmation");
                demo.decide(false);
                check(demo.outputs[0].scale === 1, "Revert saved draft");
                demo.apply(view.selectedName, view.draftScale, view.draftMode);
                demo.decide(true);
                check(demo.outputs[0].scale === 1.5, "Keep lost scale");
                view.selectedName = "HDMI-A-1";
                check(view.draftScale === 1.25, "Monitor switch kept another monitor's draft");
                demo.outputs = [];
                check(!view.selected && !view.changed, "Disconnected monitor remains selected");
                console.log("DISPLAY_FLOW_TEST passed");
                Qt.quit();
            }
        }
    }
}
