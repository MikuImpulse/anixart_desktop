import QtQuick
import QtQuick.Controls 2.15
import QtQuick.Controls.Material 2.15
import QtQuick.Layouts 1.15
import Anixart 1.0

Item {
    id: root
    property var releaseData: null
    property bool compact: false
    property string subtitle: ""
    signal clicked()

    implicitWidth: 170
    implicitHeight: 270

    Rectangle {
        id: cardBg
        anchors.fill: parent
        radius: 12
        color: "#1d192b"

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: root.height - (root.compact ? (root.subtitle ? 60 : 50) : 70)
                radius: cardBg.radius
                bottomLeftRadius: 0
                bottomRightRadius: 0
                color: "#2b2930"

                CircleImage {
                    anchors.fill: parent
                    source: (root.releaseData && root.releaseData.image) ? root.releaseData.image : ""
                    cornerRadius: cardBg.radius
                    squareBottom: true
                }

                Rectangle {
                    visible: !root.compact && !!root.releaseData && root.releaseData.grade > 0
                    anchors.top: parent.top
                    anchors.right: parent.right
                    anchors.margins: 10
                    height: 22
                    width: ratingRow.width + 12
                    radius: 11
                    color: "#cc000000"

                    Row {
                        id: ratingRow
                        anchors.centerIn: parent
                        spacing: 4
                        Image {
                            width: 12
                            height: 12
                            anchors.verticalCenter: parent.verticalCenter
                            source: "qrc:/assets/icons/star.svg"
                            sourceSize: Qt.size(12, 12)
                        }
                        Text {
                            text: root.releaseData ? Number(root.releaseData.grade).toFixed(1) : ""
                            font.pixelSize: 11
                            font.bold: true
                            color: "#ffffff"
                        }
                    }
                }

                Rectangle {
                    visible: !root.compact && !!(root.releaseData && root.releaseData.year)
                    anchors.bottom: parent.bottom
                    anchors.left: parent.left
                    anchors.margins: 8
                    height: 20
                    width: yearText.width + 10
                    radius: 10
                    color: "#cc000000"

                    Text {
                        id: yearText
                        anchors.centerIn: parent
                        text: root.releaseData && root.releaseData.year ? String(root.releaseData.year) : ""
                        font.pixelSize: 10
                        color: "#cac4d0"
                    }
                }
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 2

                    Text {
                        Layout.fillWidth: true
                        text: (root.releaseData && root.releaseData.title_ru) ? root.releaseData.title_ru : (root.releaseData ? root.releaseData.title_original : "")
                        font.pixelSize: root.compact ? 11 : 13
                        font.bold: true
                        color: "#e6e1e5"
                        elide: Text.ElideRight
                        maximumLineCount: 2
                        wrapMode: Text.Wrap
                    }

                    Text {
                        Layout.fillWidth: true
                        visible: !root.compact || root.subtitle.length > 0
                        text: root.compact ? root.subtitle : (root.releaseData?.genres || "")
                        font.pixelSize: 11
                        color: "#938f99"
                        elide: Text.ElideRight
                    }
                }
            }
        }

        Rectangle {
            anchors.fill: parent
            radius: cardBg.radius
            color: "transparent"
            border.color: mouseArea.containsMouse ? "#cfbcff" : "#36343b"
            border.width: mouseArea.containsMouse ? 2 : 1

            Behavior on border.color { ColorAnimation { duration: 150 } }
        }

        MouseArea {
            id: mouseArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.clicked()
        }
    }
}
