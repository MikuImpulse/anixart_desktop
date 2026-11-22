import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Controls.Material 2.15
import QtQuick.Layouts 1.15
import Anixart 1.0

Flickable {
    id: root
    property var releaseId: 0
    property var initialData: null
    property var fullRelease: initialData
    readonly property Flickable pullSurface: root
    readonly property bool refreshing: detailsLoading || discussion.loading
    readonly property bool announced: (fullRelease?.status?.id || fullRelease?.status_id) === 3
    readonly property bool playable: !!fullRelease && !announced && !fullRelease.is_play_disabled && !fullRelease.is_view_blocked
    readonly property string releaseTitle: fullRelease ? (fullRelease.title_ru || fullRelease.title_original || "") : ""
    readonly property string releaseSubtitle: fullRelease ? (fullRelease.title_original || "") : ""
    readonly property var screenshotItems: screenshotMedia(fullRelease)
    readonly property var relatedReleases: fullRelease?.related_releases || []
    readonly property var recommendedReleases: fullRelease?.recommended_releases || []
    readonly property int listTotal: listCount("watching_count") + listCount("plan_count") + listCount("completed_count")
        + listCount("hold_on_count") + listCount("dropped_count")
    property string pendingAction: ""
    property string actionNotice: ""
    property bool bookmarkUpdating: false
    property int bookmarkStatus: initialData?.profile_list_status ?? anixApi.getReleaseBookmarkStatus(releaseId)
    property var myCollections: []
    property bool collectionLoading: false
    property bool collectionFailed: false
    property bool hasMoreCollections: false
    property int collectionsPage: 0
    property bool detailsLoading: false
    property bool descriptionExpanded: false
    property bool relatedExpanded: false

    function listCount(name) {
        return Number(fullRelease?.[name] || 0);
    }

    function screenshotUrl(item) {
        var value = typeof item === "string" ? item : (item?.url || item?.image || item?.src || "");
        if (!value) return "";
        if (value.indexOf("://") >= 0 || value.indexOf("qrc:") === 0) return value;
        return "https://s.anixmirai.com/screenshots/" + value.replace(/\.(?:jpe?g|png|webp)$/i, "") + ".jpg";
    }

    function screenshotMedia(release) {
        var source = release?.screenshot_images;
        if (!source || source.length === 0) source = release?.screenshots || [];
        var result = [];
        for (var i = 0; i < source.length; ++i) {
            var url = screenshotUrl(source[i]);
            if (url) result.push({ url: url });
        }
        return result;
    }

    function releaseName(release) {
        return release?.title_ru || release?.title_original || "Без названия";
    }

    function releaseStatus(release) {
        var status = release?.status;
        if (status?.name) return status.name;
        if (typeof status === "string") return status;
        var id = status?.id || release?.status_id || 0;
        return id === 1 ? "Вышел" : id === 2 ? "Выходит" : id === 3 ? "Анонс" : "";
    }

    function releaseDate() {
        if (!fullRelease?.aired_on_date) return "";
        return Qt.formatDate(new Date(fullRelease.aired_on_date * 1000), "d MMMM yyyy");
    }

    contentWidth: width
    contentHeight: contentCol.implicitHeight + 60
    clip: true

    ScrollBar.vertical: AppScrollBar {}

    function loadDetails() {
        if (!releaseId || detailsLoading) return;
        detailsLoading = true;
        anixApi.fetchRelease(releaseId, authManager.token);
    }

    function changeBookmark(status) {
        if (bookmarkUpdating || status === bookmarkStatus) return;

        bookmarkUpdating = true;
        actionNotice = "";
        if (status > 0) anixApi.addBookmark(releaseId, status, authManager.token);
        else anixApi.removeBookmark(releaseId, authManager.token, bookmarkStatus);
    }

    function saveAction(action, value) {
        if (pendingAction || !fullRelease) return;
        if (!authManager.isLoggedIn) {
            window.openAuthDialog();
            return;
        }

        actionNotice = "";
        pendingAction = action;
        anixApi.saveReleaseAction(releaseId, action, value, authManager.token);
    }

    function loadCollections(page) {
        if (collectionLoading) return;

        collectionLoading = true;
        collectionFailed = false;
        anixApi.fetchBrowseSection("myReleaseCollections", page, releaseId, authManager.token);
    }

    function refresh() {
        loadDetails();
        discussion.load(0);
    }

    Component.onCompleted: loadDetails()

    Connections {
        target: anixApi
        function onReleaseLoaded(id, rel) {
            if (id !== root.releaseId) return;
            root.detailsLoading = false;
            if (rel.id !== id) return;

            root.fullRelease = rel;
            if (authManager.isLoggedIn && rel.profile_list_status !== undefined)
                root.bookmarkStatus = Number(rel.profile_list_status) || 0;
        }

        function onBookmarkUpdated(id, status) {
            if (id !== root.releaseId) return;
            root.bookmarkStatus = status;
            root.bookmarkUpdating = false;
        }

        function onBookmarkUpdateFailed(id) {
            if (id !== root.releaseId || !root.bookmarkUpdating) return;
            root.bookmarkUpdating = false;
            root.actionNotice = "Не удалось обновить закладку";
        }

        function onReleaseActionSaved(id, action, success) {
            if (id !== root.releaseId || action !== root.pendingAction) return;

            root.pendingAction = "";
            root.actionNotice = success ? action === "collection" ? "Добавлено в коллекцию" : "" : "Не удалось сохранить изменение";
            if (!success) return;

            if (action === "collection") collectionDialog.close();
            root.loadDetails();
        }

        function onBrowseSectionLoaded(section, page, id, query, data) {
            if (section !== "myReleaseCollections" || id !== root.releaseId || !root.collectionLoading) return;

            root.collectionLoading = false;
            root.collectionFailed = data.code !== 0;
            if (root.collectionFailed) return;

            const rows = data.content || [];
            root.myCollections = page === 0 ? rows : root.myCollections.concat(rows);
            root.collectionsPage = page;
            root.hasMoreCollections = page < (data.total_page_count || 0);
        }
    }

    ColumnLayout {
        id: contentCol
        width: Math.min(parent.width - 48, 1100)
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: 20
        spacing: 24

        RowLayout {
            Layout.fillWidth: true
            spacing: 16

            RoundButton {
                flat: true
                Material.background: "#2b2930"
                contentItem: Image {
                    anchors.centerIn: parent
                    width: 20
                    height: 20
                    source: "qrc:/assets/icons/back.svg"
                    sourceSize: Qt.size(20, 20)
                }
                onClicked: pageStack.pop()
            }

            Text {
                text: root.fullRelease ? root.releaseTitle : "Загрузка..."
                font.pixelSize: 20
                font.bold: true
                color: "#e6e1e5"
                elide: Text.ElideRight
                Layout.fillWidth: true
            }

            AppToolButton {
                text: "Комментарии" + (root.fullRelease ? " · " + (root.fullRelease.comment_count || 0) : "")
                enabled: root.releaseId > 0
                onClicked: window.openReleaseComments(root.releaseId, root.releaseTitle)
            }

            AppToolButton {
                icon.source: "qrc:/assets/icons/more_vert.svg"
                Accessible.name: "Действия с релизом"
                enabled: root.releaseId > 0
                onClicked: releaseMenu.open()

                Menu {
                    id: releaseMenu
                    y: parent.height

                    MenuItem {
                        text: "Открыть комментарии"
                        onClicked: window.openReleaseComments(root.releaseId, root.releaseTitle)
                    }
                    MenuItem {
                        text: "Скопировать ссылку"
                        icon.source: "qrc:/assets/icons/copy.svg"
                        onClicked: {
                            authManager.copyToClipboard("https://anixart.tv/release/" + root.releaseId);
                            root.actionNotice = "Ссылка скопирована";
                        }
                    }
                }
            }
        }

        Rectangle {
            id: heroCard
            Layout.fillWidth: true
            implicitHeight: Math.max(340, heroRow.implicitHeight + 48)
            radius: 20
            color: "#1d192b"
            CircleImage {
                anchors.fill: parent
                source: root.fullRelease ? (root.fullRelease.image || "") : ""
                cornerRadius: heroCard.radius
                opacity: 0.15
            }

            Rectangle {
                anchors.fill: parent
                radius: heroCard.radius
                color: "transparent"
                border.color: "#36343b"
                border.width: 1
            }

            RowLayout {
                id: heroRow
                anchors.fill: parent
                anchors.margins: 24
                spacing: 28
                layoutDirection: Qt.RightToLeft

                Rectangle {
                    id: heroPoster
                    Layout.preferredWidth: Math.max(200, Math.min(264, Math.round(heroCard.width * 0.24)))
                    Layout.preferredHeight: Math.round(Layout.preferredWidth * 1.45)
                    radius: 14
                    color: "#2b2930"

                    CircleImage {
                        id: posterThumbnail
                        objectName: "releasePoster"
                        anchors.fill: parent
                        source: root.fullRelease ? (root.fullRelease.image || "") : ""
                        cornerRadius: heroPoster.radius
                    }

                    AppToolButton {
                        anchors.fill: parent
                        enabled: posterThumbnail.source.length > 0
                        Accessible.name: "Открыть постер на весь экран"
                        background: Item {}
                        HoverHandler { cursorShape: Qt.PointingHandCursor }
                        onClicked: {
                            window.openMedia(posterThumbnail.source, root.releaseTitle, root.releaseSubtitle);
                        }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 12

                    Text {
                        text: root.fullRelease ? root.releaseTitle : ""
                        font.pixelSize: 26
                        font.bold: true
                        color: "#ffffff"
                        wrapMode: Text.Wrap
                        Layout.fillWidth: true
                    }

                    Text {
                        text: root.fullRelease ? (root.fullRelease.title_original || "") : ""
                        font.pixelSize: 15
                        color: "#cac4d0"
                        wrapMode: Text.Wrap
                        Layout.fillWidth: true
                    }

                    RowLayout {
                        spacing: 10

                        Rectangle {
                            visible: (root.fullRelease?.vote_count || 0) > 0
                            implicitHeight: 28
                            implicitWidth: ratingText.implicitWidth + 20
                            radius: 14
                            color: "#ffd043"

                            Row {
                                id: ratingText
                                anchors.centerIn: parent
                                spacing: 4
                                Image {
                                    width: 14
                                    height: 14
                                    anchors.verticalCenter: parent.verticalCenter
                                    source: "qrc:/assets/icons/star.svg"
                                    sourceSize: Qt.size(14, 14)
                                }
                                Text {
                                    text: root.fullRelease ? Number(root.fullRelease.grade || 0).toFixed(2) : ""
                                    font.bold: true
                                    font.pixelSize: 13
                                    color: "#241a00"
                                }
                            }
                        }

                        Rectangle {
                            visible: !!root.fullRelease?.year
                            implicitHeight: 28
                            implicitWidth: yearBadgeText.implicitWidth + 20
                            radius: 14
                            color: "#2b2930"

                            Text {
                                id: yearBadgeText
                                anchors.centerIn: parent
                                text: root.fullRelease ? (root.fullRelease.year || "") : ""
                                font.bold: true
                                font.pixelSize: 13
                                color: "#e6e1e5"
                            }
                        }

                        Rectangle {
                            visible: statusBadgeText.text.length > 0
                            implicitHeight: 28
                            implicitWidth: statusBadgeText.implicitWidth + 20
                            radius: 14
                            color: "#2b2930"

                            Text {
                                id: statusBadgeText
                                anchors.centerIn: parent
                                text: {
                                    return root.releaseStatus(root.fullRelease);
                                }
                                font.bold: true
                                font.pixelSize: 13
                                color: "#cfbcff"
                            }
                        }
                    }

                    Text {
                        text: root.fullRelease ? ("Жанры: " + (root.fullRelease.genres || "—")) : ""
                        font.pixelSize: 13
                        color: "#cac4d0"
                        wrapMode: Text.Wrap
                        Layout.fillWidth: true
                    }

                    Text {
                        Layout.fillWidth: true
                        visible: text.length > 0
                        text: {
                            const released = root.fullRelease?.episodes_released || 0;
                            const total = root.fullRelease?.episodes_total || 0;
                            return released && total > released ? released + " из " + total + " эп."
                                : total || released ? (total || released) + " эп." : "";
                        }
                        font.pixelSize: 13
                        color: "#938f99"
                    }

                    Text {
                        Layout.fillWidth: true
                        visible: text.length > 0
                        text: root.fullRelease?.description || ""
                        textFormat: Text.PlainText
                        font.pixelSize: 14
                        color: "#e6e1e5"
                        wrapMode: Text.Wrap
                        maximumLineCount: 3
                        elide: Text.ElideRight
                    }

                    Item { Layout.fillHeight: true }

                    RowLayout {
                        spacing: 12

                        Rectangle {
                            visible: root.announced
                            Layout.preferredHeight: 48
                            implicitWidth: announceRow.implicitWidth + 32
                            radius: 24
                            color: "#352e42"
                            border.color: "#4f455c"
                            border.width: 1

                            RowLayout {
                                id: announceRow
                                anchors.centerIn: parent
                                spacing: 8
                                Image {
                                    width: 18
                                    height: 18
                                    source: "qrc:/assets/icons/catalog.svg"
                                    sourceSize: Qt.size(18, 18)
                                }
                                Text {
                                    text: {
                                        if (root.fullRelease && root.fullRelease.aired_on_date > 0) {
                                            return "Премьера " + Qt.formatDate(new Date(root.fullRelease.aired_on_date * 1000), "d MMMM yyyy");
                                        }
                                        if (root.fullRelease && root.fullRelease.release_date && root.fullRelease.release_date.trim().length > 0) {
                                            return "Премьера: " + root.fullRelease.release_date.trim();
                                        }
                                        if (root.fullRelease && root.fullRelease.year) {
                                            return "Скоро · " + root.fullRelease.year;
                                        }
                                        return "Анонс";
                                    }
                                    font.pixelSize: 14
                                    font.bold: true
                                    color: "#e6e1e5"
                                }
                            }
                        }

                        Button {
                            visible: !root.announced
                            text: "Смотреть"
                            icon.source: "qrc:/assets/icons/play.svg"
                            enabled: root.playable && !root.detailsLoading
                            font.pixelSize: 15
                            font.bold: true
                            Material.background: "#cfbcff"
                            Material.foreground: "#381e72"
                            Layout.preferredHeight: 48

                            onClicked: {
                                pageStack.push("qrc:/qml/VoiceoverEpisodesPage.qml", {
                                    releaseId: root.releaseId,
                                    releaseTitle: root.fullRelease ? root.fullRelease.title_ru : "Аниме",
                                    releasePoster: root.fullRelease ? root.fullRelease.image : ""
                                });
                            }
                        }

                        Button {
                            id: bookmarkBtn
                            readonly property int currentStatus: root.bookmarkStatus
                            text: {
                                if (currentStatus === 1) return "✓ Смотрю";
                                if (currentStatus === 2) return "✓ В планах";
                                if (currentStatus === 3) return "✓ Просмотрено";
                                if (currentStatus === 4) return "✓ Отложено";
                                if (currentStatus === 5) return "✓ Брошено";
                                return "В закладки";
                            }
                            font.pixelSize: 14
                            Material.background: currentStatus > 0 ? "#4f378b" : "#2b2930"
                            Material.foreground: currentStatus > 0 ? "#ffffff" : "#cac4d0"
                            Layout.preferredHeight: 48
                            enabled: !root.bookmarkUpdating && !root.detailsLoading
                            onClicked: bookmarkMenu.open()

                            Menu {
                                id: bookmarkMenu
                                y: bookmarkBtn.height

                                MenuItem {
                                    text: "Смотрю"
                                    onTriggered: root.changeBookmark(1)
                                }
                                MenuItem {
                                    text: "В планах"
                                    onTriggered: root.changeBookmark(2)
                                }
                                MenuItem {
                                    text: "Просмотрено"
                                    onTriggered: root.changeBookmark(3)
                                }
                                MenuItem {
                                    text: "Отложено"
                                    onTriggered: root.changeBookmark(4)
                                }
                                MenuItem {
                                    text: "Брошено"
                                    onTriggered: root.changeBookmark(5)
                                }
                                MenuItem {
                                    visible: bookmarkBtn.currentStatus > 0
                                    text: "Удалить из закладок"
                                    onTriggered: root.changeBookmark(0)
                                }
                            }
                        }

                        Button {
                            id: commentsTileBtn
                            Layout.preferredHeight: 48
                            text: (root.fullRelease ? (root.fullRelease.comment_count || root.fullRelease.comments_count || 0) : 0) + " коммент."
                            ToolTip.text: "Перейти к комментариям"
                            ToolTip.visible: hovered
                            Material.background: "#2b2930"
                            Material.foreground: "#cac4d0"
                            onClicked: window.openReleaseComments(root.releaseId, root.releaseTitle)
                        }
                    }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: descCol.implicitHeight + 48
            radius: 16
            color: "#1d192b"
            border.color: "#36343b"
            border.width: 1

            ColumnLayout {
                id: descCol
                anchors.fill: parent
                anchors.margins: 24
                spacing: 12

                Text {
                    text: "Описание"
                    font.pixelSize: 18
                    font.bold: true
                    color: "#e6e1e5"
                }

                Text {
                    id: descriptionText
                    Layout.fillWidth: true
                    text: root.fullRelease ? (root.fullRelease.description || "Описание отсутствует.") : ""
                    font.pixelSize: 14
                    lineHeight: 1.4
                    lineHeightMode: Text.ProportionalHeight
                    color: "#cac4d0"
                    wrapMode: Text.Wrap
                    maximumLineCount: root.descriptionExpanded ? 1000000 : 5
                    elide: Text.ElideRight
                }

                AppToolButton {
                    visible: descriptionText.lineCount > 5
                    text: root.descriptionExpanded ? "Свернуть" : "Читать полностью"
                    onClicked: root.descriptionExpanded = !root.descriptionExpanded
                }

                Text {
                    Layout.fillWidth: true
                    visible: text.length > 0
                    text: root.fullRelease?.note || ""
                    font.pixelSize: 13
                    lineHeight: 1.3
                    lineHeightMode: Text.ProportionalHeight
                    color: "#938f99"
                    wrapMode: Text.Wrap
                }
            }
        }

        GridLayout {
            Layout.fillWidth: true
            columns: width >= 720 ? 2 : 1
            columnSpacing: 24
            rowSpacing: 24

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredWidth: 1
                implicitHeight: ratingColumn.implicitHeight + 40
                radius: 16
                color: "#1d192b"
                border.color: "#36343b"
                border.width: 1

                ColumnLayout {
                    id: ratingColumn
                    anchors.fill: parent
                    anchors.margins: 20
                    spacing: 10

                    RowLayout {
                        Layout.fillWidth: true

                        Text {
                            text: "Оценки"
                            font.pixelSize: 18
                            font.bold: true
                            color: "#e6e1e5"
                        }

                        Item { Layout.fillWidth: true }

                        Text {
                            text: root.fullRelease?.vote_count ? root.fullRelease.vote_count + " оценок" : ""
                            color: "#938f99"
                            font.pixelSize: 12
                        }
                    }

                    RowLayout {
                        spacing: 8

                        Text {
                            text: root.fullRelease?.grade ? Number(root.fullRelease.grade).toFixed(2) : "—"
                            font.pixelSize: 28
                            font.bold: true
                            color: "#ffd043"
                        }

                        Text {
                            text: "из 5"
                            color: "#938f99"
                            font.pixelSize: 13
                            Layout.alignment: Qt.AlignBottom
                        }
                    }

                    Repeater {
                        model: [5, 4, 3, 2, 1]

                        delegate: RowLayout {
                            required property int modelData
                            Layout.fillWidth: true
                            property int votes: Number(root.fullRelease?.["vote_" + modelData + "_count"] || 0)
                            property real portion: root.fullRelease?.vote_count > 0 ? Math.min(1, votes / root.fullRelease.vote_count) : 0

                            Text {
                                text: modelData
                                color: "#cac4d0"
                                font.pixelSize: 12
                                Layout.preferredWidth: 12
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 6
                                radius: 3
                                color: "#302b36"

                                Rectangle {
                                    width: parent.width * parent.parent.portion
                                    height: parent.height
                                    radius: 3
                                    color: "#cfbcff"
                                }
                            }

                            Text {
                                text: votes
                                color: "#938f99"
                                font.pixelSize: 12
                                horizontalAlignment: Text.AlignRight
                                Layout.preferredWidth: 34
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true

                        Label { Layout.fillWidth: true; text: "Ваша оценка" }

                        Repeater {
                            model: [1, 2, 3, 4, 5]

                            delegate: AppToolButton {
                                required property int modelData
                                readonly property int currentVote: root.fullRelease?.your_vote || 0
                                text: modelData <= currentVote ? "★" : "☆"
                                font.pixelSize: 19
                                Accessible.name: "Оценить на " + modelData
                                enabled: !!root.fullRelease && !root.pendingAction && !root.detailsLoading
                                onClicked: root.saveAction("rating", modelData === currentVote ? 0 : modelData)
                            }
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredWidth: 1
                implicitHeight: factsColumn.implicitHeight + 40
                radius: 16
                color: "#1d192b"
                border.color: "#36343b"
                border.width: 1

                ColumnLayout {
                    id: factsColumn
                    anchors.fill: parent
                    anchors.margins: 20
                    spacing: 9

                    Text {
                        text: "О релизе"
                        font.pixelSize: 18
                        font.bold: true
                        color: "#e6e1e5"
                    }

                    Repeater {
                        model: [
                            { label: "Дата", value: root.releaseDate() },
                            { label: "Эпизоды", value: root.fullRelease?.episodes_total > 0
                                ? ((root.fullRelease.episodes_released > 0 && root.fullRelease.episodes_released < root.fullRelease.episodes_total)
                                    ? root.fullRelease.episodes_released + " из " : "") + root.fullRelease.episodes_total : "" },
                            { label: "Длительность", value: root.fullRelease?.duration > 0 ? root.fullRelease.duration + " мин." : "" },
                            { label: "Жанры", value: root.fullRelease?.genres || "" },
                            { label: "Источник", value: root.fullRelease?.source || "" },
                            { label: "Страна", value: root.fullRelease?.country || "" },
                            { label: "Режиссёр", value: root.fullRelease?.director || "" },
                            { label: "Студия", value: root.fullRelease?.studio || "" },
                            { label: "Автор", value: root.fullRelease?.author || "" }
                        ]

                        delegate: RowLayout {
                            required property var modelData
                            visible: modelData.value !== ""
                            Layout.fillWidth: true

                            Text {
                                text: modelData.label
                                color: "#938f99"
                                font.pixelSize: 13
                                Layout.preferredWidth: 104
                            }

                            Text {
                                text: modelData.value
                                color: "#cac4d0"
                                font.pixelSize: 13
                                wrapMode: Text.Wrap
                                Layout.fillWidth: true
                            }
                        }
                    }
                    Item { Layout.fillHeight: true }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            visible: !!root.fullRelease
            implicitHeight: listsColumn.implicitHeight + 40
            radius: 16
            color: "#1d192b"
            border.color: "#36343b"
            border.width: 1

            ColumnLayout {
                id: listsColumn
                anchors.fill: parent
                anchors.margins: 20
                spacing: 12

                Text {
                    text: "Активность"
                    font.pixelSize: 18
                    font.bold: true
                    color: "#e6e1e5"
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 18

                    Repeater {
                        model: [
                            { label: "Смотрю", count: root.listCount("watching_count") },
                            { label: "В планах", count: root.listCount("plan_count") },
                            { label: "Просмотрено", count: root.listCount("completed_count") },
                            { label: "Отложено", count: root.listCount("hold_on_count") },
                            { label: "Брошено", count: root.listCount("dropped_count") }
                        ]

                        delegate: ColumnLayout {
                            required property var modelData
                            visible: modelData.count > 0
                            spacing: 2

                            Text {
                                text: modelData.count
                                color: "#cfbcff"
                                font.pixelSize: 18
                                font.bold: true
                            }

                            Text {
                                text: modelData.label
                                color: "#938f99"
                                font.pixelSize: 12
                            }
                        }
                    }

                    Item { Layout.fillWidth: true }

                }

                RowLayout {
                    Layout.fillWidth: true

                    Button {
                        text: "В коллекциях · " + (root.fullRelease?.collection_count || 0)
                        enabled: (root.fullRelease?.collection_count || 0) > 0
                        onClicked: window.openProfileExtras("releaseCollections", root.releaseId, false)
                    }

                    Button {
                        text: "В свою коллекцию"
                        highlighted: true
                        onClicked: {
                            if (authManager.isLoggedIn) collectionDialog.open();
                            else window.openAuthDialog();
                        }
                    }

                    AppToolButton {
                        text: root.fullRelease?.is_favorite ? "Убрать из избранного" : "В избранное"
                        icon.source: "qrc:/assets/icons/bookmarks.svg"
                        enabled: !root.pendingAction && !root.detailsLoading
                        onClicked: root.saveAction("favorite", root.fullRelease.is_favorite ? 0 : 1)
                    }
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            visible: root.screenshotItems.length > 0
            spacing: 12

            Text {
                text: "Кадры"
                font.pixelSize: 20
                font.bold: true
                color: "#e6e1e5"
            }

            Flickable {
                Layout.fillWidth: true
                Layout.preferredHeight: 156
                contentWidth: screenshotRow.width
                contentHeight: height
                clip: true
                flickableDirection: Flickable.HorizontalFlick

                ScrollBar.horizontal: AppScrollBar {}

                Row {
                    id: screenshotRow
                    spacing: 12

                    Repeater {
                        model: root.screenshotItems

                        delegate: Rectangle {
                            required property var modelData
                            width: 224
                            height: 136
                            radius: 12
                            color: "#2b2930"
                            clip: true

                            Image {
                                anchors.fill: parent
                                source: parent.modelData.url
                                fillMode: Image.PreserveAspectCrop
                                mipmap: true
                                asynchronous: true
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: window.openFeedGallery(root.screenshotItems, index)
                            }
                        }
                    }
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            visible: root.relatedReleases.length > 0
            spacing: 12

            RowLayout {
                Layout.fillWidth: true

                Text {
                    text: "Связанные релизы"
                    font.pixelSize: 20
                    font.bold: true
                    color: "#e6e1e5"
                }

                Item { Layout.fillWidth: true }

                AppToolButton {
                    visible: root.relatedReleases.length > 4
                    text: root.relatedExpanded ? "Свернуть" : "Все"
                    onClicked: root.relatedExpanded = !root.relatedExpanded
                }
            }

            GridLayout {
                Layout.fillWidth: true
                columns: 2
                columnSpacing: 16
                rowSpacing: 16

                Repeater {
                    model: root.relatedExpanded ? root.relatedReleases : root.relatedReleases.slice(0, 4)

                    delegate: Button {
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.preferredHeight: 96
                        enabled: modelData.id > 0
                        leftPadding: 0
                        rightPadding: 12
                        topPadding: 0
                        bottomPadding: 0
                        background: Rectangle {
                            radius: 12
                            color: "#1d192b"
                            border.color: "#36343b"
                            border.width: 1
                        }
                        contentItem: RowLayout {
                            spacing: 12

                            Rectangle {
                                Layout.preferredWidth: 62
                                Layout.fillHeight: true
                                radius: 12
                                color: "#2b2930"
                                clip: true

                                Image {
                                    anchors.fill: parent
                                    source: modelData.image || ""
                                    fillMode: Image.PreserveAspectCrop
                                    mipmap: true
                                    asynchronous: true
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 4

                                Text {
                                    text: root.releaseName(modelData)
                                    color: "#e6e1e5"
                                    font.pixelSize: 14
                                    font.bold: true
                                    wrapMode: Text.Wrap
                                    maximumLineCount: 2
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }

                                Text {
                                    text: root.releaseStatus(modelData)
                                    visible: text.length > 0
                                    color: "#938f99"
                                    font.pixelSize: 12
                                }
                            }
                        }
                        onClicked: window.openRelease(modelData.id)
                    }
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            visible: root.recommendedReleases.length > 0
            spacing: 12

            Text {
                text: "Рекомендуем посмотреть"
                font.pixelSize: 20
                font.bold: true
                color: "#e6e1e5"
            }

            Flickable {
                Layout.fillWidth: true
                Layout.preferredHeight: 244
                contentWidth: recommendationsRow.width
                contentHeight: height
                clip: true
                flickableDirection: Flickable.HorizontalFlick

                ScrollBar.horizontal: AppScrollBar {}

                Row {
                    id: recommendationsRow
                    spacing: 14

                    Repeater {
                        model: root.recommendedReleases

                        delegate: Button {
                            required property var modelData
                            width: 142
                            height: 224
                            enabled: modelData.id > 0
                            padding: 0
                            background: Item {}
                            contentItem: ColumnLayout {
                                spacing: 7

                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 180
                                    radius: 12
                                    color: "#2b2930"
                                    clip: true

                                    Image {
                                        anchors.fill: parent
                                        source: modelData.image || ""
                                        fillMode: Image.PreserveAspectCrop
                                        mipmap: true
                                        asynchronous: true
                                    }
                                }

                                Text {
                                    text: root.releaseName(modelData)
                                    color: "#e6e1e5"
                                    font.pixelSize: 13
                                    font.bold: true
                                    wrapMode: Text.Wrap
                                    maximumLineCount: 2
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }
                            }
                            onClicked: window.openRelease(modelData.id)
                        }
                    }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            visible: root.announced
            implicitHeight: noticeCol.implicitHeight + 28
            radius: 14
            color: "#211c2a"
            border.color: "#3d334d"
            border.width: 1

            ColumnLayout {
                id: noticeCol
                anchors.fill: parent
                anchors.margins: 18
                spacing: 6

                Text {
                    text: "Информация об анонсе"
                    font.bold: true
                    font.pixelSize: 15
                    color: "#cfbcff"
                }
                Text {
                    Layout.fillWidth: true
                    text: {
                        var y = root.fullRelease ? (root.fullRelease.year || "") : "";
                        var d = (root.fullRelease && root.fullRelease.aired_on_date > 0)
                            ? Qt.formatDate(new Date(root.fullRelease.aired_on_date * 1000), "d MMMM yyyy") : "";
                        if (d.length > 0) return "Официальная дата премьеры: " + d + " г.\nСерии станут доступны после выхода релиза в эфир.";
                        if (y.length > 0) return "Премьера ожидается в " + y + " году.\nБольше подробностей сообщат позже.";
                        return "Релиз находится на стадии анонса. Подробности будут сообщены позже.";
                    }
                    font.pixelSize: 13
                    lineHeight: 1.3
                    lineHeightMode: Text.ProportionalHeight
                    color: "#cac4d0"
                    wrapMode: Text.Wrap
                }
            }
        }

        Label {
            Layout.fillWidth: true
            visible: root.actionNotice.length > 0
            text: root.actionNotice
            wrapMode: Text.Wrap
            color: "#cfbcff"
        }

        Item { Layout.preferredHeight: 30 }
        Discussion {
            id: discussion
            Layout.fillWidth: true
            section: "releaseComments"
            entityId: root.releaseId
            preview: true
            previewComments: root.fullRelease?.comments ?? null
            canComment: !!root.fullRelease && !root.fullRelease.is_view_blocked
            onOpenAll: (commentId, replyProfile) => window.openReleaseComments(
                root.releaseId, root.releaseTitle, commentId, canComment, replyProfile)
        }
    }

    Dialog {
        id: collectionDialog
        parent: Overlay.overlay
        anchors.centerIn: parent
        width: Math.min(parent.width - 40, 490)
        title: "Мои коллекции"
        modal: true
        Overlay.modal: Rectangle { color: "#bb000000" }
        onOpened: root.loadCollections(0)

        contentItem: ColumnLayout {
            Label {
                Layout.fillWidth: true
                visible: !!root.actionNotice || root.collectionFailed || root.collectionLoading || root.myCollections.length === 0
                text: root.collectionFailed ? "Не удалось загрузить коллекции"
                    : root.collectionLoading ? "Загрузка…" : root.actionNotice || "У вас пока нет коллекций"
                wrapMode: Text.Wrap
            }

            ListView {
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(300, contentHeight)
                clip: true
                model: root.myCollections
                ScrollBar.vertical: AppScrollBar {}

                delegate: ItemDelegate {
                    id: collectionItem
                    required property var modelData
                    width: ListView.view.width
                    text: modelData.title || "Коллекция"
                    enabled: !root.pendingAction
                    background: Rectangle {
                        radius: 12
                        color: collectionItem.down ? "#4a385e"
                            : collectionItem.hovered || collectionItem.activeFocus ? "#2d2539" : "transparent"
                    }
                    onClicked: root.saveAction("collection", modelData.id)
                }
            }

            Button {
                visible: root.hasMoreCollections
                enabled: !root.collectionLoading
                text: "Ещё коллекции"
                onClicked: root.loadCollections(root.collectionsPage + 1)
            }
        }
    }

}
