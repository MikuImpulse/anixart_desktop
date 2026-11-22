import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    id: root

    property var sections: []
    property string selection: ""
    signal activated(string key)

    implicitWidth: rowLayout.implicitWidth + 12
    implicitHeight: 38
    radius: 19
    color: "#201c27"
    border.color: "#383144"
    border.width: 1

    Row {
        id: rowLayout
        anchors.centerIn: parent
        spacing: 2

        Repeater {
            model: root.sections

            delegate: Rectangle {
                id: tabItem
                required property var modelData
                readonly property bool isSelected: root.selection === modelData.key
                readonly property bool isHovered: tabMouse.containsMouse && !isSelected

                implicitHeight: 32
                implicitWidth: Math.max(34, tabContent.implicitWidth + (modelData.label ? 24 : 14))
                radius: 16
                color: isSelected ? "#3d374a" : (isHovered ? "#2e2938" : "transparent")

                Behavior on color { ColorAnimation { duration: 120 } }

                RowLayout {
                    id: tabContent
                    anchors.centerIn: parent
                    spacing: 6

                    Image {
                        visible: !!tabItem.modelData.icon
                        Layout.alignment: Qt.AlignVCenter
                        Layout.preferredWidth: 18
                        Layout.preferredHeight: 18
                        source: tabItem.modelData.icon || ""
                        sourceSize: Qt.size(18, 18)
                        smooth: true
                    }

                    Text {
                        visible: !!tabItem.modelData.label
                        Layout.alignment: Qt.AlignVCenter
                        text: tabItem.modelData.label || ""
                        font.pixelSize: 13
                        font.weight: tabItem.isSelected ? Font.DemiBold : Font.Normal
                        color: tabItem.isSelected ? "#ffffff" : (tabItem.isHovered ? "#ffffff" : "#cac4d0")
                    }
                }

                MouseArea {
                    id: tabMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.activated(tabItem.modelData.key)
                }

                ToolTip.text: modelData.hint || ""
                ToolTip.visible: tabMouse.containsMouse && ToolTip.text.length > 0
            }
        }
    }
}
