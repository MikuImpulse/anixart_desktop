import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: root

    required property string section
    required property var entityId
    property string heading: "Комментарии"
    property var focusCommentId: 0
    property bool canComment: true
    property var initialReplyProfile: null
    readonly property Flickable pullSurface: scroll
    readonly property bool refreshing: discussion.loading

    function refresh() {
        discussion.load(0);
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 24
            Layout.rightMargin: 24
            Layout.topMargin: 12

            AppToolButton {
                icon.source: "qrc:/assets/icons/back.svg"
                Accessible.name: "Назад"
                onClicked: root.StackView.view.pop()
            }

            Label {
                Layout.fillWidth: true
                text: root.heading
                font.pixelSize: 23
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }
        }

        Flickable {
            id: scroll
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentWidth: width
            contentHeight: discussion.implicitHeight + 32
            clip: true

            ScrollBar.vertical: AppScrollBar {}

            Discussion {
                id: discussion
                anchors.horizontalCenter: parent.horizontalCenter
                y: 16
                width: Math.min(root.width - 48, 920)
                section: root.section
                entityId: root.entityId
                canComment: root.canComment
                focusCommentId: root.focusCommentId
                composerHost: dock
                Component.onCompleted: {
                    if (root.initialReplyProfile)
                        Qt.callLater(function() { discussion.setReply(root.focusCommentId, root.initialReplyProfile); });
                }
            }
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: "#3a3048" }

        ColumnLayout {
            id: dock
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignHCenter
            Layout.maximumWidth: Math.min(root.width - 48, 920)
            Layout.topMargin: 12
            Layout.bottomMargin: 12 + window.navigationDockInset
        }
    }
}
