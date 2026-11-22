import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Controls.Material 2.15
import QtQuick.Layouts 1.15

Flickable {
    id: root
    contentWidth: width
    contentHeight: contentCol.implicitHeight + 60
    clip: true

    ScrollBar.vertical: AppScrollBar {}

    readonly property Flickable pullSurface: root
    readonly property bool refreshing: hubLoading
    property bool hubLoading: false

    function refresh() {
        if (hubLoading) return;
        hubRequested = false;
        loadHub();
    }

    property var banners: []
    property var recommendations: []
    property var watching: []
    property var discussing: []
    property var collections: []
    property bool randomPending: false
    property bool hubRequested: false

    Component.onCompleted: {
        if (visible) loadHub();
    }

    onVisibleChanged: {
        if (visible) loadHub();
    }

    function loadHub() {
        if (hubRequested) return;

        hubRequested = true;
        hubLoading = true;
        anixApi.fetchHub();
    }

    Connections {
        target: anixApi
        function onHubLoaded(data) {
            root.hubLoading = false;
            if (data.interesting && data.interesting.length > 0) root.banners = data.interesting;
            else if (data.banners && data.banners.length > 0) root.banners = data.banners;
            if (data.recommendations) root.recommendations = data.recommendations;
            if (data.watching) root.watching = data.watching;
            if (data.discussing) root.discussing = data.discussing;
            if (data.collections) root.collections = data.collections;
        }
        function onBrowseSectionLoaded(section, page, collectionId, query, data) {
            if (section !== "random" || !root.randomPending) return;

            root.randomPending = false;
            if (data.release && root.visible) window.openRelease(data.release.id);
            else if (root.visible) randomError.open();
        }
    }

    ColumnLayout {
        id: contentCol
        width: Math.min(parent.width - 48, 1440)
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: 24
        spacing: 32

        RowLayout {
            Layout.fillWidth: true

            Label {
                text: "Обзор"
                color: "#f0e9f8"
                font.pixelSize: 29
                font.weight: Font.DemiBold
            }
            Item { Layout.fillWidth: true }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 320
            radius: 16
            color: "#1d192b"
            clip: true
            visible: root.banners.length > 0

            SwipeView {
                id: bannerSwipe
                anchors.fill: parent

                Repeater {
                    model: root.banners
                    delegate: Item {
                        readonly property var releaseObj: modelData.release

                        Image {
                            anchors.fill: parent
                            source: modelData.image ? modelData.image : (releaseObj ? releaseObj.image : "")
                            fillMode: Image.PreserveAspectCrop
                            mipmap: true
                            smooth: true
                        }

                        Rectangle {
                            anchors.fill: parent
                            gradient: Gradient {
                                GradientStop { position: 0.0; color: "transparent" }
                                GradientStop { position: 0.5; color: "#44000000" }
                                GradientStop { position: 1.0; color: "#e60f0d13" }
                            }
                        }

                        ColumnLayout {
                            anchors.left: parent.left
                            anchors.bottom: parent.bottom
                            anchors.margins: 28
                            spacing: 8

                            Text {
                                text: releaseObj ? releaseObj.title_ru : modelData.title
                                font.pixelSize: 26
                                font.bold: true
                                color: "#ffffff"
                            }

                            Text {
                                text: releaseObj ? (releaseObj.year + " • " + releaseObj.genres) : (modelData.description || "")
                                font.pixelSize: 13
                                color: "#cfbcff"
                            }

                            Button {
                                text: "Смотреть"
                                icon.name: "media-playback-start"
                                Material.background: "#cfbcff"
                                Material.foreground: "#381e72"
                                font.bold: true
                                onClicked: {
                                    var rId = releaseObj ? releaseObj.id : (modelData.action ? parseInt(modelData.action) : 0);
                                    if (rId > 0) {
                                        pageStack.push("qrc:/qml/ReleaseDetailsPage.qml", {
                                            releaseId: rId,
                                            initialData: releaseObj || {}
                                        });
                                    }
                                }
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                var rId = releaseObj ? releaseObj.id : (modelData.action ? parseInt(modelData.action) : 0);
                                if (rId > 0) {
                                    pageStack.push("qrc:/qml/ReleaseDetailsPage.qml", {
                                        releaseId: rId,
                                        initialData: releaseObj || {}
                                    });
                                }
                            }
                        }
                    }
                }
            }

            PageIndicator {
                anchors.bottom: parent.bottom
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottomMargin: 8
                count: bannerSwipe.count
                currentIndex: bannerSwipe.currentIndex
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            Button {
                text: "Популярное"
                onClicked: root.StackView.view.push("qrc:/qml/ReleaseGridPage.qml", { mode: "popular", heading: text })
            }
            Button {
                text: "Расписание"
                onClicked: root.StackView.view.push("qrc:/qml/UpdatesPage.qml")
            }
            Button {
                text: "Коллекции"
                enabled: root.collections.length > 0
                onClicked: root.contentY = Math.min(collectionsSection.y + contentCol.y, root.contentHeight - root.height)
            }
            Button {
                text: "Фильтры"
                onClicked: window.navigateTo(1)
            }
            Item { Layout.fillWidth: true }
            Button {
                text: "Случайный тайтл"
                enabled: !root.randomPending
                onClicked: {
                    root.randomPending = true;
                    anixApi.fetchBrowseSection("random");
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 14
            visible: root.recommendations.length > 0

            Text {
                text: "Рекомендации для вас"
                font.pixelSize: 20
                font.bold: true
                color: "#e6e1e5"
            }

            ListView {
                Layout.fillWidth: true
                Layout.preferredHeight: 280
                orientation: ListView.Horizontal
                spacing: 16
                clip: true
                model: root.recommendations

                delegate: AnimeCard {
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

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 14
            visible: root.watching.length > 0

            Text {
                text: "Сейчас смотрят"
                font.pixelSize: 20
                font.bold: true
                color: "#e6e1e5"
            }

            ListView {
                Layout.fillWidth: true
                Layout.preferredHeight: 280
                orientation: ListView.Horizontal
                spacing: 16
                clip: true
                model: root.watching

                delegate: AnimeCard {
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

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 14
            visible: root.discussing.length > 0

            Text {
                text: "Обсуждаемое сообществом"
                font.pixelSize: 20
                font.bold: true
                color: "#e6e1e5"
            }

            ListView {
                Layout.fillWidth: true
                Layout.preferredHeight: 280
                orientation: ListView.Horizontal
                spacing: 16
                clip: true
                model: root.discussing

                delegate: AnimeCard {
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

        ColumnLayout {
            id: collectionsSection
            Layout.fillWidth: true
            spacing: 12
            visible: root.collections.length > 0

            Label {
                text: "Коллекции"
                color: "#e6e1e5"
                font.pixelSize: 20
                font.bold: true
            }

            ListView {
                Layout.fillWidth: true
                Layout.preferredHeight: 110
                orientation: ListView.Horizontal
                spacing: 10
                clip: true
                model: root.collections

                delegate: Button {
                    required property var modelData
                    width: 230
                    height: 100
                    text: modelData.title || ""
                    onClicked: root.StackView.view.push("qrc:/qml/ReleaseGridPage.qml", {
                        mode: "collection", collectionId: modelData.id, heading: text
                    })

                    contentItem: Label {
                        text: parent.text
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        wrapMode: Text.Wrap
                        maximumLineCount: 3
                        elide: Text.ElideRight
                    }
                }
            }
        }
    }

    Dialog {
        id: randomError
        anchors.centerIn: parent
        title: "Не удалось подобрать тайтл"
        modal: true
        Overlay.modal: Rectangle { color: "#bb000000" }
        standardButtons: Dialog.Ok
        onOpened: standardButton(Dialog.Ok).text = "Понятно"
    }
}
