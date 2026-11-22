import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Anixart 1.0

Flickable {
    id: root

    required property var profileData
    property string bannerUrl: ""
    property var preferences: null
    property var socials: null
    property string saving: ""
    property string notice: ""
    property bool statusEdited: false
    property var selectedPrivacy: null
    property var selectedProvider: null
    readonly property Flickable pullSurface: root
    readonly property bool refreshing: preferences === null
    readonly property var privacyOptions: ["Все пользователи", "Только друзья", "Только я"]
    readonly property var networks: [
        {label: "ВКонтакте", key: "vkPage", field: "vk_page"},
        {label: "Telegram", key: "tgPage", field: "tg_page"},
        {label: "Instagram", key: "instPage", field: "inst_page"},
        {label: "TikTok", key: "ttPage", field: "tt_page"},
        {label: "Discord", key: "discordPage", field: "discord_page"}
    ]

    contentWidth: width
    contentHeight: body.implicitHeight + 44
    clip: true

    ScrollBar.vertical: AppScrollBar {}

    function refresh() {
        anixApi.fetchBrowseSection("profilePreferences", 0, profileData.id, authManager.token);
        anixApi.fetchBrowseSection("profilePrivateSocial", 0, profileData.id, authManager.token);
    }

    function save(field, value) {
        if (saving || !authManager.isLoggedIn || profileData.id !== authManager.userId) return;

        notice = "";
        saving = field;
        anixApi.saveProfilePreference(field, value, authManager.token);
    }

    Component.onCompleted: refresh()

    Connections {
        target: anixApi

        function onBrowseSectionLoaded(section, page, id, query, data) {
            if (id !== root.profileData.id) return;

            if (section === "profilePreferences") {
                root.preferences = data;
                if (data.code === 0) {
                    if (!root.statusEdited) statusField.text = data.status || "";
                } else {
                    root.notice = "Не удалось загрузить настройки профиля";
                }
            } else if (section === "profilePrivateSocial") {
                root.socials = data;
            }
        }

        function onProfilePreferenceSaved(field, value, success) {
            if (root.saving !== field) return;

            root.saving = "";
            root.notice = success ? "Изменения сохранены" : "Не удалось сохранить изменения";
            if (success && field === "status") root.statusEdited = false;
            if (success || field !== "status" && field !== "social") root.refresh();
        }

        function onProfilePreferencesChanged() {
            if (!root.saving) root.refresh();
        }
    }

    Connections {
        target: authManager

        function onProviderBindingFinished(provider, success) {
            if (root.selectedProvider?.key !== provider) return;

            const binding = providerDialog.binding;
            providerDialog.close();
            root.notice = success
                ? (binding ? "Сервис привязан" : "Сервис отвязан")
                : (binding ? "Не удалось привязать сервис" : "Не удалось отвязать сервис");
            root.refresh();
        }

        function onAuthFailed(reason) {
            if (providerDialog.opened && providerDialog.binding && root.selectedProvider?.key === "google")
                providerDialog.error = reason;
        }
    }

    ColumnLayout {
        id: body
        anchors.horizontalCenter: parent.horizontalCenter
        y: 20
        width: Math.min(root.width - 40, 730)
        spacing: 12

        RowLayout {
            Layout.fillWidth: true

            AppToolButton {
                icon.source: "qrc:/assets/icons/back.svg"
                Accessible.name: "Назад"
                onClicked: root.StackView.view.pop()
            }

            Label { text: "Редактировать профиль"; font.pixelSize: 24; font.weight: Font.DemiBold }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 148
            radius: 18
            color: "#2b2930"

            CircleImage { anchors.fill: parent; cornerRadius: parent.radius; source: root.bannerUrl }
            CircleImage {
                anchors.centerIn: parent
                width: 84
                height: 84
                source: root.preferences?.avatar || root.profileData.avatar || ""
                TapHandler {
                    enabled: parent.source.length > 0
                    onTapped: window.openMedia(parent.source, root.profileData.login, "Аватар")
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true

            TextField {
                id: statusField
                Layout.fillWidth: true
                text: root.profileData.status || ""
                onTextEdited: root.statusEdited = true
                placeholderText: "Статус"
                maximumLength: 80
                enabled: root.preferences?.code === 0 && !root.saving
                onAccepted: if (saveStatus.enabled) root.save("status", text.trim())
            }

            AppToolButton {
                id: saveStatus
                icon.source: "qrc:/assets/icons/check_circle.svg"
                Accessible.name: "Сохранить статус"
                ToolTip.text: Accessible.name
                ToolTip.visible: hovered
                enabled: statusField.enabled && statusField.text.trim() !== (root.preferences?.status || "")
                onClicked: root.save("status", statusField.text.trim())
            }
        }

        Label { visible: root.notice.length > 0; text: root.notice; color: "#cfbcff"; wrapMode: Text.Wrap }

        RowLayout {
            Layout.fillWidth: true
            Label { Layout.fillWidth: true; text: root.profileData.login || ""; font.pixelSize: 17 }
            Button {
                text: "Значок"
                highlighted: true
                onClicked: window.openProfileExtras("profileBadges", root.profileData.id, true)
            }
            Button {
                text: "Социальные сети"
                highlighted: true
                enabled: root.socials?.code === 0 && !root.saving
                onClicked: socialDialog.open()
            }
        }

        Label { text: "Приватность"; color: "#cfbcff"; font.weight: Font.DemiBold }

        Repeater {
            model: [
                {label: "Статистика, оценки и история просмотра", field: "privacy_stats", key: "stats"},
                {label: "Комментарии, коллекции, видео и друзья", field: "privacy_counts", key: "counts"},
                {label: "Социальные сети", field: "privacy_social", key: "socialPrivacy"},
                {label: "Заявки в друзья", field: "privacy_friend_requests", key: "friendRequests"}
            ]

            delegate: ItemDelegate {
                id: privacyRow
                required property var modelData

                Layout.fillWidth: true
                padding: 14
                spacing: 5
                enabled: root.preferences?.code === 0 && !root.saving
                background: Rectangle {
                    radius: 12
                    color: privacyRow.hovered || privacyRow.activeFocus ? "#30283e" : "#211c29"
                }
                contentItem: RowLayout {
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 3
                        Label {
                            Layout.fillWidth: true
                            text: privacyRow.modelData.label
                            wrapMode: Text.Wrap
                        }
                        Label {
                            Layout.fillWidth: true
                            text: root.privacyOptions[root.preferences?.[privacyRow.modelData.field]] ?? "—"
                            color: "#c9bfd3"
                        }
                    }
                    Label { text: "›"; color: "#c9bfd3"; font.pixelSize: 20 }
                }
                onClicked: {
                    root.selectedPrivacy = modelData;
                    privacyDialog.open();
                }
            }
        }

        Label { text: "Аккаунт"; color: "#cfbcff"; font.weight: Font.DemiBold }

        RowLayout {
            Layout.fillWidth: true
            Label { Layout.fillWidth: true; text: "Email" }
            Label { text: root.preferences?.email_hint || "—"; color: "#c9bfd3" }
        }

        Label { Layout.topMargin: 8; text: "Привязанные сервисы"; color: "#cfbcff"; font.weight: Font.DemiBold }

        Repeater {
            model: [
                { label: "Яндекс", key: "yandex" }, { label: "ВКонтакте", key: "vk" },
                { label: "Telegram", key: "telegram" }, { label: "Google", key: "google" }
            ]

            delegate: SwitchDelegate {
                id: providerSwitch
                required property var modelData
                readonly property var bound: root.preferences?.["is_" + modelData.key + "_bound"]

                Layout.fillWidth: true
                text: modelData.label
                checked: bound === true
                enabled: typeof bound === "boolean" && !root.saving && !authManager.isAuthenticating
                onClicked: {
                    checked = Qt.binding(() => bound === true);
                    root.selectedProvider = modelData;
                    providerDialog.binding = !bound;
                    providerDialog.error = "";
                    providerDialog.open();
                }
                background: Rectangle {
                    radius: 12
                    color: providerSwitch.hovered || providerSwitch.activeFocus ? "#30283e" : "#211c29"
                }
            }
        }

        Button {
            Layout.topMargin: 8
            text: "Выйти из аккаунта"
            onClicked: logoutDialog.open()
        }
    }

    Dialog {
        id: logoutDialog
        parent: Overlay.overlay
        anchors.centerIn: parent
        modal: true
        Overlay.modal: Rectangle { color: "#bb000000" }
        title: "Выйти из аккаунта?"
        standardButtons: Dialog.Yes | Dialog.Cancel
        onOpened: {
            standardButton(Dialog.Yes).text = "Выйти";
            standardButton(Dialog.Cancel).text = "Отмена";
        }
        onAccepted: {
            root.StackView.view.pop();
            authManager.signOut();
        }
    }

    Dialog {
        id: socialDialog
        parent: Overlay.overlay
        anchors.centerIn: parent
        width: Math.min(parent.width - 40, 480)
        modal: true
        Overlay.modal: Rectangle { color: "#bb000000" }
        title: "Социальные сети"
        standardButtons: Dialog.Save | Dialog.Cancel
        onOpened: {
            standardButton(Dialog.Save).text = "Сохранить";
            standardButton(Dialog.Cancel).text = "Отмена";
            for (let i = 0; i < socialFields.count; ++i)
                socialFields.itemAt(i).text = root.socials[root.networks[i].field] || "";
        }
        onAccepted: {
            const values = {};
            for (let i = 0; i < socialFields.count; ++i)
                values[root.networks[i].key] = socialFields.itemAt(i).text.trim();
            root.save("social", values);
        }

        contentItem: ColumnLayout {
            spacing: 14

            Repeater {
                id: socialFields
                model: root.networks

                delegate: ColumnLayout {
                    required property var modelData
                    property alias text: field.text

                    Layout.fillWidth: true
                    spacing: 4
                    Label { text: modelData.label; color: "#c9bfd3" }
                    TextField {
                        id: field
                        Layout.fillWidth: true
                        Accessible.name: modelData.label
                        selectByMouse: true
                    }
                }
            }
        }
    }

    Dialog {
        id: privacyDialog
        parent: Overlay.overlay
        anchors.centerIn: parent
        width: Math.min(parent.width - 40, 480)
        modal: true
        Overlay.modal: Rectangle { color: "#bb000000" }
        title: "Кому видно"
        standardButtons: Dialog.Cancel
        onOpened: standardButton(Dialog.Cancel).text = "Отмена"

        contentItem: ColumnLayout {
            Label {
                Layout.fillWidth: true
                text: root.selectedPrivacy?.label || ""
                color: "#c9bfd3"
                wrapMode: Text.Wrap
            }
            Repeater {
                model: root.privacyOptions
                RadioDelegate {
                    required property string modelData
                    required property int index

                    Layout.fillWidth: true
                    text: modelData
                    checked: index === root.preferences?.[root.selectedPrivacy?.field]
                    onClicked: {
                        if (index !== root.preferences?.[root.selectedPrivacy.field])
                            root.save(root.selectedPrivacy.key, index);
                        privacyDialog.close();
                    }
                }
            }
        }
    }

    Dialog {
        id: providerDialog
        property bool binding: false
        property string error: ""
        readonly property bool browserBinding: binding && root.selectedProvider?.key === "google"

        parent: Overlay.overlay
        anchors.centerIn: parent
        width: Math.min(parent.width - 40, 480)
        modal: true
        closePolicy: authManager.isAuthenticating ? Popup.NoAutoClose : Popup.CloseOnEscape | Popup.CloseOnPressOutside
        Overlay.modal: Rectangle { color: "#bb000000" }
        title: binding ? "Привязка учётной записи" : "Отвязка учётной записи"
        onClosed: {
            if (browserBinding && authManager.isWaitingBrowserAuth) authManager.cancelBrowserAuth();
        }

        contentItem: ColumnLayout {
            spacing: 12
            Label {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                text: !providerDialog.binding
                    ? "Отвязать " + (root.selectedProvider?.label || "") + " от профиля? Для входа через этот сервис потребуется привязать его снова."
                    : providerDialog.browserBinding
                        ? "Выберите аккаунт Google в браузере. Привязка обновится после подтверждения."
                        : "Откройте Anixart на телефоне и включите «" + (root.selectedProvider?.label || "")
                            + "» в разделе «Привязка к сервисам». Затем обновите настройки здесь."
            }
            Label {
                Layout.fillWidth: true
                visible: providerDialog.error.length > 0
                wrapMode: Text.Wrap
                color: "#ffb4ab"
                text: providerDialog.error
            }
            RowLayout {
                Layout.alignment: Qt.AlignRight
                Button {
                    text: "Отмена"
                    flat: true
                    enabled: !authManager.isAuthenticating
                    onClicked: providerDialog.close()
                }
                Button {
                    text: !providerDialog.binding ? "Отвязать"
                        : !providerDialog.browserBinding ? "Обновить"
                        : authManager.isWaitingBrowserAuth ? "Открыть браузер" : "Привязать"
                    highlighted: true
                    enabled: !authManager.isAuthenticating
                    onClicked: {
                        if (!providerDialog.binding) {
                            authManager.unlinkProvider(root.selectedProvider.key);
                        } else if (!providerDialog.browserBinding) {
                            root.refresh();
                            providerDialog.close();
                        } else if (authManager.isWaitingBrowserAuth) {
                            authManager.reopenBrowserAuth();
                        } else {
                            providerDialog.error = "";
                            authManager.startBrowserAuth(true);
                        }
                    }
                }
            }
        }
    }
}
