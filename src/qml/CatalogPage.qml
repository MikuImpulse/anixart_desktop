import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Controls.Material 2.15
import QtQuick.Layouts 1.15

Item {
    id: root
    property var releasesList: []
    property int currentPage: 0
    property string activeSearchQuery: ""
    property int selectedChip: 0
    readonly property Flickable pullSurface: catalogGrid
    readonly property bool refreshing: anixApi.isLoading

    function refresh() {
        if (activeSearchQuery) anixApi.search(activeSearchQuery, 0);
        else anixApi.fetchCatalog(0, selectedChip === 2 ? 6 : 0, selectedChip === 3 ? 2 : 0, selectedChip === 1 ? 2 : 0);
    }

    function focusSearch() { searchField.forceActiveFocus(); }

    Component.onCompleted: {
        anixApi.fetchCatalog(0, 0);
    }

    Connections {
        target: anixApi
        function onSearchLoaded(releases) {
            root.releasesList = releases;
        }
        function onCatalogLoaded(releases) {
            root.releasesList = releases;
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 24
        spacing: 20

        RowLayout {
            Layout.fillWidth: true
            spacing: 16

            Text {
                text: "Каталог"
                font.pixelSize: 28
                font.bold: true
                color: "#e6e1e5"
            }

            Item { Layout.fillWidth: true }

            Rectangle {
                Layout.preferredWidth: 360
                Layout.preferredHeight: 44
                radius: 22
                color: "#1d192b"
                border.color: searchField.activeFocus ? "#cfbcff" : "#49454f"
                border.width: searchField.activeFocus ? 2 : 1

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 16
                    anchors.rightMargin: 12
                    spacing: 10

                    Image {
                        Layout.alignment: Qt.AlignVCenter
                        width: 18
                        height: 18
                        source: "qrc:/assets/icons/search.svg"
                        sourceSize: Qt.size(18, 18)
                        opacity: 0.7
                    }

                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        TextInput {
                            id: searchField
                            anchors.fill: parent
                            verticalAlignment: TextInput.AlignVCenter
                            color: "#e6e1e5"
                            font.pixelSize: 14
                            selectByMouse: true
                            clip: true
                            onAccepted: {
                                root.activeSearchQuery = text.trim();
                                root.refresh();
                            }
                        }

                        Text {
                            anchors.fill: parent
                            verticalAlignment: Text.AlignVCenter
                            text: "Поиск аниме, авторов, студий..."
                            color: "#938f99"
                            font.pixelSize: 14
                            visible: searchField.text.length === 0
                        }
                    }

                    Item {
                        visible: searchField.text.length > 0
                        Layout.preferredWidth: 24
                        Layout.preferredHeight: 24
                        Layout.alignment: Qt.AlignVCenter

                        Image {
                            anchors.centerIn: parent
                            width: 14
                            height: 14
                            source: "qrc:/assets/icons/close.svg"
                            sourceSize: Qt.size(14, 14)
                            opacity: 0.8
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                searchField.text = "";
                                root.activeSearchQuery = "";
                                root.refresh();
                            }
                        }
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            Repeater {
                model: ["Все релизы", "Онгоинги", "Популярные", "Фильмы"]
                delegate: Button {
                    text: modelData
                    checkable: true
                    checked: root.selectedChip === index
                    Material.background: checked ? "#4f378b" : "#1d192b"
                    Material.foreground: checked ? "#ffffff" : "#cac4d0"
                    onClicked: {
                        root.selectedChip = index;
                        root.activeSearchQuery = "";
                        searchField.clear();
                        root.refresh();
                    }
                }
            }

            Item { Layout.fillWidth: true }

            Text {
                text: "Найдено: " + root.releasesList.length
                font.pixelSize: 13
                color: "#938f99"
            }
        }

        BusyIndicator {
            Layout.alignment: Qt.AlignHCenter
            visible: anixApi && anixApi.isLoading
            running: anixApi && anixApi.isLoading
        }

        GridView {
            id: catalogGrid
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            model: root.releasesList

            readonly property int columns: Math.max(2, Math.floor(width / 190))
            cellWidth: width / columns
            cellHeight: 290

            ScrollBar.vertical: AppScrollBar {}

            delegate: Item {
                width: catalogGrid.cellWidth
                height: catalogGrid.cellHeight

                AnimeCard {
                    anchors.centerIn: parent
                    width: catalogGrid.cellWidth - 16
                    height: catalogGrid.cellHeight - 16
                    releaseData: modelData
                    onClicked: {
                        pageStack.push("qrc:/qml/ReleaseDetailsPage.qml", {
                            releaseId: modelData.id,
                            initialData: modelData
                        });
                    }
                }
            }
        }
    }
}
