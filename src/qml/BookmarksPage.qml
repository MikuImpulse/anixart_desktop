import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Controls.Material 2.15
import QtQuick.Layouts 1.15

Item {
    id: root
    readonly property Flickable pullSurface: bookmarksGrid
    readonly property bool refreshing: isLoading

    function refresh() {
        if (userId <= 0 || isLoading) return;
        setList(currentStatus, Object.assign({}, currentList, {updatedAt: 0}));
        loadCurrentList();
    }

    property int viewSort: 0
    readonly property var filters: [
        {key: "7", label: "Коллекции"}, {key: "0", label: "История"}, {key: "6", label: "Избранное"},
        {key: "1", label: "Смотрю"}, {key: "2", label: "В планах"}, {key: "3", label: "Просмотрено"},
        {key: "4", label: "Отложено"}, {key: "5", label: "Брошено"}
    ]
    readonly property bool showingCollections: currentStatus === 7
    property int currentStatus: 1
    property var userId: 0
    property int requestSerial: 0
    property var lists: ({})
    property var scrollPositions: ({})
    readonly property var currentList: lists[currentStatus] || {}
    readonly property var bookmarksList: {
        const rows = currentList.releases || [];
        if (viewSort === 1)
            return rows.slice().sort((a, b) => (a.title_ru || a.title_original || a.title || "")
                .localeCompare(b.title_ru || b.title_original || b.title || ""));
        if (viewSort === 2)
            return rows.slice().sort((a, b) => (b.grade || 0) - (a.grade || 0));
        return rows;
    }
    readonly property int totalCount: currentList.totalCount || 0
    readonly property bool isLoading: currentList.loading || false

    Component.onCompleted: updateAccount()

    onVisibleChanged: {
        if (visible) loadCurrentList();
    }

    function updateAccount() {
        var account = authManager.isLoggedIn ? authManager.userId : 0;
        if (account === root.userId) return;

        root.userId = account;
        root.lists = {};
        root.scrollPositions = {};
        loadCurrentList();
        restoreScrollPosition();
    }

    function setList(status, list) {
        var updated = Object.assign({}, root.lists);
        updated[status] = list;
        root.lists = updated;
    }

    function loadCurrentList() {
        if (root.userId <= 0) return;

        var status = root.currentStatus;
        var list = root.lists[status];
        if (!list) {
            list = anixApi.cachedProfileList(root.userId, status);
            setList(status, list);
        }
        if (list.loading || (list.updatedAt > 0 && Date.now() - list.updatedAt < 300000)) return;

        var requestId = ++root.requestSerial;
        setList(status, Object.assign({}, list, {loading: true, requestId: requestId, pending: []}));
        anixApi.fetchProfileList(authManager.token, status, 0, requestId, root.userId);
    }

    function selectSort(sort) {
        viewSort = sort;
        bookmarksGrid.positionViewAtBeginning();
    }

    function restoreScrollPosition() {
        var status = root.currentStatus;
        Qt.callLater(function() {
            if (status === root.currentStatus) {
                bookmarksGrid.forceLayout();
                bookmarksGrid.contentY = Math.min(scrollPositions[status] ?? bookmarksGrid.originY,
                    Math.max(bookmarksGrid.originY, bookmarksGrid.originY + bookmarksGrid.contentHeight - bookmarksGrid.height));
            }
        });
    }

    Connections {
        target: anixApi
        function onEpisodeHistoryUpdated() {
            if (root.userId <= 0) return;

            var list = root.lists[0] || anixApi.cachedProfileList(root.userId, 0);
            setList(0, Object.assign({}, list, {updatedAt: 0, loading: false, pending: []}));
            anixApi.invalidateProfileListCache(root.userId, 0);
            if (root.visible && root.currentStatus === 0) root.loadCurrentList();
        }
        function onProfileListLoaded(requestId, status, releases, page, totalPageCount, count) {
            var list = root.lists[status];
            if (!list || list.requestId !== requestId || !list.loading) return;

            var all = list.pending.concat(releases);
            if (releases.length > 0 && (page + 1 < totalPageCount || all.length < count)) {
                setList(status, Object.assign({}, list, {pending: all}));
                anixApi.fetchProfileList(authManager.token, status, page + 1, requestId, root.userId);
                return;
            }

            if (status === root.currentStatus) root.scrollPositions[status] = bookmarksGrid.contentY;
            setList(status, {releases: all, totalCount: count, updatedAt: Date.now()});
            anixApi.cacheProfileList(root.userId, status, all, count);
            if (status === root.currentStatus) restoreScrollPosition();
        }
        function onProfileListFailed(requestId, status) {
            var list = root.lists[status];
            if (!list || list.requestId !== requestId) return;

            setList(status, Object.assign({}, list, {loading: false, pending: [], failed: true}));
        }
        function onBookmarkListsChanged() {
            if (root.userId <= 0) return;

            for (var status = 1; status <= 6; ++status) {
                var list = root.lists[status] || anixApi.cachedProfileList(root.userId, status);
                setList(status, Object.assign({}, list, {updatedAt: 0, loading: false, pending: []}));
                anixApi.invalidateProfileListCache(root.userId, status);
            }
            if (root.visible) root.loadCurrentList();
        }
    }

    Connections {
        target: authManager
        function onAuthChanged() {
            root.updateAccount();
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 24
        spacing: 16

        SectionStrip {
            Layout.alignment: Qt.AlignHCenter
            sections: root.filters
            selection: String(root.currentStatus)
            onActivated: key => {
                const status = Number(key);
                if (status === root.currentStatus) return;

                root.scrollPositions[root.currentStatus] = bookmarksGrid.contentY;
                root.currentStatus = status;
                if (root.showingCollections && root.viewSort === 2) root.viewSort = 0;
                root.loadCurrentList();
                root.restoreScrollPosition();
            }
        }

        RowLayout {
            Layout.fillWidth: true
            visible: authManager.isLoggedIn

            Label {
                Layout.fillWidth: true
                text: root.totalCount + " всего"
                color: "#c2b7cd"
            }

            RoundButton {
                id: sortButton
                readonly property string recentLabel: root.currentStatus === 0 ? "По просмотру" : "По добавлению"
                readonly property var choices: root.showingCollections ? [recentLabel, "По названию"] : [recentLabel, "По названию", "По оценке"]
                text: choices[root.viewSort] + "  ▾"
                leftPadding: 16
                rightPadding: 16
                onClicked: sortMenu.open()

                Menu {
                    id: sortMenu
                    x: parent.width - width
                    y: parent.height

                    MenuItem { text: sortButton.recentLabel; onTriggered: root.selectSort(0) }
                    MenuItem { text: "По названию"; onTriggered: root.selectSort(1) }
                    MenuItem { visible: !root.showingCollections; text: "По оценке"; onTriggered: root.selectSort(2) }
                }
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            Rectangle {
                anchors.fill: parent
                visible: !authManager.isLoggedIn || (!root.isLoading && root.bookmarksList.length === 0)
                radius: 16
                color: "#1d192b"
                border.color: "#36343b"

                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 12

                    Label {
                        Layout.alignment: Qt.AlignHCenter
                        text: !authManager.isLoggedIn ? "Войдите в аккаунт, чтобы просмотреть закладки"
                            : (root.currentList.failed ? "Не удалось загрузить закладки" : "В этом списке пока ничего нет")
                        color: "#cac4d0"
                        font.pixelSize: 18
                    }

                    Button {
                        Layout.alignment: Qt.AlignHCenter
                        visible: !authManager.isLoggedIn || root.currentList.failed === true
                        text: authManager.isLoggedIn ? "Повторить" : "Войти"
                        onClicked: {
                            if (authManager.isLoggedIn) {
                                root.loadCurrentList();
                            } else {
                                openAuthDialog();
                            }
                        }
                    }
                }
            }

            BusyIndicator {
                anchors.centerIn: parent
                visible: root.isLoading && root.bookmarksList.length === 0
                running: visible
                Material.accent: "#cfbcff"
            }

            GridView {
                id: bookmarksGrid
                anchors.fill: parent
                visible: authManager.isLoggedIn && root.bookmarksList.length > 0
                clip: true
                model: root.bookmarksList

                readonly property int columns: Math.max(2, Math.floor(width / 190))
                cellWidth: width / columns
                cellHeight: 290

                ScrollBar.vertical: AppScrollBar {}

                delegate: Item {
                    width: bookmarksGrid.cellWidth
                    height: bookmarksGrid.cellHeight

                    AnimeCard {
                        anchors.centerIn: parent
                        width: bookmarksGrid.cellWidth - 16
                        height: bookmarksGrid.cellHeight - 16
                        compact: root.showingCollections
                        subtitle: root.showingCollections ? (modelData.release_count || 0) + " тайтлов" : ""
                        releaseData: root.showingCollections ? {image: modelData.image, title_ru: modelData.title} : modelData
                        onClicked: {
                            if (root.showingCollections) {
                                pageStack.push("qrc:/qml/ReleaseGridPage.qml", {
                                    mode: "collection", collectionId: modelData.id, heading: modelData.title
                                });
                            } else {
                                pageStack.push("qrc:/qml/ReleaseDetailsPage.qml", {
                                    releaseId: modelData.id, initialData: modelData
                                });
                            }
                        }
                    }
                }
            }
        }
    }
}
