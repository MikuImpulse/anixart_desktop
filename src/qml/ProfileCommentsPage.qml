import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Anixart 1.0

Item {
    id: root

    required property var userId
    property string activeTab: "release"
    property var comments: []
    property bool loading: false
    property int totalCount: 0
    property int currentPage: 0
    property int sort: 1
    readonly property Flickable pullSurface: list
    readonly property bool refreshing: loading
    readonly property bool hasMore: comments.length < totalCount

    function load(page) {
        if (loading) return;

        loading = true;
        anixApi.fetchProfileComments(userId, page, activeTab, authManager.token, sort);
    }

    function refresh() {
        load(0);
    }

    Component.onCompleted: refresh()

    Connections {
        target: anixApi

        function onProfileCommentsLoaded(id, type, rows, page, total) {
            if (id !== root.userId || type !== root.activeTab || !root.loading) return;

            root.loading = false;
            root.comments = page === 0 ? rows : root.comments.concat(rows);
            root.totalCount = rows.length ? total : root.comments.length;
            root.currentPage = page;
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 24
        spacing: 12

        RowLayout {
            Layout.fillWidth: true

            AppToolButton {
                icon.source: "qrc:/assets/icons/back.svg"
                Accessible.name: "Назад"
                onClicked: root.StackView.view.pop()
            }

            Label {
                Layout.fillWidth: true
                text: "Комментарии"
                font.pixelSize: 23
                font.weight: Font.DemiBold
            }
        }

        SectionStrip {
            Layout.alignment: Qt.AlignHCenter
            selection: root.activeTab
            sections: [{key: "release", label: "К релизам"}, {key: "collection", label: "К коллекциям"}, {key: "article", label: "К записям"}]
            enabled: !root.loading
            onActivated: key => {
                if (root.activeTab === key) return;
                root.activeTab = key;
                root.refresh();
            }
        }

        RowLayout {
            Layout.fillWidth: true

            Label { Layout.fillWidth: true; text: root.totalCount + " всего"; color: "#cac1d0" }
            ComboBox {
                model: ["Сначала новые", "Сначала старые", "По рейтингу"]
                currentIndex: root.sort - 1
                enabled: !root.loading
                onActivated: {
                    root.sort = currentIndex + 1;
                    root.refresh();
                }
            }
        }

        Label {
            Layout.alignment: Qt.AlignHCenter
            visible: !root.loading && list.count === 0
            text: "Здесь пока нет комментариев"
            color: "#cac1d0"
        }

        ListView {
            id: list
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            model: root.comments
            spacing: 10
            ScrollBar.vertical: AppScrollBar {}

            delegate: Rectangle {
                id: entry
                required property var modelData
                readonly property var profile: modelData.profile || modelData.creator
                readonly property var subject: modelData.release || modelData.collection || modelData.article
                readonly property int score: modelData.vote_count || 0
                property bool revealed: false
                width: list.width
                implicitHeight: content.implicitHeight + 24
                radius: 14
                color: "#211b2a"

                ColumnLayout {
                    id: content
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 5

                    RowLayout {
                        Layout.fillWidth: true

                        IdentityButton {
                            Layout.maximumWidth: parent.width * 0.8
                            avatarSize: 30
                            text: entry.profile?.login || "Пользователь"
                            avatarSource: entry.profile?.avatar || ""
                            badgeSource: entry.profile?.badge_url || ""
                            enabled: entry.profile?.id > 0
                            onClicked: window.openProfile(entry.profile.id)
                        }

                        Item { Layout.fillWidth: true }

                        Label {
                            text: (entry.score > 0 ? "+" : "") + entry.score
                            color: entry.score > 0 ? "#9bd3ae" : entry.score < 0 ? "#ffb4ab" : "#c8bbd3"
                        }
                    }

                    AppToolButton {
                        Layout.fillWidth: true
                        visible: !!entry.subject?.id
                        text: (entry.subject?.title_ru || entry.subject?.title || entry.subject?.payload?.title || "Открыть обсуждение") + " ›"
                        onClicked: {
                            if (entry.modelData.release?.id)
                                window.openReleaseComments(entry.subject.id, entry.subject.title_ru, entry.modelData.id);
                            else if (entry.modelData.article?.id)
                                window.openArticle(entry.modelData.article);
                            else if (entry.modelData.collection?.id)
                                root.StackView.view.push("qrc:/qml/ReleaseGridPage.qml",
                                    {mode: "collection", collectionId: entry.subject.id, heading: entry.subject.title || "Коллекция"});
                        }
                    }

                    RoundButton {
                        visible: !!entry.modelData.is_spoiler
                        text: entry.revealed ? "Скрыть спойлер" : "Показать спойлер"
                        highlighted: true
                        onClicked: entry.revealed = !entry.revealed
                    }

                    Label {
                        Layout.fillWidth: true
                        visible: !entry.modelData.is_spoiler || entry.revealed
                        text: entry.modelData.message || ""
                        textFormat: Text.PlainText
                        wrapMode: Text.Wrap
                    }

                    Label {
                        text: entry.modelData.timestamp ? Qt.formatDateTime(new Date(entry.modelData.timestamp * 1000), "d MMM · hh:mm") : ""
                        color: "#c8bbd3"
                        font.pixelSize: 12
                    }
                }
            }

            footer: Button {
                visible: root.hasMore
                enabled: !root.loading
                text: "Ещё комментарии"
                onClicked: root.load(root.currentPage + 1)
            }
        }
    }
}
