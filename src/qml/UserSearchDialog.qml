import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Controls.Material 2.15
import QtQuick.Layouts 1.15
import Anixart 1.0

Popup {
    id: root
    parent: Overlay.overlay
    anchors.centerIn: parent
    width: Math.min(parent.width - 40, 600)
    height: Math.min(parent.height - 80, 700)
    modal: true
    Overlay.modal: Rectangle { color: "#bb000000" }
    focus: true
    padding: 0
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    background: Rectangle {
        color: "#18151f"
        radius: 24
        border.color: "#35303d"
        border.width: 1
    }

    property var searchResults: []
    property bool loading: false

    onOpened: searchInput.forceActiveFocus()

    onClosed: {
        searchTimer.stop();
        loading = false;
    }

    Connections {
        target: anixApi
        function onProfilesSearchLoaded(profiles, page, total, query) {
            if (!root.opened || query !== searchInput.text.trim()) return;
            root.loading = false;
            root.searchResults = profiles;
        }
    }

    Timer {
        id: searchTimer
        interval: 350
        repeat: false
        onTriggered: {
            if (searchInput.text.trim().length > 0) {
                root.loading = true;
                anixApi.searchProfiles(searchInput.text.trim(), 0);
            } else {
                root.loading = false;
                root.searchResults = [];
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 20
        spacing: 16

        Rectangle {
            Layout.fillWidth: true
            height: 50
            radius: 25
            color: "#25212d"
            border.color: searchInput.activeFocus ? "#cfbcff" : "#36323f"
            border.width: 1

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                spacing: 12

                Image {
                    source: "qrc:/assets/icons/search.svg"
                    width: 20
                    height: 20
                    sourceSize: Qt.size(20, 20)
                }

                TextField {
                    id: searchInput
                    Layout.fillWidth: true
                    Accessible.name: "Поиск пользователей"
                    verticalAlignment: Text.AlignVCenter
                    topPadding: 0
                    bottomPadding: 0

                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        x: parent.leftPadding
                        visible: !searchInput.text
                        text: searchInput.Accessible.name
                        color: "#aaa1b3"
                        font.pixelSize: 15
                    }
                    color: "#ffffff"
                    font.pixelSize: 15
                    background: Item {}
                    onTextChanged: searchTimer.restart()
                }

                Text {
                    visible: searchInput.text.length > 0
                    text: "✕"
                    font.pixelSize: 16
                    color: "#938f99"
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            searchInput.text = "";
                            root.searchResults = [];
                        }
                    }
                }
            }
        }

        BusyIndicator {
            Layout.alignment: Qt.AlignHCenter
            running: root.loading
            visible: running
        }

        Text {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: 40
            visible: !root.loading && searchInput.text.length > 0 && root.searchResults.length === 0
            text: "Пользователи не найдены"
            font.pixelSize: 15
            color: "#938f99"
        }

        ListView {
            id: resultsList
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            model: root.searchResults
            spacing: 10

            delegate: IdentityButton {
                required property var modelData
                width: resultsList.width
                height: 64
                avatarSize: 46
                leftPadding: 14
                rightPadding: 14
                text: modelData.login || "Пользователь"
                subtitle: modelData.badge_name || "Пользователь"
                avatarSource: modelData.avatar || ""
                badgeSource: modelData.badge_url || ""
                online: modelData.is_online === true
                showChevron: true
                enabled: modelData.id > 0
                onClicked: {
                    root.close();
                    window.openProfile(modelData.id);
                }
            }
        }
    }
}
