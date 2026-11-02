import QtQuick

// Shared page transition: retain the outgoing page until it is transparent.
Item {
    id: transition
    property string requestedPage: ""
    property string displayedPage: ""
    property bool animated: true
    property real contentOpacity: 1
    readonly property bool interactive: !sequence.running && displayedPage === requestedPage
    signal settled()
    onRequestedPageChanged: {
        sequence.stop();
        if (!animated) {
            displayedPage = requestedPage;
            contentOpacity = 1;
            settled();
        } else {
            sequence.start();
        }
    }
    SequentialAnimation {
        id: sequence
        NumberAnimation { target: transition; property: "contentOpacity"; to: 0; duration: 180; easing.type: Easing.InOutSine }
        ScriptAction { script: transition.displayedPage = transition.requestedPage }
        NumberAnimation { target: transition; property: "contentOpacity"; to: 1; duration: 360; easing.type: Easing.OutQuint }
        ScriptAction { script: transition.settled() }
    }
}
