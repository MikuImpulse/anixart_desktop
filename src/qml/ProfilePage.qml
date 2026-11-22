import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Controls.Material 2.15
import QtQuick.Layouts 1.15
import Anixart 1.0

Flickable {
    id: root
    contentWidth: width
    contentHeight: contentColumn.implicitHeight + 56
    clip: true

    ScrollBar.vertical: AppScrollBar {}

    property var requestedUserId: 0
    property string activeSection: "stats"
    property bool profileLoading: false
    property bool profileFailed: false
    property bool profileDirty: true
    property var profileData: null
    property var profileUserId: 0
    property string mediaNotice: ""
    property string channelCover: ""
    readonly property bool ownProfile: requestedUserId <= 0
    readonly property bool publicSections: ownProfile || !(profileData?.is_private ?? false)
    readonly property Flickable pullSurface: root
    readonly property bool refreshing: profileLoading
    readonly property var sections: [
        {key: "stats", label: "Статистика", icon: "qrc:/assets/icons/profile_stats.svg"},
        {key: "ratings", label: "Оценки", icon: "qrc:/assets/icons/star.svg"},
        {key: "collections", label: "Коллекции", icon: "qrc:/assets/icons/catalog.svg"},
        {key: "comments", label: "Комментарии", icon: "qrc:/assets/icons/chat.svg"},
        {key: "videos", label: "Видео", icon: "qrc:/assets/icons/play.svg"},
        {key: "badges", label: "Значки", icon: "qrc:/assets/icons/profile_badge.svg"}
    ]
    readonly property var listStats: [
        {label: "Смотрю", value: profileData?.watching_count || 0, color: "#71b281"},
        {label: "В планах", value: profileData?.plan_count || 0, color: "#b286ca"},
        {label: "Просмотрено", value: profileData?.completed_count || 0, color: "#8099e2"},
        {label: "Отложено", value: profileData?.hold_on_count || 0, color: "#edbd6a"},
        {label: "Брошено", value: profileData?.dropped_count || 0, color: "#da7f8f"}
    ]
    readonly property int listTotal: listStats.reduce((sum, status) => sum + status.value, 0)
    readonly property var sectionRows: {
        if (!profileData || !publicSections) return [];
        if (activeSection === "ratings") return profileData.votes || profileData.ratings || [];
        if (activeSection === "collections") return profileData.collections_preview || profileData.collections || [];
        if (activeSection === "videos") return profileData.release_videos_preview || profileData.videos || [];
        return [];
    }
    readonly property var badges: profileData?.badges_preview || profileData?.badges || (profileData?.badge ? [profileData.badge] : [])

    Component.onCompleted: loadProfile()

    onVisibleChanged: {
        if (visible && profileDirty) loadProfile();
    }

    function refresh() {
        profileDirty = true;
        loadProfile();
    }

    function loadProfile() {
        var userId = ownProfile ? (authManager.isLoggedIn ? authManager.userId : 0) : requestedUserId;
        if (profileUserId !== userId) {
            profileUserId = userId;
            channelCover = "";
            var cached = ownProfile && userId > 0 ? anixApi.cachedUserProfile(userId) : {};
            profileData = cached.id ? cached : null;
            profileLoading = false;
            profileDirty = true;
        }

        if (userId > 0 && profileDirty) {
            profileDirty = false;
            profileLoading = true;
            profileFailed = false;
            anixApi.fetchUserProfile(userId, authManager.token);
            anixApi.fetchBrowseSection("profileBlog", 0, userId, authManager.token);
        }
    }

    function avatarUrl() {
        return profileData?.header_avatar || profileData?.avatar || (ownProfile ? authManager.userAvatar : "") || "";
    }

    function bannerUrl() {
        return profileData?.banner || profileData?.cover || profileData?.header || channelCover;
    }

    function leadingPreference() {
        var genre = profileData?.preferred_genres?.length ? profileData.preferred_genres[0] : null;
        var theme = profileData?.preferred_themes?.length ? profileData.preferred_themes[0] : null;
        return String(genre?.name || theme?.name || "").toLowerCase();
    }

    function themeColor() {
        var preference = leadingPreference();
        if (preference.indexOf("романт") >= 0 || preference.indexOf("romance") >= 0) return "#5a314c";
        if (preference.indexOf("экшен") >= 0 || preference.indexOf("боев") >= 0 || preference.indexOf("action") >= 0) return "#54202b";
        if (preference.indexOf("комед") >= 0 || preference.indexOf("comedy") >= 0) return "#594021";
        return "#1e1b24";
    }

    function themeMark() {
        var preference = leadingPreference();
        if (preference.indexOf("романт") >= 0 || preference.indexOf("romance") >= 0) return "♥";
        return "";
    }

    function formatNumber(value) {
        return Number(value || 0).toString().replace(/\B(?=(\d{3})+(?!\d))/g, " ");
    }

    function formatWatchTime(minutes) {
        var value = Number(minutes || 0);
        if (value < 60) return value ? value + " мин" : "0 мин";
        var days = Math.floor(value / 1440);
        var hours = Math.floor(value % 1440 / 60);
        return days ? days + " д. " + hours + " ч." : hours + " ч.";
    }

    function titleFor(item) {
        return item?.title_ru || item?.title || item?.name_ru || item?.name || item?.release?.title_ru || item?.release?.title || "Запись";
    }

    function profileLink() {
        return profileUserId > 0 ? "https://anixart.tv/profile/" + profileUserId : "";
    }

    function openMedia(url, title, subtitle) {
        if (!url) return;
        window.openMedia(url, title || "Медиа", subtitle || "");
    }

    function openComments() {
        if (!profileUserId || !publicSections || profileData?.is_comments_hidden && !ownProfile) return;
        root.StackView.view.push("qrc:/qml/ProfileCommentsPage.qml", { userId: profileUserId });
    }

    function copyProfileLink() {
        var link = profileLink();
        if (!link) {
            mediaNotice = "Ссылка на профиль не предоставлена сервером";
            return;
        }
        authManager.copyToClipboard(link);
        mediaNotice = "Ссылка скопирована";
    }

    Connections {
        target: authManager

        function onAuthChanged() {
            root.profileDirty = true;
            root.loadProfile();
        }
    }

    Connections {
        target: anixApi

        function onUserProfileLoaded(id, profile) {
            if (id !== root.profileUserId) return;
            root.profileLoading = false;
            root.profileFailed = !profile.id;
            if (profile.id) root.profileData = profile;
        }

        function onBrowseSectionLoaded(section, page, id, query, data) {
            if (section === "profileBlog" && id === root.profileUserId && data.code === 0)
                root.channelCover = data.channel?.cover || "";
        }

        function onProfilePreferencesChanged() {
            if (root.ownProfile) root.refresh();
        }

        function onEpisodeHistoryUpdated() {
            if (!root.ownProfile) return;
            root.profileDirty = true;
            if (root.visible) root.loadProfile();
        }
    }

    UserSearchDialog {
        id: userSearchDialog
    }

    ColumnLayout {
        id: contentColumn
        width: Math.min(parent.width - 48, 780)
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: 20
        spacing: 16

        RowLayout {
            Layout.fillWidth: true

            AppToolButton {
                visible: !root.ownProfile
                icon.source: "qrc:/assets/icons/back.svg"
                Accessible.name: "Назад"
                onClicked: root.StackView.view.pop()
            }

            Label {
                Layout.fillWidth: true
                text: root.ownProfile ? "Мой профиль" : "Профиль"
                font.pixelSize: 25
                font.bold: true
            }

            AppToolButton {
                icon.source: "qrc:/assets/icons/search.svg"
                Accessible.name: "Найти пользователя"
                onClicked: userSearchDialog.open()
            }

        }

        BusyIndicator {
            Layout.alignment: Qt.AlignHCenter
            running: root.profileLoading && !root.profileData
            visible: running
        }

        Rectangle {
            visible: root.profileFailed && !root.profileData
            Layout.fillWidth: true
            implicitHeight: 72
            radius: 14
            color: "#2b2027"

            Label {
                anchors.centerIn: parent
                text: "Не удалось загрузить профиль"
                color: "#ffd8d3"
            }
        }

        Rectangle {
            visible: root.ownProfile && !authManager.isLoggedIn
            Layout.fillWidth: true
            implicitHeight: unauthenticatedColumn.implicitHeight + 36
            radius: 18
            color: "#1e1b24"
            border.color: "#36343b"

            ColumnLayout {
                id: unauthenticatedColumn
                anchors.fill: parent
                anchors.margins: 18
                spacing: 10

                Label { text: "Вы не авторизованы"; font.pixelSize: 20; font.bold: true }
                Label {
                    Layout.fillWidth: true
                    text: "Войдите в аккаунт, чтобы увидеть профиль, историю и закладки."
                    wrapMode: Text.Wrap
                    color: "#cac4d0"
                }
                Button { text: "Войти в аккаунт"; onClicked: openAuthDialog() }
            }
        }

        ColumnLayout {
            visible: !!root.profileData || root.ownProfile && authManager.isLoggedIn
            Layout.fillWidth: true
            spacing: 16

            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: identity.y + identity.implicitHeight

                Rectangle {
                    id: banner
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    height: 150
                    radius: 20
                    color: "#2b2930"

                    CircleImage {
                        anchors.fill: parent
                        cornerRadius: banner.radius
                        source: root.bannerUrl()
                        visible: root.bannerUrl().length > 0
                    }

                    MouseArea {
                        anchors.fill: parent
                        enabled: root.bannerUrl().length > 0
                        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: root.openMedia(root.bannerUrl(), root.profileData?.login || "Профиль", "Обложка профиля")
                    }
                }

                Item {
                    width: 92
                    height: 92
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: parent.top
                    anchors.topMargin: 104

                    CircleImage {
                        anchors.fill: parent
                        source: root.avatarUrl()
                        visible: source.toString().length > 0
                    }

                    Rectangle {
                        anchors.fill: parent
                        radius: width / 2
                        visible: root.avatarUrl().length === 0
                        color: "#4f378b"

                        Label {
                            anchors.centerIn: parent
                            text: (root.profileData?.login || authManager.userLogin || "U").substring(0, 1).toUpperCase()
                            font.pixelSize: 42
                            font.bold: true
                            color: "white"
                        }
                    }

                    Rectangle {
                        visible: root.profileData?.is_online ?? false
                        width: 18
                        height: 18
                        radius: 9
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        color: "#47d16c"
                        border.color: "#1e1b24"
                        border.width: 3
                    }

                    MouseArea {
                        anchors.fill: parent
                        enabled: root.avatarUrl().length > 0
                        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: root.openMedia(root.avatarUrl(), root.profileData?.login || "Профиль", "Аватар")
                    }
                }

                ColumnLayout {
                    id: identity
                    anchors.top: parent.top
                    anchors.topMargin: 204
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 4

                    RowLayout {
                        Layout.alignment: Qt.AlignHCenter
                        spacing: 7

                        Label { text: root.profileData?.login || authManager.userLogin || ""; font.pixelSize: 22; font.bold: true }

                        Image {
                            source: root.profileData?.badge?.image_small_url || root.profileData?.badge?.image_url || ""
                            visible: source.toString().length > 0
                            Layout.preferredWidth: 24
                            Layout.preferredHeight: 24
                            fillMode: Image.PreserveAspectFit
                            mipmap: true
                        }
                    }

                    Label {
                        Layout.alignment: Qt.AlignHCenter
                        visible: text.length > 0
                        text: root.ownProfile && root.profileData?.register_date
                            ? "На проекте с " + Qt.formatDate(new Date(root.profileData.register_date * 1000), "d MMM yyyy")
                            : root.profileData?.is_online ? "В сети" : root.profileData?.last_activity_time
                                ? "Последний визит · " + Qt.formatDateTime(new Date(root.profileData.last_activity_time * 1000), "d MMM · hh:mm") : ""
                        color: "#b9afc1"
                        font.pixelSize: 12
                    }

                    Label {
                        Layout.alignment: Qt.AlignHCenter
                        visible: text.length > 0
                        text: root.profileData?.status || ""
                        color: "#d9c7e8"
                    }
                }
            }

            Label {
                Layout.alignment: Qt.AlignHCenter
                visible: root.mediaNotice.length > 0
                text: root.mediaNotice
                color: "#ffb4ab"
            }

            AbstractButton {
                id: friendsButton
                Layout.alignment: Qt.AlignHCenter
                visible: !!root.profileData && (root.ownProfile || !(root.profileData?.is_counts_hidden ?? true))
                text: root.formatNumber(root.profileData?.friend_count) + " · Друзья"
                padding: 7
                leftPadding: 12
                rightPadding: 12
                hoverEnabled: true

                background: Rectangle {
                    radius: height / 2
                    color: friendsButton.down ? "#403350" : friendsButton.hovered ? "#2a2236" : "transparent"
                }

                contentItem: RowLayout {
                    spacing: 8

                    Row {
                        spacing: -5

                        Repeater {
                            model: root.profileData?.friends_preview || []
                            delegate: CircleImage {
                                required property var modelData
                                width: 24
                                height: 24
                                source: modelData.avatar || ""
                            }
                        }
                    }

                    Label { text: friendsButton.text; color: "#e2d9ed" }
                }

                onClicked: root.StackView.view.push("qrc:/qml/FriendsPage.qml", {userId: root.profileUserId})
            }

            RowLayout {
                Layout.fillWidth: true
                visible: !!root.profileData
                spacing: 8

                RoundButton {
                    id: editProfileButton
                    Layout.fillWidth: true
                    implicitHeight: 44
                    visible: root.ownProfile
                    text: "Редактировать профиль"
                    icon.source: "qrc:/assets/icons/edit.svg"
                    background: Rectangle {
                        radius: height / 2
                        color: editProfileButton.down ? "#4a355e" : editProfileButton.hovered ? "#3a2c4a" : "#2b2237"
                    }
                    onClicked: root.StackView.view.push("qrc:/qml/EditProfilePage.qml",
                        {profileData: root.profileData, bannerUrl: root.bannerUrl()})
                }

                Item { Layout.fillWidth: true; visible: !root.ownProfile }

                RoundButton {
                    id: moreProfileButton
                    implicitWidth: 44
                    implicitHeight: 44
                    icon.source: "qrc:/assets/icons/more_vert.svg"
                    Accessible.name: "Действия с профилем"
                    background: Rectangle {
                        radius: height / 2
                        color: moreProfileButton.down ? "#4a355e" : moreProfileButton.hovered ? "#3a2c4a" : "#2b2237"
                    }
                    onClicked: moreMenu.popup(this, 0, height)
                }
            }

            Label {
                visible: !root.ownProfile && (root.profileData?.is_private ?? false)
                Layout.alignment: Qt.AlignHCenter
                text: "Профиль закрыт"
                color: "#cac4d0"
            }

            Rectangle {
                visible: root.publicSections && !!root.profileData
                Layout.fillWidth: true
                implicitHeight: sectionContent.implicitHeight + 24
                radius: 21
                border.color: "#453950"
                gradient: Gradient {
                    GradientStop { position: 0; color: root.themeColor() }
                    GradientStop { position: 1; color: "#201a29" }
                }

                ColumnLayout {
                    id: sectionContent
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 10

                    SectionStrip {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.maximumWidth: sectionContent.width
                        visible: root.publicSections && !!root.profileData
                        sections: root.sections
                        selection: root.activeSection
                        onActivated: key => root.activeSection = key
                    }

                    Rectangle {
                        visible: root.activeSection === "stats" && root.publicSections && !!root.profileData
                            && (root.ownProfile || !(root.profileData.is_counts_hidden ?? false))
                        Layout.fillWidth: true
                        implicitHeight: listColumn.implicitHeight + 28
                        radius: 16
                        color: "#1e1b24"
                        border.color: "#36343b"

                        ColumnLayout {
                            id: listColumn
                            anchors.fill: parent
                            anchors.margins: 14
                            spacing: 8

                            RowLayout {
                                Layout.fillWidth: true
                                Label { Layout.fillWidth: true; text: "В списках"; font.pixelSize: 17; font.bold: true }
                                Label { text: root.formatNumber(root.listTotal); color: "#c9bfd3" }
                            }

                            Row {
                                id: listBar
                                Layout.fillWidth: true
                                Layout.preferredHeight: 8
                                visible: root.listTotal > 0
                                spacing: 2

                                Repeater {
                                    id: listSegments
                                    model: root.listStats.filter(status => status.value > 0)
                                    Rectangle {
                                        required property var modelData
                                        width: Math.max(0, (listBar.width - Math.max(0, listSegments.count - 1) * listBar.spacing)
                                            * modelData.value / Math.max(1, root.listTotal))
                                        height: listBar.height
                                        radius: height / 2
                                        color: modelData.color
                                    }
                                }
                            }

                            Repeater {
                                model: root.listStats
                                delegate: RowLayout {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    Rectangle { width: 8; height: 8; radius: 4; color: modelData.color }
                                    Label { Layout.fillWidth: true; text: modelData.label; color: "#cac4d0" }
                                    Label { text: root.formatNumber(modelData.value); font.bold: true }
                                }
                            }
                        }
                    }

                    GridLayout {
                        visible: root.activeSection === "stats" && root.publicSections && !!root.profileData
                            && (root.ownProfile || !(root.profileData.is_stats_hidden ?? false))
                        Layout.fillWidth: true
                        columns: 2
                        columnSpacing: 10
                        rowSpacing: 10

                        Repeater {
                            model: [
                                { label: "Серий просмотрено", value: root.formatNumber(root.profileData?.watched_episode_count) },
                                { label: "Время просмотра", value: root.formatWatchTime(root.profileData?.watched_time) }
                            ]

                            delegate: Rectangle {
                                required property var modelData
                                Layout.fillWidth: true
                                implicitHeight: 76
                                radius: 14
                                color: "#1e1b24"
                                border.color: "#36343b"

                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.margins: 12
                                    spacing: 2
                                    Label { text: modelData.value; font.pixelSize: 20; font.bold: true }
                                    Label { text: modelData.label; color: "#938f99"; font.pixelSize: 12 }
                                }
                            }
                        }
                    }

                    Rectangle {
                        visible: root.activeSection === "stats" && root.publicSections && !!root.profileData
                            && (root.ownProfile || !root.profileData.is_stats_hidden)
                        Layout.fillWidth: true
                        implicitHeight: tasteContent.implicitHeight + 28
                        radius: 16
                        gradient: Gradient {
                            GradientStop { position: 0; color: root.themeColor() }
                            GradientStop { position: 1; color: "#1e1b24" }
                        }

                        RowLayout {
                            id: tasteContent
                            anchors.fill: parent
                            anchors.margins: 14
                            Label {
                                Layout.fillWidth: true
                                text: [
                                    {label: "Жанры", items: root.profileData?.preferred_genres || []},
                                    {label: "Аудитория", items: root.profileData?.preferred_audiences || []},
                                    {label: "Тематика", items: root.profileData?.preferred_themes || []}
                                ].filter(group => group.items.length).map(group => group.label + " · "
                                    + group.items.map(value => value.name + " " + value.percentage + "%").join(", ")).join("\n") || "Предпочтения пока не определены"
                                wrapMode: Text.Wrap
                            }
                            Label { text: root.themeMark(); color: "#ffbad6"; font.pixelSize: 24; visible: text.length > 0 }
                        }
                    }

                    Rectangle {
                        visible: root.activeSection === "stats" && root.publicSections && (root.profileData?.watch_dynamics || []).length > 0
                        Layout.fillWidth: true
                        implicitHeight: 156
                        radius: 16
                        color: "#1e1b24"
                        border.color: "#36343b"

                        Label { anchors.left: parent.left; anchors.top: parent.top; anchors.margins: 14; text: "Динамика просмотра"; font.pixelSize: 17; font.bold: true }

                        Row {
                            id: dynamicsGraph
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            anchors.margins: 14
                            height: 90

                            readonly property var days: (root.profileData?.watch_dynamics || []).slice(-10)
                            readonly property real maximum: Math.max(1, ...days.map(day => Number(day.count || 0)))

                            Repeater {
                                model: dynamicsGraph.days

                                delegate: Item {
                                    required property var modelData
                                    width: dynamicsGraph.width / Math.max(1, dynamicsGraph.days.length)
                                    height: dynamicsGraph.height

                                    Column {
                                        anchors.centerIn: parent
                                        width: parent.width
                                        spacing: 3

                                        Label {
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            text: modelData.count ?? 0
                                            font.pixelSize: 11
                                        }

                                        Item {
                                            width: parent.width
                                            height: 49

                                            Rectangle {
                                                anchors.horizontalCenter: parent.horizontalCenter
                                                anchors.bottom: parent.bottom
                                                width: Math.min(20, parent.width * 0.48)
                                                height: Math.max(3, parent.height * Number(modelData.count || 0) / dynamicsGraph.maximum)
                                                radius: 3
                                                color: "#cfbcff"
                                            }
                                        }

                                        Label {
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            text: Qt.formatDate(new Date(modelData.timestamp * 1000), "dd.MM")
                                            color: "#cbc1d2"
                                            font.pixelSize: 10
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Rectangle {
                        visible: root.activeSection === "badges" && root.publicSections
                        Layout.fillWidth: true
                        implicitHeight: badgeColumn.implicitHeight + 28
                        radius: 16
                        color: "#1e1b24"
                        border.color: "#36343b"

                        ColumnLayout {
                            id: badgeColumn
                            anchors.fill: parent
                            anchors.margins: 14
                            spacing: 10
                            Button {
                                text: root.ownProfile ? "Установить значок" : "Все значки"
                                highlighted: root.ownProfile
                                onClicked: window.openProfileExtras("profileBadges", root.profileUserId, root.ownProfile)
                            }
                            Flow {
                                Layout.fillWidth: true
                                spacing: 10
                                Repeater {
                                    model: root.badges
                                    delegate: Item {
                                        required property var modelData
                                        width: 54
                                        height: 54
                                        Image {
                                            anchors.fill: parent
                                            source: modelData.image_small_url || modelData.image_url || modelData.url || ""
                                            fillMode: Image.PreserveAspectFit
                                            mipmap: true
                                        }
                                        ToolTip.visible: badgeMouse.containsMouse
                                        ToolTip.text: modelData.name || "Значок"
                                        MouseArea { id: badgeMouse; anchors.fill: parent; hoverEnabled: true }
                                    }
                                }
                            }
                        }
                    }

                    ColumnLayout {
                        visible: root.activeSection === "stats" && root.publicSections && (root.profileData?.friends_preview || []).length > 0
                            && (root.ownProfile || !(root.profileData?.is_social_hidden ?? false))
                        Layout.fillWidth: true
                        spacing: 8
                        RowLayout {
                            Layout.fillWidth: true
                            Label { Layout.fillWidth: true; text: "Друзья"; font.pixelSize: 17; font.bold: true }
                            AppToolButton { text: "›"; Accessible.name: "Все друзья"; onClicked: root.StackView.view.push("qrc:/qml/FriendsPage.qml", { userId: root.profileUserId }) }
                        }
                        Flow {
                            Layout.fillWidth: true
                            spacing: 8
                            Repeater {
                                model: root.profileData?.friends_preview || []
                                delegate: IdentityButton {
                                    required property var modelData
                                    text: modelData.login || "Пользователь"
                                    avatarSource: modelData.avatar || ""
                                    showName: false
                                    enabled: modelData.id > 0
                                    ToolTip.text: text
                                    ToolTip.visible: hovered
                                    onClicked: window.openProfile(modelData.id)
                                }
                            }
                        }
                    }

                    ColumnLayout {
                        visible: root.activeSection === "stats" && root.publicSections && (root.profileData?.history || []).length > 0
                        Layout.fillWidth: true
                        spacing: 8
                        Label { text: "Просмотрено недавно"; font.pixelSize: 17; font.bold: true }
                        Flickable {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 210
                            contentWidth: historyRow.width
                            clip: true
                            Row {
                                id: historyRow
                                spacing: 10
                                Repeater {
                                    model: root.profileData?.history || []
                                    delegate: AnimeCard {
                                        width: 122
                                        height: 205
                                        compact: true
                                        releaseData: modelData
                                        subtitle: modelData.last_view_episode?.name || ""
                                        onClicked: window.openRelease(modelData.id)
                                    }
                                }
                            }
                        }
                    }

                    ColumnLayout {
                        visible: root.activeSection === "comments" && root.publicSections
                        Layout.fillWidth: true

                        Repeater {
                            model: root.profileData?.comments_preview || []

                            delegate: ItemDelegate {
                                id: commentItem
                                required property var modelData
                                Layout.fillWidth: true
                                enabled: modelData.release?.id > 0
                                text: (modelData.release?.title_ru || "Комментарий") + "\n"
                                    + (modelData.is_spoiler ? "Спойлер" : modelData.message || "")
                                background: Rectangle {
                                    radius: 12
                                    color: commentItem.down ? "#4a385e"
                                        : commentItem.hovered || commentItem.activeFocus ? "#2d2539" : "transparent"
                                }
                                onClicked: window.openReleaseComments(modelData.release.id, modelData.release.title_ru, modelData.id)
                            }
                        }

                        Button {
                            text: root.profileData?.comment_count > 0 ? "Все комментарии · " + root.profileData.comment_count : "Все комментарии"
                            onClicked: root.openComments()
                        }
                    }

                    Flow {
                        visible: root.activeSection === "ratings" && root.sectionRows.length > 0
                        Layout.fillWidth: true
                        spacing: 12
                        Repeater {
                            model: root.sectionRows
                            delegate: AnimeCard {
                                required property var modelData
                                width: 144
                                height: 238
                                compact: true
                                releaseData: modelData.release || modelData
                                subtitle: "Оценка · " + (modelData.my_vote || modelData.vote || "—")
                                onClicked: window.openRelease((modelData.release || modelData).id)
                            }
                        }
                    }

                    Button {
                        visible: root.activeSection === "ratings" && root.sectionRows.length > 0
                        text: "Все оценки"
                        onClicked: window.openProfileExtras("profileRatings", root.profileUserId, root.ownProfile)
                    }

                    Repeater {
                        model: root.activeSection === "collections" || root.activeSection === "videos" ? root.sectionRows : []
                        delegate: Rectangle {
                            required property var modelData
                            Layout.fillWidth: true
                            implicitHeight: 58
                            radius: 12
                            color: "#1e1b24"
                            border.color: "#36343b"
                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 12
                                Label { Layout.fillWidth: true; text: root.titleFor(modelData); elide: Text.ElideRight }
                                Label { text: "›"; color: "#938f99" }
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (root.activeSection === "collections" && modelData.id) {
                                        root.StackView.view.push("qrc:/qml/ReleaseGridPage.qml", {
                                            mode: "collection",
                                            collectionId: modelData.id,
                                            heading: root.titleFor(modelData)
                                        });
                                    } else if (root.activeSection === "videos" && (modelData.url || modelData.video_url)) {
                                        Qt.openUrlExternally(modelData.url || modelData.video_url);
                                    }
                                }
                            }
                        }
                    }

                    Label {
                        visible: root.publicSections && root.activeSection !== "stats" && root.activeSection !== "comments" && root.activeSection !== "badges" && root.sectionRows.length === 0
                        Layout.alignment: Qt.AlignHCenter
                        text: "Здесь пока ничего нет"
                        color: "#938f99"
                    }
                }
            }
        }

        Item { Layout.preferredHeight: 24 }
    }

    Menu {
        id: moreMenu

        MenuItem {
            text: "История никнейма"
            icon.source: "qrc:/assets/icons/search.svg"
            onTriggered: window.openProfileExtras("profileLoginHistory", root.profileUserId, root.ownProfile)
        }
        MenuItem {
            text: "Поделиться ссылкой"
            icon.source: "qrc:/assets/icons/share.svg"
            onTriggered: Qt.callLater(function() { shareDialog.open(); })
        }
        MenuItem {
            text: "Скопировать ссылку"
            icon.source: "qrc:/assets/icons/copy.svg"
            onTriggered: root.copyProfileLink()
        }
    }

    Dialog {
        id: shareDialog
        parent: Overlay.overlay
        anchors.centerIn: parent
        width: Math.min(parent.width - 40, 420)
        title: "Поделиться профилем"
        modal: true
        Overlay.modal: Rectangle { color: "#bb000000" }

        ColumnLayout {
            width: parent.width
            TextField {
                Layout.fillWidth: true
                text: root.profileLink()
                readOnly: true
                selectByMouse: true
            }
            Button {
                text: "Скопировать"
                icon.source: "qrc:/assets/icons/copy.svg"
                onClicked: {
                    root.copyProfileLink();
                    shareDialog.close();
                }
            }
            Button {
                text: "Открыть почту"
                onClicked: Qt.openUrlExternally("mailto:?body=" + encodeURIComponent(root.profileLink()))
            }
        }
    }
}
