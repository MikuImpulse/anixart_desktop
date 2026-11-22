import QtQuick 2.15
import QtQuick.Controls 2.15

ScrollBar {
    id: control
    hoverEnabled: true
    active: hovered || pressed
    policy: ScrollBar.AsNeeded

    implicitWidth: hovered || pressed ? 6 : 3
    implicitHeight: hovered || pressed ? 6 : 3

    contentItem: Rectangle {
        implicitWidth: control.hovered || control.pressed ? 6 : 3
        implicitHeight: control.hovered || control.pressed ? 6 : 3
        radius: width / 2
        color: control.pressed ? "#e8def8" : "#cfbcff"
        opacity: control.hovered || control.pressed ? 0.9 : 0.25

        Behavior on implicitWidth { NumberAnimation { duration: 150 } }
        Behavior on opacity { NumberAnimation { duration: 150 } }
        Behavior on color { ColorAnimation { duration: 150 } }
    }

    background: Rectangle {
        color: "transparent"
    }
}
