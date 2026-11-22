import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ColumnLayout {
    id: root

    required property string section
    required property var entityId
    property var voters: []
    property int total: 0
    property int nextPage: 0
    property bool loading: false
    property bool failed: false
    property bool hasMore: true
    readonly property var filters: [0, 2, 1]
    readonly property int filter: filters[filterBox.currentIndex] ?? 0
    readonly property Flickable pullSurface: list
    readonly property bool refreshing: loading

    function refresh() { load(0); }

    function load(page) {
        if (loading) return;
        loading = true;
        failed = false;
        anixApi.fetchVoters(section, entityId, page, filter, authManager.token);
    }

    Component.onCompleted: refresh()

    Connections {
        target: anixApi
        function onVotersLoaded(section, entityId, page, filter, rows, total, hasMore, success) {
            if (!root.loading || section !== root.section || entityId !== root.entityId || filter !== root.filter) return;
            root.loading = false;
            root.failed = !success;
            if (!success) return;
            root.voters = page === 0 ? rows : root.voters.concat(rows);
            root.total = total;
            root.nextPage = page + 1;
            root.hasMore = hasMore && rows.length > 0;
        }
    }

    RowLayout {
        Layout.fillWidth: true
        Layout.margins: 16

        AppToolButton {
            icon.source: "qrc:/assets/icons/back.svg"
            Accessible.name: "Назад"
            onClicked: root.StackView.view.pop()
        }

        Label { text: "Оценки"; font.pixelSize: 22; font.bold: true; Layout.fillWidth: true }
    }

    ColumnLayout {
        Layout.maximumWidth: 720
        Layout.alignment: Qt.AlignHCenter
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.leftMargin: 24
        Layout.rightMargin: 24

        RowLayout {
            Layout.fillWidth: true
            Label { text: "Всего голосов · " + root.total; Layout.fillWidth: true }
            ComboBox {
                id: filterBox
                Accessible.name: "Фильтр оценок"
                model: ["Все оценки", "Положительные", "Отрицательные"]
                enabled: !root.loading
                onActivated: {
                    root.voters = [];
                    root.total = 0;
                    root.nextPage = 0;
                    root.refresh();
                }
            }
        }

        ListView {
            id: list
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            model: root.voters
            spacing: 4
            ScrollBar.vertical: AppScrollBar {}
            onAtYEndChanged: {
                if (atYEnd && root.hasMore && !root.failed && root.voters.length) root.load(root.nextPage);
            }

            delegate: RowLayout {
                required property var modelData
                width: ListView.view.width
                spacing: 8

                IdentityButton {
                    Layout.maximumWidth: parent.width * 0.85
                    text: modelData.login || "Пользователь"
                    avatarSource: modelData.avatar || ""
                    badgeSource: modelData.badge_url || ""
                    enabled: modelData.id > 0
                    onClicked: window.openProfile(modelData.id)
                }

                Item { Layout.fillWidth: true }
                Label {
                    Layout.rightMargin: 16
                    visible: modelData.vote === 1 || modelData.vote === 2
                    text: modelData.vote === 1 ? "−" : "+"
                    color: modelData.vote === 1 ? "#ffb4ab" : "#8ae69c"
                    font.pixelSize: 18
                }
            }
        }

        BusyIndicator { running: root.loading; visible: running; Layout.alignment: Qt.AlignHCenter }
        Label {
            Layout.alignment: Qt.AlignHCenter
            visible: !root.loading && (root.failed || !root.voters.length)
            text: root.failed ? "Не удалось загрузить оценки" : "Оценок нет"
        }
        Button {
            Layout.alignment: Qt.AlignHCenter
            visible: !root.loading && (root.failed || (root.hasMore && root.voters.length > 0))
            text: root.failed ? "Повторить" : "Ещё оценки"
            onClicked: root.load(root.nextPage)
        }
    }
}
