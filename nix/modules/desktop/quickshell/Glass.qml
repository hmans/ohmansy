import QtQuick

Rectangle {
    property color tint: theme.background
    Theme { id: theme }
    color: tint
    radius: theme.radius
    border.width: 1
    border.color: theme.border
}
