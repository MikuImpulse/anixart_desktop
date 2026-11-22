import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import Anixart 1.0

Item {
    id: root

    property var channelId: 0
    property var channelData: ({})
    readonly property Flickable pullSurface: posts
    readonly property bool refreshing: loading || channelLoading
    property bool channelLoading: false
    property bool channelFailed: false
    property double feedDate: 0

    property bool searchMode: false
    property var latestChannels: []
    property int selectedChannelFilterId: 0

    function refresh() {
        root.loading = false;
        if (channelId > 0 && !channelLoading) {
            channelLoading = true;
            anixApi.fetchBrowseSection("channel", 0, channelId, authManager.token, "");
        }
        loadPage(0);
    }

    function openSearch() {
        root.searchMode = true;
        Qt.callLater(searchField.forceActiveFocus);
    }

    function closeSearch() {
        root.searchMode = false;
        searchField.text = "";
        root.selectSection("latestFeed", "");
    }

    function selectChannel(chId) {
        if (root.selectedChannelFilterId === chId) {
            root.selectedChannelFilterId = 0;
            root.selectSection("latestFeed", "");
        } else {
            root.selectedChannelFilterId = chId;
            root.selectSection("channelFeed", String(chId));
        }
    }

    property string activeSection: channelId > 0 ? "channelFeed" : "latestFeed"
    property string query: channelId > 0 ? String(channelId) : ""
    property var entries: ({})
    property int lastPage: 0
    property int nextPage: 0
    property bool loading: false
    property bool failed: false
    readonly property string key: activeSection + "|" + query
    readonly property var rosterChannels: activeSection === "subscriptions"
        ? (entries[key]?.channels || []) : latestChannels

    function mergeChannels(existing, incoming) {
        const indexes = ({});
        const merged = [];
        for (let index = 0; index < existing.length; ++index) {
            const channel = existing[index];
            if (!channel || channel.id === undefined || channel.id === null) continue;

            const channelId = String(channel.id);
            if (indexes[channelId] === undefined) {
                indexes[channelId] = merged.length;
                merged.push(channel);
            }
        }
        for (let index = 0; index < incoming.length; ++index) {
            const channel = incoming[index];
            if (!channel || channel.id === undefined || channel.id === null) continue;

            const channelId = String(channel.id);
            if (indexes[channelId] === undefined) {
                indexes[channelId] = merged.length;
                merged.push(channel);
            } else {
                merged[indexes[channelId]] = channel;
            }
        }
        return merged;
    }

    function selectSection(section, text) {
        root.activeSection = section;
        root.query = text;
        root.nextPage = root.entries[root.key]?.nextPage ?? 0;
        root.lastPage = root.entries[root.key]?.lastPage ?? 0;
        root.feedDate = root.entries[root.key]?.date ?? 0;
        root.loading = false;
        root.failed = false;
        posts.positionViewAtBeginning();
        if (!root.entries[root.key]) root.loadPage(0);
    }

    function loadPage(page) {
        if (root.loading || !authManager.isLoggedIn) return;

        root.loading = true;
        root.failed = false;
        loadSafetyTimer.restart();
        if (page === 0) root.feedDate = Math.floor(Date.now() / 1000);
        anixApi.fetchBrowseSection(root.activeSection, page, root.activeSection === "channelFeed" ? Number(root.query) : 0,
                                   authManager.token, root.activeSection === "myFeed" || root.activeSection === "channelFeed" ? String(root.feedDate) : root.query);
    }

    Timer {
        id: loadSafetyTimer
        interval: 10000
        onTriggered: {
            if (root.loading) {
                root.loading = false;
            }
        }
    }

    Component.onCompleted: {
        if (visible || channelId > 0) refresh();
    }

    onVisibleChanged: {
        if (visible && !root.entries[root.key] && !root.failed) root.loadPage(0);
    }

    Connections {
        target: authManager
        function onAuthChanged() {
            root.entries = {};
            if (root.channelId > 0) root.selectSection("channelFeed", String(root.channelId));
            else root.selectSection("latestFeed", "");
        }
    }

    Connections {
        target: anixApi
        function onBrowseSectionLoaded(section, page, collectionId, query, data) {
            if (section === "channel" && collectionId === root.channelId) {
                root.channelLoading = false;
                root.channelFailed = !data.channel;
                if (data.channel) root.channelData = data.channel;
                return;
            }
            if (!root.loading || section !== root.activeSection || !authManager.isLoggedIn) return;

            root.loading = false;
            loadSafetyTimer.stop();

            if (data.code !== undefined && data.code !== 0) {
                root.failed = true;
                return;
            }

            const old = page === 0 ? [] : (root.entries[root.key]?.posts || []);
            const updated = Object.assign({}, root.entries);
            const articles = section === "subscriptions" ? [] : (data.content || data.articles?.content || []);
            const channels = section === "subscriptions"
                ? root.mergeChannels(page === 0 ? [] : root.entries[root.key]?.channels || [], data.content || [])
                : page === 0 ? root.mergeChannels([], (data.channels?.content || []).concat(data.blogs?.content || []))
                : (root.entries[root.key]?.channels || []);

            if (section !== "subscriptions" && channels.length > 0) {
                root.latestChannels = channels;
            }

            root.nextPage = page + 1;
            root.lastPage = Math.max(data.total_page_count || data.articles?.total_page_count || 0,
                                    (section === "subscriptions" ? channels.length < (data.total_count || 0) : articles.length >= 25) ? page + 1 : page);
            updated[root.key] = {posts: old.concat(articles), channels: channels,
                                 nextPage: root.nextPage, lastPage: root.lastPage, date: root.feedDate};
            root.entries = updated;
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 20
        spacing: 14

        RowLayout {
            Layout.fillWidth: true
            visible: root.channelId > 0
            spacing: 12

            Button {
                text: "Назад"
                onClicked: root.StackView.view.pop()
            }
            Label {
                Layout.fillWidth: true
                text: root.channelData.title || "Сообщество"
                elide: Text.ElideRight
                font.pixelSize: 22
                font.weight: Font.DemiBold
                color: "#f0e9f8"
            }
        }

        RowLayout {
            Layout.fillWidth: true
            visible: root.channelId <= 0 && root.searchMode
            spacing: 12

            RoundButton {
                flat: true
                Material.background: "#2b2930"
                contentItem: Image {
                    anchors.centerIn: parent
                    width: 18
                    height: 18
                    source: "qrc:/assets/icons/back.svg"
                    sourceSize: Qt.size(18, 18)
                }
                onClicked: root.closeSearch()
            }

            TextField {
                id: searchField
                Layout.fillWidth: true
                placeholderText: "Поиск записей и блогов"
                color: "#ffffff"
                Material.accent: "#cfbcff"
                onAccepted: {
                    if (text.trim().length > 0) root.selectSection("feedSearch", text.trim());
                }
            }

            Button {
                text: "✕"
                visible: searchField.text.length > 0
                flat: true
                onClicked: {
                    searchField.text = "";
                    root.closeSearch();
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            visible: root.channelId <= 0 && !root.searchMode

            Item { Layout.fillWidth: true }

            SectionStrip {
                selection: root.activeSection
                sections: [
                    { key: "myFeed", label: "Моя лента" },
                    { key: "latestFeed", label: "Свежее" },
                    { key: "subscriptions", icon: "qrc:/assets/icons/star.svg", hint: "Мои подписки" }
                ]
                onActivated: key => {
                    root.selectedChannelFilterId = 0;
                    root.selectSection(key, "");
                }
            }

            Item { Layout.fillWidth: true }
        }

        Rectangle {
            Layout.fillWidth: true
            visible: root.channelId > 0
            implicitHeight: channelHeader.implicitHeight + 28
            radius: 14
            color: "#211a2d"

            RowLayout {
                id: channelHeader
                anchors.fill: parent
                anchors.margins: 14
                CircleImage {
                    visible: !(root.channelData.blog_profile_id > 0)
                    Layout.preferredWidth: 70
                    Layout.preferredHeight: 70
                    source: root.channelData.avatar || ""
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    Label {
                        Layout.fillWidth: true
                        text: root.channelFailed ? "Не удалось загрузить сообщество" : root.channelData.description || ""
                        visible: text.length > 0
                        wrapMode: Text.Wrap
                        textFormat: Text.PlainText
                    }
                    Label {
                        visible: !!root.channelData.id
                        text: (root.channelData.subscriber_count || 0) + " подписчиков · " + (root.channelData.article_count || 0) + " записей"
                        color: "#c5b7d1"
                    }
                    IdentityButton {
                        Layout.alignment: Qt.AlignLeft
                        visible: (root.channelData.blog_profile_id || 0) > 0
                        text: "Профиль автора"
                        avatarSource: root.channelData.avatar || ""
                        onClicked: window.openProfile(root.channelData.blog_profile_id)
                    }
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            visible: root.channelId <= 0 && !root.searchMode && root.rosterChannels.length > 0
            spacing: 8

            RowLayout {
                Layout.fillWidth: true

                Row {
                    spacing: 4
                    Text {
                        text: "Последнее"
                        font.pixelSize: 18
                        font.bold: true
                        color: "#ffffff"
                    }
                    Text {
                        text: " ∨"
                        font.pixelSize: 14
                        color: "#cac4d0"
                    }
                }

                Item { Layout.fillWidth: true }

                Text {
                    text: "Все"
                    font.pixelSize: 13
                    font.bold: true
                    color: "#cac4d0"
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.selectSection("subscriptions", "")
                    }
                }
            }

            Flickable {
                id: channelRoster
                Layout.fillWidth: true
                Layout.preferredHeight: 96
                contentWidth: storiesRow.implicitWidth
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                function prefetchSubscriptions() {
                    if (root.activeSection !== "subscriptions" || root.loading || root.failed
                        || root.nextPage > root.lastPage) return;
                    if (contentX + width + 96 >= contentWidth) root.loadPage(root.nextPage);
                }

                onContentXChanged: prefetchSubscriptions()
                onWidthChanged: prefetchSubscriptions()
                onMovementEnded: prefetchSubscriptions()

                Row {
                    id: storiesRow
                    spacing: 16

                    Repeater {
                        model: root.rosterChannels

                        delegate: Column {
                            id: storyDelegate
                            required property var modelData
                            readonly property bool isSelected: root.selectedChannelFilterId === modelData.id
                            spacing: 6
                            width: 68

                            Rectangle {
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: 64
                                height: 64
                                radius: 32
                                color: "transparent"
                                border.color: storyDelegate.isSelected ? "#cfbcff" : "transparent"
                                border.width: 2

                                CircleImage {
                                    anchors.centerIn: parent
                                    width: storyDelegate.isSelected ? 56 : 60
                                    height: storyDelegate.isSelected ? 56 : 60
                                    source: storyDelegate.modelData.avatar || ""
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.selectChannel(storyDelegate.modelData.id)
                                }
                            }

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: 68
                                text: storyDelegate.modelData.title || storyDelegate.modelData.name || storyDelegate.modelData.login || ""
                                font.pixelSize: 11
                                elide: Text.ElideRight
                                horizontalAlignment: Text.AlignHCenter
                                color: storyDelegate.isSelected ? "#ffffff" : "#cac4d0"
                            }
                        }
                    }
                }
            }

            Button {
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: 200
                Layout.preferredHeight: 38
                visible: root.selectedChannelFilterId > 0
                text: "Перейти на канал"
                font.bold: true
                Material.background: "#241f2c"
                Material.foreground: "#ffffff"
                onClicked: window.openChannel(root.selectedChannelFilterId)
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            Label {
                anchors.centerIn: parent
                visible: !root.loading && (root.activeSection === "subscriptions"
                    ? root.rosterChannels.length === 0 : posts.count === 0)
                text: !authManager.isLoggedIn ? "Войдите в аккаунт, чтобы читать ленту"
                    : (root.failed ? "Не удалось загрузить записи" : (root.activeSection === "subscriptions" ? "Подписок пока нет" : "Записей пока нет"))
                color: "#cac0d5"
            }

            BusyIndicator {
                anchors.centerIn: parent
                running: root.loading && (root.activeSection === "subscriptions"
                    ? root.rosterChannels.length === 0 : posts.count === 0)
                visible: running
            }

            ListView {
                id: posts
                anchors.fill: parent
                anchors.leftMargin: Math.max(0, (parent.width - 980) / 2)
                anchors.rightMargin: anchors.leftMargin
                clip: true
                spacing: 12
                model: root.entries[root.key]?.posts || []
                ScrollBar.vertical: AppScrollBar {}
                onMovementEnded: {
                    if (atYEnd && root.nextPage <= root.lastPage && !root.failed) root.loadPage(root.nextPage);
                }

                delegate: Loader {
                    id: entry
                    required property var modelData
                    width: posts.width - 12
                    sourceComponent: postCard

                    Component {
                        id: postCard
                        FeedPost { article: entry.modelData }
                    }
                }
            }
        }
    }
}
