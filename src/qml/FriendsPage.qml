import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Controls.Material 2.15
import QtQuick.Layouts 1.15
import Anixart 1.0

Rectangle {
    id: root
    color: "#141218"

    property var userId: authManager.userId
    property var friendsList: []
    property bool loading: false
    property int currentPage: -1
    property int totalFriends: 0
    property bool hasMore: false
    readonly property Flickable pullSurface: friendsView
    readonly property bool refreshing: loading
    property bool contactLoading: false
    property var selectedFriend: null
    property var selectedContact: null
    property string contactNotice: ""

    Component.onCompleted: refresh()

    onUserIdChanged: {
        if (visible) refresh();
    }

    function refresh() {
        loadFriends(0);
    }

    function loadFriends(page) {
        if (!(userId > 0) || loading) return;

        loading = true;
        anixApi.fetchProfileFriends(userId, page, authManager.token);
    }

    function networkLinks(profile) {
        const sources = [
            {label: "ВКонтакте", value: profile.vk_page, base: "https://vk.com/", icon: "vk"},
            {label: "Telegram", value: profile.tg_page, base: "https://t.me/", icon: "telegram"},
            {label: "Discord", value: profile.discord_page, base: "https://discord.com/users/", icon: "discord"},
            {label: "TikTok", value: profile.tt_page, base: "https://www.tiktok.com/@", icon: "tiktok"},
            {label: "Instagram", value: profile.inst_page, base: "https://www.instagram.com/", icon: "instagram"}
        ];
        return sources.map(source => {
            const value = (source.value || "").trim();
            let url = "";
            if (/^https?:\/\/[^\s]+$/i.test(value)) url = value;
            else if (/^(?:www\.)?(?:vk\.com|t\.me|discord\.gg|discord\.com|tiktok\.com|instagram\.com)\/[^\s]+$/i.test(value))
                url = "https://" + value;
            else if (source.icon !== "discord" && /^@?[a-z0-9_.-]+$/i.test(value))
                url = source.base + value.replace(/^@/, "");
            else if (source.icon === "discord" && /^\d+$/.test(value))
                url = source.base + value;
            return {label: source.label, url: url, icon: source.icon, handle: value};
        }).filter(contact => contact.url || contact.icon === "discord" && contact.handle.length > 0);
    }

    function openContact(friend) {
        if (!friend?.is_social || !(friend.id > 0) || contactLoading) return;

        selectedFriend = friend;
        contactNotice = "";
        contactLoading = true;
        anixApi.fetchBrowseSection("profileSocial", 0, friend.id, authManager.token);
    }

    Connections {
        target: anixApi

        function onProfileFriendsLoaded(id, friends, page, total) {
            if (id !== root.userId) return;
            root.loading = false;
            root.currentPage = page;
            root.totalFriends = total;
            root.friendsList = page === 0 ? friends : root.friendsList.concat(friends);
            root.hasMore = friends.length > 0 && root.friendsList.length < total;
        }

        function onBrowseSectionLoaded(section, page, id, query, data) {
            if (section !== "profileSocial" || !root.selectedFriend || id !== root.selectedFriend.id || !root.contactLoading) return;

            root.contactLoading = false;
            root.selectedContact = root.networkLinks(data);
            if (root.selectedContact.length > 0) socialPopup.open();
            else root.contactNotice = data.code === 0 ? "У пользователя нет доступных контактов" : "Не удалось загрузить контакты";
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 20
        spacing: 14

        RowLayout {
            Layout.fillWidth: true

            AppToolButton {
                icon.source: "qrc:/assets/icons/back.svg"
                Accessible.name: "Назад"
                onClicked: root.StackView.view.pop()
            }
            Label { text: "Друзья"; font.pixelSize: 22; font.bold: true }
            Item { Layout.fillWidth: true }
            AppToolButton {
                icon.source: "qrc:/assets/icons/search.svg"
                Accessible.name: "Поиск пользователей"
                onClicked: userSearch.open()
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Label { text: root.userId === authManager.userId ? "Мои друзья" : "Друзья пользователя"; font.pixelSize: 17; font.bold: true }
            Rectangle {
                width: countLabel.implicitWidth + 12
                height: 20
                radius: 10
                color: "#2b2930"
                Label { id: countLabel; anchors.centerIn: parent; text: root.totalFriends; font.pixelSize: 12; color: "#cac4d0" }
            }
            Item { Layout.fillWidth: true }
        }

        BusyIndicator {
            Layout.alignment: Qt.AlignHCenter
            running: root.loading && root.friendsList.length === 0
            visible: running
        }

        Label {
            Layout.alignment: Qt.AlignHCenter
            visible: !root.loading && root.friendsList.length === 0
            text: "Список друзей пуст или скрыт"
            color: "#938f99"
        }

        Label {
            Layout.alignment: Qt.AlignHCenter
            visible: root.contactLoading || root.contactNotice.length > 0
            text: root.contactLoading ? "Проверяем публичные ссылки…" : root.contactNotice
            color: "#938f99"
        }

        ListView {
            id: friendsView
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            model: root.friendsList
            spacing: 8
            ScrollBar.vertical: AppScrollBar {}
            onAtYEndChanged: {
                if (atYEnd && root.hasMore) root.loadFriends(root.currentPage + 1);
            }

            footer: Button {
                visible: root.hasMore
                enabled: !root.loading
                text: "Ещё друзья"
                onClicked: root.loadFriends(root.currentPage + 1)
            }

            delegate: Item {
                id: friendRow
                required property var modelData
                width: friendsView.width
                height: 64

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    spacing: 12

                    IdentityButton {
                        Layout.fillWidth: true
                        avatarSize: 44
                        text: friendRow.modelData.login || "Пользователь"
                        subtitle: (friendRow.modelData.friend_count || 0) + " друзей"
                        avatarSource: friendRow.modelData.avatar || ""
                        badgeSource: friendRow.modelData.badge_url || ""
                        online: friendRow.modelData.is_online === true
                        enabled: friendRow.modelData.id > 0
                        onClicked: window.openProfile(friendRow.modelData.id)
                    }

                    AppToolButton {
                        id: messageButton
                        z: 1
                        enabled: friendRow.modelData.is_social === true
                        opacity: enabled ? 1 : 0.4
                        icon.source: "qrc:/assets/icons/chat.svg"
                        Accessible.name: enabled ? "Открыть социальные ссылки" : "У пользователя нет социальных контактов"
                        onClicked: root.openContact(friendRow.modelData)
                    }
                }
            }
        }
    }

    UserSearchDialog { id: userSearch }

    Popup {
        id: socialPopup
        parent: Overlay.overlay
        anchors.centerIn: parent
        width: Math.min(parent.width - 40, 420)
        padding: 20
        modal: true
        Overlay.modal: Rectangle { color: "#bb000000" }
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

        background: Rectangle {
            color: "#1e1b24"
            radius: 20
            border.color: "#36343b"
        }

        ColumnLayout {
            width: parent.width
            spacing: 12

            Label { text: "Связаться с " + (root.selectedFriend?.login || "пользователем"); font.pixelSize: 19; font.bold: true }
            Repeater {
                model: root.selectedContact || []
                delegate: Button {
                    id: contactButton
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.preferredHeight: 42
                    topInset: 0
                    bottomInset: 0
                    topPadding: 0
                    bottomPadding: 0
                    leftPadding: 14
                    rightPadding: 14
                    text: modelData.url ? modelData.label : modelData.label + " · " + modelData.handle

                    contentItem: Item {
                        Image {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            width: 22
                            height: 22
                            source: "qrc:/assets/icons/" + contactButton.modelData.icon + ".svg"
                            fillMode: Image.PreserveAspectFit
                        }

                        Label {
                            anchors.fill: parent
                            anchors.leftMargin: 32
                            anchors.rightMargin: 32
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            text: contactButton.text
                            color: "#eee7f4"
                            elide: Text.ElideRight
                        }
                    }

                    background: Rectangle {
                        radius: height / 2
                        color: parent.down ? "#4c3b60" : parent.hovered ? "#382a49" : "#2a2336"
                        border.color: "#453952"
                    }
                    onClicked: {
                        if (modelData.url) Qt.openUrlExternally(modelData.url);
                        else authManager.copyToClipboard(modelData.handle);
                        socialPopup.close();
                    }
                }
            }
        }
    }
}
