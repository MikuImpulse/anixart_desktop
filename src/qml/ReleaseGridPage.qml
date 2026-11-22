import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import QtCore

Item {
    id: root

    property string mode: "home"
    property var collectionId: 0
    property string heading: mode === "home" ? "Главная" : ""
    property string category: mode === "home" ? personalSettings.defaultTab : "popular"
    readonly property Flickable pullSurface: releases
    readonly property bool refreshing: loading
    readonly property var tabs: [
        { label: "Моя вкладка", key: "my" }, { label: "Аниме", key: "anime" },
        { label: "Дунхуа", key: "donghua" }, { label: "Последнее", key: "latest" },
        { label: "Онгоинги", key: "ongoing" }, { label: "Анонсы", key: "announced" },
        { label: "Завершённые", key: "finished" }, { label: "Фильмы", key: "movies" },
        { label: "OVA", key: "ova" }
    ]
    readonly property var criteria: JSON.parse(personalSettings.filters)
    readonly property bool hasCriteria: Object.keys(criteria).length > 0
    readonly property string requestQuery: category === "my" ? "my:" + personalSettings.filters : category
    readonly property string cacheKey: requestQuery + "|" + (category === "my" ? "account:" + authManager.userId : "public")

    Settings {
        id: personalSettings
        category: "PersonalTab"
        property string defaultTab: "anime"
        property string filters: "{}"
    }
    property var snapshots: ({})
    property var pendingPages: ({})
    readonly property var snapshot: snapshots[cacheKey] || null
    readonly property bool loading: pendingPages[requestQuery] !== undefined
    property bool failed: false

    ListModel {
        id: emptyReleaseModel
    }

    Component {
        id: releaseModelComponent

        ListModel {
        }
    }

    function ensureSnapshot(key) {
        if (snapshots[key]) return snapshots[key];

        const state = {
            model: releaseModelComponent.createObject(root),
            indexes: ({}),
            page: -1,
            hasMore: true,
            contentY: 0
        };
        const updated = Object.assign({}, snapshots);
        updated[key] = state;
        snapshots = updated;
        return state;
    }

    function appendRows(state, rows) {
        let appended = 0;
        for (let index = 0; index < rows.length; ++index) {
            const release = rows[index];
            if (!release || release.id === undefined || release.id === null) continue;

            const releaseId = String(release.id);
            if (state.indexes[releaseId] !== undefined) {
                state.model.setProperty(state.indexes[releaseId], "release", release);
            } else {
                state.indexes[releaseId] = state.model.count;
                state.model.append({release: release});
                ++appended;
            }
        }
        return appended;
    }

    function pageHasMore(page, rows, state, data) {
        const totalPages = Number(data.total_page_count || 0);
        const totalCount = Number(data.total_count || 0);
        return rows.length > 0 && (page < totalPages || state.model.count < totalCount
            || (mode !== "collection" && rows.length >= 25));
    }

    function restoreViewport(state) {
        Qt.callLater(function() {
            if (root.snapshot !== state) return;
            releases.contentY = Math.max(0, Math.min(state.contentY, releases.contentHeight - releases.height));
            releases.prefetchIfNeeded();
        });
    }

    function selectCategory(value) {
        if (root.category === value) return;

        if (root.snapshot) root.snapshot.contentY = releases.contentY;
        root.category = value;
        root.failed = false;
        const state = root.snapshot;
        if (state) {
            restoreViewport(state);
        } else {
            releases.positionViewAtBeginning();
            loadPage(0);
        }
    }

    function refresh() { loadPage(0); }

    function loadPage(page) {
        if (pendingPages[requestQuery] !== undefined || (category === "my" && !hasCriteria)) return;

        const state = ensureSnapshot(cacheKey);
        if (page > 0 && (!state.hasMore || page <= state.page)) return;

        const userId = category === "my" ? authManager.userId : 0;
        const pending = Object.assign({}, pendingPages);
        pending[requestQuery] = {page: page, cacheKey: cacheKey, userId: userId};
        pendingPages = pending;
        if (mode === "home" && page === 0 && state.page < 0 && state.model.count === 0)
            appendRows(state, anixApi.cachedReleaseGrid(requestQuery, userId));

        failed = false;
        anixApi.fetchBrowseSection(mode === "collection" ? "collection" : "releaseGrid", page,
                                   collectionId, category === "my" ? authManager.token : "", requestQuery);
    }

    Component.onCompleted: loadPage(0)

    Connections {
        target: anixApi
        function onBrowseSectionLoaded(section, page, id, query, data) {
            const request = root.pendingPages[query];
            if (section !== (root.mode === "collection" ? "collection" : "releaseGrid") || id !== root.collectionId
                || !request || request.page !== page) return;

            const pending = Object.assign({}, root.pendingPages);
            delete pending[query];
            root.pendingPages = pending;

            if (data.code !== 0) {
                if (request.cacheKey === root.cacheKey) root.failed = true;
                else if (root.category === "my" && (!root.snapshot || root.snapshot.page < 0))
                    Qt.callLater(function() { root.loadPage(0); });
                return;
            }

            const state = root.snapshots[request.cacheKey];
            if (!state) return;

            const rows = data.content || data.releases || [];
            const prefixChanged = page === 0 && state.model.count > 0
                && (rows.length < Math.min(25, state.model.count) || rows.some((release, index) =>
                    !release || index >= state.model.count || String(state.model.get(index).release.id) !== String(release.id)));
            if (prefixChanged) {
                state.model.clear();
                state.indexes = ({});
                state.page = -1;
            }
            const appended = root.appendRows(state, rows);
            if (page === 0 && root.mode === "home" && (!query.startsWith("my:") || request.cacheKey === root.cacheKey))
                anixApi.cacheReleaseGrid(query, request.userId, rows);
            if (page === 0 && state.page < 0) state.page = 0;
            else if (page > 0) state.page = Math.max(state.page, page);

            if (page > 0 && appended === 0) state.hasMore = false;
            else if (page !== 0 || state.page === 0) state.hasMore = root.pageHasMore(page, rows, state, data);

            if (request.cacheKey === root.cacheKey) {
                Qt.callLater(releases.prefetchIfNeeded);
            } else if (root.category === "my" && (!root.snapshot || root.snapshot.page < 0)) {
                Qt.callLater(function() { root.loadPage(0); });
            }
        }
    }

    Connections {
        target: authManager
        function onAuthChanged() {
            if (root.mode !== "home" || root.category !== "my") return;
            root.failed = false;
            root.loadPage(0);
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 24
        spacing: 14

        RowLayout {
            Layout.fillWidth: true
            visible: root.mode !== "home"
            Button {
                text: "Назад"
                onClicked: root.StackView.view.pop()
            }
            Label {
                text: root.heading
                color: "#f0e9f8"
                font.pixelSize: 22
                font.weight: Font.DemiBold
            }
        }

        SectionStrip {
            id: categoryBar
            Layout.alignment: Qt.AlignHCenter
            visible: root.mode === "home"
            selection: root.category
            sections: [{key: "filters", icon: "qrc:/assets/icons/tune.svg", hint: "Настройки вкладки"}].concat(root.tabs)
            onActivated: key => {
                if (key === "filters") tabMenu.open();
                else root.selectCategory(key);
            }

            Menu {
                id: tabMenu
                y: categoryBar.height + 4
                MenuItem {
                    text: "Изменить вкладку по умолч."
                    icon.source: "qrc:/assets/icons/home.svg"
                    onTriggered: Qt.callLater(function() { defaultTabDialog.open(); })
                }
                MenuItem {
                    text: "Настроить мою вкладку"
                    icon.source: "qrc:/assets/icons/tune.svg"
                    onTriggered: personalDialog.open()
                }
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            BusyIndicator { anchors.centerIn: parent; running: root.loading && releases.count === 0 }

            ColumnLayout {
                anchors.centerIn: parent
                z: 1
                visible: !root.loading && releases.count === 0
                spacing: 12

                Image {
                    Layout.alignment: Qt.AlignHCenter
                    visible: root.category === "my" && !root.hasCriteria
                    source: "qrc:/assets/empty_tab_ed.png"
                    sourceSize: Qt.size(190, 190)
                    fillMode: Image.PreserveAspectFit
                    mipmap: true
                }

                Label {
                    Layout.alignment: Qt.AlignHCenter
                    font.pixelSize: 20
                    font.weight: Font.DemiBold
                    text: root.failed ? "Не удалось загрузить тайтлы"
                        : (root.category === "my" && !root.hasCriteria ? "Это ваша вкладка" : "Тайтлов пока нет")
                    color: "#f0e9f8"
                }

                Label {
                    Layout.alignment: Qt.AlignHCenter
                    visible: root.category === "my" && !root.hasCriteria
                    text: "Настройте её под себя и укажите,\nчто хотели бы здесь видеть"
                    horizontalAlignment: Text.AlignHCenter
                    font.pixelSize: 14
                    color: "#cac0d5"
                }

                Button {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.preferredWidth: 140
                    Layout.preferredHeight: 40
                    visible: root.category === "my"
                    text: "Настроить"
                    font.bold: true
                    Material.background: "#e6e0e9"
                    Material.foreground: "#1d192b"
                    onClicked: personalDialog.open()
                }
            }

            GridView {
                id: releases
                anchors.fill: parent
                clip: true
                model: root.snapshot ? root.snapshot.model : emptyReleaseModel
                readonly property int columns: Math.max(3, Math.floor(width / (width < 1060 ? 174 : 188)))
                cellWidth: width / columns
                cellHeight: Math.min(Math.round(cellWidth * 1.48 + 46), Math.max(240, height))
                ScrollBar.vertical: AppScrollBar {}

                function prefetchIfNeeded() {
                    if (!root.snapshot || root.loading || root.failed || !root.snapshot.hasMore) return;
                    if (contentY + height * 4 >= contentHeight) root.loadPage(root.snapshot.page + 1);
                }

                onContentYChanged: prefetchIfNeeded()
                onHeightChanged: prefetchIfNeeded()
                onMovementEnded: prefetchIfNeeded()

                delegate: Item {
                    required property var release
                    width: releases.cellWidth
                    height: releases.cellHeight

                    AnimeCard {
                        anchors.centerIn: parent
                        width: parent.width - 12
                        height: parent.height - 12
                        releaseData: parent.release
                        onClicked: window.openRelease(releaseData.id)
                    }
                }
            }
        }
    }
    Dialog {
        id: defaultTabDialog
        parent: Overlay.overlay
        anchors.centerIn: parent
        width: Math.min(420, parent.width - 32)
        modal: true
        Overlay.modal: Rectangle { color: "#bb000000" }
        title: "Вкладка по умолчанию"
        Material.accent: "#cfbcff"

        ButtonGroup {
            id: defaultTabGroup
        }

        contentItem: ScrollView {
            implicitHeight: Math.min(defaultTabChoices.implicitHeight, defaultTabDialog.parent.height - 110)
            contentWidth: availableWidth
            clip: true

            ColumnLayout {
                id: defaultTabChoices
                width: parent.width
                spacing: 0

                Repeater {
                    model: root.tabs
                    delegate: RadioButton {
                        required property var modelData
                        Layout.fillWidth: true
                        text: modelData.label
                        checked: personalSettings.defaultTab === modelData.key
                        ButtonGroup.group: defaultTabGroup
                        onClicked: {
                            root.selectCategory(modelData.key);
                            personalSettings.defaultTab = modelData.key;
                            personalSettings.sync();
                            defaultTabDialog.close();
                        }
                    }
                }
            }
        }
    }

    PersonalTabDialog {
        id: personalDialog
        parent: Overlay.overlay
        criteria: root.criteria
        onCriteriaSelected: filters => {
            personalSettings.filters = JSON.stringify(filters);
            personalSettings.sync();
            root.failed = false;
            root.selectCategory("my");
            if (!root.snapshot || root.snapshot.model.count === 0) root.loadPage(0);
        }
    }
}
