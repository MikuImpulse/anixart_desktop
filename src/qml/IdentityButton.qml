import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Anixart 1.0

AppToolButton {
    id: control

    property string avatarSource: ""
    property string badgeSource: ""
    property string subtitle: ""
    property int avatarSize: 32
    property bool showName: true
    property bool online: false
    property bool showChevron: false

    leftPadding: 5
    rightPadding: showName ? 12 : 5
    topPadding: 4
    bottomPadding: 4
    Accessible.name: text
    HoverHandler { enabled: control.enabled; cursorShape: Qt.PointingHandCursor }

    contentItem: RowLayout {
        spacing: 8

        Item {
            Layout.preferredWidth: control.avatarSize
            Layout.preferredHeight: control.avatarSize
            Layout.alignment: Qt.AlignVCenter

            CircleImage {
                anchors.fill: parent
                source: control.avatarSource
                visible: control.avatarSource.length > 0
            }

            Rectangle {
                anchors.fill: parent
                visible: !control.avatarSource
                radius: width / 2
                color: "#4f378b"

                Label {
                    anchors.centerIn: parent
                    text: control.text.substring(0, 1).toUpperCase()
                    font.bold: true
                    color: "#f4ebff"
                }
            }

            Rectangle {
                width: 10
                height: 10
                radius: 5
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                visible: control.online
                color: "#47d16c"
                border.color: "#1e1929"
                border.width: 2
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            visible: control.showName
            spacing: 1

            RowLayout {
                Layout.fillWidth: true
                spacing: 5

                Label {
                    Layout.maximumWidth: parent.width > 0
                        ? Math.max(0, parent.width - (badge.visible ? badge.width + parent.spacing : 0)) : Number.POSITIVE_INFINITY
                    text: control.text
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    font.weight: Font.DemiBold
                    color: "#eee7f4"
                }

                Image {
                    id: badge
                    Layout.preferredWidth: 16
                    Layout.preferredHeight: 16
                    source: control.badgeSource
                    visible: control.badgeSource.length > 0
                    fillMode: Image.PreserveAspectFit
                    mipmap: true
                }

                Item { Layout.fillWidth: true }
            }

            Label {
                Layout.fillWidth: true
                visible: control.subtitle.length > 0
                text: control.subtitle
                textFormat: Text.PlainText
                elide: Text.ElideRight
                font.pixelSize: 12
                color: "#b6aabf"
            }
        }

        Label {
            Layout.alignment: Qt.AlignVCenter
            visible: control.showChevron
            text: "›"
            font.pixelSize: 20
            color: "#b6aabf"
        }
    }
}
