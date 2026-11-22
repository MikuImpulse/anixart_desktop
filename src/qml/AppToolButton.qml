import QtQuick
import QtQuick.Controls

ToolButton {
    id: control

    hoverEnabled: true

    background: Rectangle {
        radius: Math.min(width, height) / 2
        color: control.down ? "#4a385e"
            : control.highlighted ? "#36294a"
            : control.hovered || control.activeFocus ? "#2d2539" : "transparent"
        border.color: control.visualFocus ? "#cfbcff" : "transparent"

        Behavior on color { ColorAnimation { duration: 100 } }
    }
}
