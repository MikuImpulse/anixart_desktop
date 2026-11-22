import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Controls.Material 2.15
import QtQuick.Layouts 1.15

Dialog {
    id: root
    title: ""
    modal: true
    anchors.centerIn: parent
    width: Math.min(600, parent.width - 40)
    padding: 24

    background: Rectangle {
        color: "#211a2d"
        radius: 18
        border.color: "#493959"
    }

    Overlay.modal: Rectangle {
        color: Qt.rgba(0, 0, 0, 0.75)
    }

    Material.theme: Material.Dark
    Material.accent: "#cfbcff"
    Material.background: "#1d192b"

    property string statusMessage: ""
    property bool isError: false
    property string phoneProvider: ""
    property string emailMode: ""
    property string verificationHash: ""
    property int verificationLength: 5
    property int resendDelay: 0
    readonly property bool recovering: emailMode === "restore"
    closePolicy: authManager.isAuthenticating ? Popup.NoAutoClose : Popup.CloseOnEscape | Popup.CloseOnPressOutside

    function resetEmailForm() {
        verificationHash = "";
        resendDelay = 0;
        emailLogin.clear();
        emailAddress.clear();
        newPassword.clear();
        repeatPassword.clear();
        verificationCode.clear();
    }

    function openEmailForm(mode) {
        resetEmailForm();
        statusMessage = "";
        emailMode = mode;
        if (recovering) emailLogin.text = loginInput.text;
        emailLogin.forceActiveFocus();
    }

    onOpened: {
        root.statusMessage = "";
        root.phoneProvider = "";
        if (authTabs.currentIndex === 2) authManager.startQrAuth();
    }

    onClosed: {
        authManager.cancelBrowserAuth();
        authManager.cancelQrAuth();
        passInput.clear();
        showPassword.checked = false;
        emailMode = "";
        resetEmailForm();
    }

    Connections {
        target: authManager
        function onAuthSuccess(profile) {
            root.isError = false;
            root.statusMessage = "Успешный вход! Добро пожаловать, " + (profile.login || "");
            root.close();
        }
        function onAuthFailed(reason) {
            root.isError = true;
            root.statusMessage = reason;
        }
        function onBrowserAuthChanged() {
            root.statusMessage = "";
        }
        function onEmailCodeReady(hash, length, retryAfter) {
            if (!root.visible || !root.emailMode) return;
            root.verificationHash = hash;
            root.verificationLength = length;
            root.resendDelay = retryAfter;
            root.statusMessage = "";
            verificationCode.clear();
            verificationCode.forceActiveFocus();
        }
        function onPasswordRestored() {
            loginInput.text = emailLogin.text;
            passInput.clear();
            root.emailMode = "";
            root.resetEmailForm();
            authTabs.currentIndex = 1;
            root.statusMessage = "Пароль изменён. Войдите с новым паролем.";
            root.isError = false;
            passInput.forceActiveFocus();
        }
    }

    Timer {
        interval: 1000
        repeat: true
        running: root.resendDelay > 0
        onTriggered: --root.resendDelay
    }

    contentItem: ColumnLayout {
        id: mainContentCol
        spacing: 14

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 14
            visible: authManager && authManager.isWaitingBrowserAuth

            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 36

                RowLayout {
                    anchors.centerIn: parent
                    spacing: 10

                    Image {
                        Layout.preferredWidth: 26
                        Layout.preferredHeight: 26
                        source: "qrc:/assets/icons/google.svg"
                        sourceSize: Qt.size(26, 26)
                        smooth: true
                    }

                    Text {
                        text: "Вход через Google"
                        font.pixelSize: 18
                        font.bold: true
                        color: "#e6e1e5"
                    }
                }

                RoundButton {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    flat: true
                    width: 36
                    height: 36
                    contentItem: Image {
                        anchors.centerIn: parent
                        width: 20
                        height: 20
                        source: "qrc:/assets/icons/close.svg"
                        sourceSize: Qt.size(20, 20)
                    }
                    onClicked: authManager.cancelBrowserAuth()
                }
            }

            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: 12

                BusyIndicator {
                    Layout.preferredWidth: 28
                    Layout.preferredHeight: 28
                    running: authManager && authManager.isWaitingBrowserAuth
                    Material.accent: "#cfbcff"
                }

                Text {
                    text: "Ожидание авторизации..."
                    font.pixelSize: 15
                    font.bold: true
                    color: "#cfbcff"
                }
            }

            Text {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                text: "Выберите аккаунт в браузере. Результат входа автоматически появится в Anixart."
                font.pixelSize: 13
                color: "#cac4d0"
            }

            RowLayout {
                Layout.fillWidth: true

                Button {
                    Layout.fillWidth: true
                    text: "Открыть браузер"
                    onClicked: authManager.reopenBrowserAuth()
                }

                Button {
                    text: "Войти с телефона"
                    onClicked: {
                        authManager.cancelBrowserAuth();
                        root.phoneProvider = "Google";
                        authTabs.currentIndex = 2;
                    }
                }

                Button {
                    text: "Отмена"
                    onClicked: authManager.cancelBrowserAuth()
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 12
            visible: !root.emailMode && (!authManager || !authManager.isWaitingBrowserAuth)

            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 36

                RowLayout {
                    anchors.centerIn: parent
                    spacing: 10

                    Image {
                        Layout.preferredWidth: 26
                        Layout.preferredHeight: 26
                        source: "qrc:/assets/anixart_symbol.png"
                        sourceSize: Qt.size(26, 26)
                        smooth: true
                        mipmap: true
                    }

                    Text {
                        text: "Вход в Anixart"
                        font.pixelSize: 18
                        font.bold: true
                        color: "#e6e1e5"
                    }
                }

                RoundButton {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    flat: true
                    width: 36
                    height: 36
                    contentItem: Image {
                        anchors.centerIn: parent
                        width: 20
                        height: 20
                        source: "qrc:/assets/icons/close.svg"
                        sourceSize: Qt.size(20, 20)
                    }
                    enabled: !authManager.isAuthenticating
                    onClicked: root.close()
                }
            }

            TabBar {
                id: authTabs
                Layout.fillWidth: true
                enabled: !authManager.isAuthenticating
                currentIndex: 0
                Material.accent: "#cfbcff"

                TabButton { text: "Сервисы" }
                TabButton { text: "Логин и пароль" }
                TabButton { text: "Вход с телефона" }

                onCurrentIndexChanged: {
                    root.statusMessage = "";
                    if (currentIndex === 2 && root.opened) {
                        authManager.startQrAuth();
                    } else {
                        authManager.cancelQrAuth();
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignHCenter
                visible: root.statusMessage.length > 0
                text: root.statusMessage
                font.pixelSize: 13
                font.bold: true
                color: root.isError ? "#ffb4ab" : "#47d16c"
                wrapMode: Text.WordWrap
                horizontalAlignment: Text.AlignHCenter
            }

            StackLayout {
                Layout.fillWidth: true
                Layout.minimumHeight: 0
                Layout.preferredHeight: [serviceTab, passwordTab, phoneTab][currentIndex]?.implicitHeight ?? 0
                currentIndex: authTabs.currentIndex

                ColumnLayout {
                    id: serviceTab
                    spacing: 8

                    Text {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        text: "Google открывается в браузере. Для Яндекса и Telegram доступен вход с телефона."
                        wrapMode: Text.WordWrap
                        font.pixelSize: 12
                        font.weight: Font.Medium
                        color: "#938f99"
                    }

                    GridLayout {
                        Layout.fillWidth: true
                        columns: 2
                        columnSpacing: 10
                        rowSpacing: 8

                        Repeater {
                            model: [
                                { title: "Google", provider: "google" },
                                { title: "ВКонтакте", provider: "vk" },
                                { title: "Яндекс", provider: "yandex" },
                                { title: "Telegram", provider: "telegram" }
                            ]
                            delegate: Button {
                                id: providerButton
                                required property var modelData

                                Layout.fillWidth: true
                                Layout.preferredHeight: 42
                                text: modelData.title
                                icon.source: "qrc:/assets/icons/" + modelData.provider + ".svg"
                                icon.color: "transparent"
                                icon.width: 20
                                icon.height: 20
                                enabled: !authManager.isAuthenticating
                                onClicked: {
                                    if (modelData.provider === "google") {
                                        authManager.startBrowserAuth();
                                    } else if (modelData.provider === "vk") {
                                        root.isError = true;
                                        root.statusMessage = "Вход через ВКонтакте в браузере недоступен.";
                                    } else {
                                        root.phoneProvider = modelData.title;
                                        authTabs.currentIndex = 2;
                                    }
                                }

                                background: Rectangle {
                                    radius: 9
                                    color: providerButton.hovered || providerButton.activeFocus ? "#473659" : "#2d233b"
                                    border.color: "#493959"
                                    Behavior on color { ColorAnimation { duration: 140 } }
                                }
                            }
                        }
                    }

                    Button {
                        id: registerButton
                        Layout.fillWidth: true
                        Layout.preferredHeight: 42
                        text: "Создать аккаунт"
                        enabled: !authManager.isAuthenticating
                        onClicked: root.openEmailForm("register")
                        background: Rectangle {
                            radius: 9
                            color: registerButton.hovered || registerButton.activeFocus ? "#473659" : "#2d233b"
                            border.color: "#493959"
                        }
                    }
                }

                ColumnLayout {
                    id: passwordTab
                    spacing: 12

                    Text {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        text: "Введите данные вашей учетной записи:"
                        font.pixelSize: 13
                        color: "#cac4d0"
                    }

                    TextField {
                        id: loginInput
                        Layout.fillWidth: true
                        placeholderText: "Логин или Email"
                        color: "#e6e1e5"
                        selectByMouse: true
                    }

                    TextField {
                        id: passInput
                        Layout.fillWidth: true
                        placeholderText: "Пароль"
                        echoMode: showPassword.checked ? TextInput.Normal : TextInput.Password
                        color: "#e6e1e5"
                        selectByMouse: true
                        onAccepted: if (loginBtn.enabled) loginBtn.clicked()
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        CheckBox {
                            id: showPassword
                            text: "Показать пароль"
                        }
                        Item { Layout.fillWidth: true }
                        Button {
                            flat: true
                            text: "Забыли пароль?"
                            enabled: !authManager.isAuthenticating
                            onClicked: root.openEmailForm("restore")
                        }
                    }

                    Button {
                        id: loginBtn
                        Layout.fillWidth: true
                        Layout.preferredHeight: 44
                        text: (authManager && authManager.isAuthenticating) ? "Выполняется вход..." : "Войти"
                        enabled: (!authManager || !authManager.isAuthenticating) && loginInput.text.trim().length > 0 && passInput.text.length > 0
                        Material.background: "#cfbcff"
                        Material.foreground: "#381e72"
                        font.bold: true
                        onClicked: {
                            authManager.signIn(loginInput.text.trim(), passInput.text);
                        }
                    }
                }

                ColumnLayout {
                    id: phoneTab
                    spacing: 14

                    Text {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        text: "Подтвердите вход в Anixart на телефоне"
                        font.pixelSize: 13
                        color: "#cac4d0"
                    }

                    Image {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.preferredWidth: 180
                        Layout.preferredHeight: 180
                        visible: status === Image.Ready
                        source: authManager.qrImage
                        smooth: false
                        mipmap: false
                        Accessible.name: "QR-код для входа с телефона"
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 80
                        radius: 16
                        color: "#2b2930"
                        border.color: "#4f378b"
                        border.width: 1

                        ColumnLayout {
                            anchors.centerIn: parent
                            spacing: 4

                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                text: "PIN-КОД"
                                font.pixelSize: 11
                                font.bold: true
                                color: "#938f99"
                                font.letterSpacing: 1.5
                            }

                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                text: (authManager && authManager.qrPin.length > 0) ? authManager.qrPin : "••••"
                                font.pixelSize: 32
                                font.bold: true
                                font.letterSpacing: 6
                                color: "#cfbcff"
                            }
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                        text: (root.phoneProvider ? "Сначала войдите через " + root.phoneProvider + " в Anixart на телефоне. " : "")
                            + "Наведите камеру телефона на QR-код, откройте ссылку и введите этот PIN в Anixart."
                        font.pixelSize: 12
                        lineHeight: 1.3
                        color: "#938f99"
                    }

                    RowLayout {
                        Layout.alignment: Qt.AlignHCenter
                        spacing: 8

                        BusyIndicator {
                            Layout.preferredWidth: 20
                            Layout.preferredHeight: 20
                            running: authManager.qrPending
                            visible: running
                            Material.accent: "#cfbcff"
                        }

                        Text {
                            text: (authManager && authManager.qrStatus.length > 0) ? authManager.qrStatus : "Ожидание подтверждения..."
                            font.pixelSize: 12
                            color: "#cac4d0"
                        }
                    }

                    Button {
                        Layout.fillWidth: true
                        text: "Обновить код"
                        enabled: !authManager.qrPending || authManager.qrPin.length > 0
                        Material.background: "#2b2930"
                        Material.foreground: "#e6e1e5"
                        onClicked: authManager.startQrAuth()
                    }
                }
            }
        }

        ColumnLayout {
            visible: root.emailMode !== ""
            Layout.fillWidth: true
            spacing: 12

            RowLayout {
                Layout.fillWidth: true
                Button {
                    flat: true
                    icon.source: "qrc:/assets/icons/back.svg"
                    Accessible.name: "Назад"
                    enabled: !authManager.isAuthenticating
                    onClicked: {
                        root.resetEmailForm();
                        root.emailMode = "";
                        root.statusMessage = "";
                    }
                }
                Label {
                    Layout.fillWidth: true
                    text: root.verificationHash ? "Подтвердите почту"
                        : root.recovering ? "Восстановление пароля" : "Создание аккаунта"
                    font.pixelSize: 21
                    font.weight: Font.DemiBold
                }
            }

            Label {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                text: root.verificationHash ? "Введите код из письма."
                    : root.recovering ? "Укажите почту или никнейм и придумайте новый пароль."
                    : "Укажите никнейм и почту для подтверждения регистрации."
            }

            TextField {
                id: emailLogin
                Layout.fillWidth: true
                visible: !root.verificationHash
                enabled: !authManager.isAuthenticating
                placeholderText: root.recovering ? "Почта или никнейм" : "Никнейм"
                selectByMouse: true
            }
            TextField {
                id: emailAddress
                Layout.fillWidth: true
                visible: !root.verificationHash && !root.recovering
                enabled: !authManager.isAuthenticating
                placeholderText: "Почта"
                inputMethodHints: Qt.ImhEmailCharactersOnly
                selectByMouse: true
            }
            TextField {
                id: newPassword
                Layout.fillWidth: true
                visible: !root.verificationHash
                enabled: !authManager.isAuthenticating
                placeholderText: root.recovering ? "Новый пароль" : "Пароль"
                echoMode: TextInput.Password
            }
            TextField {
                id: repeatPassword
                Layout.fillWidth: true
                visible: !root.verificationHash
                enabled: !authManager.isAuthenticating
                placeholderText: "Повторите пароль"
                echoMode: TextInput.Password
            }
            TextField {
                id: verificationCode
                Layout.fillWidth: true
                visible: !!root.verificationHash
                enabled: !authManager.isAuthenticating
                Accessible.name: "Код из письма"
                horizontalAlignment: TextInput.AlignHCenter
                maximumLength: root.verificationLength
                validator: RegularExpressionValidator { regularExpression: /[0-9]*/ }
                inputMethodHints: Qt.ImhDigitsOnly
                onAccepted: if (confirmEmail.enabled) confirmEmail.clicked()
            }
            Label {
                Layout.fillWidth: true
                visible: root.statusMessage !== ""
                wrapMode: Text.Wrap
                color: root.isError ? "#ffb4ab" : "#cfbcff"
                text: root.statusMessage
            }
            RowLayout {
                Layout.fillWidth: true
                Button {
                    visible: !!root.verificationHash
                    flat: true
                    enabled: root.resendDelay === 0 && !authManager.isAuthenticating
                    text: root.resendDelay ? "Повторить через " + root.resendDelay + " с" : "Отправить код ещё раз"
                    onClicked: authManager.confirmEmailCode(root.recovering, emailLogin.text,
                        emailAddress.text, newPassword.text, root.verificationHash, "")
                }
                Item { Layout.fillWidth: true }
                Button {
                    id: confirmEmail
                    highlighted: true
                    text: root.verificationHash ? "Подтвердить" : "Получить код"
                    enabled: !authManager.isAuthenticating && (root.verificationHash
                        ? verificationCode.length === root.verificationLength
                        : emailLogin.text.trim() !== "" && (root.recovering || emailAddress.text.trim() !== "")
                            && newPassword.length > 0 && newPassword.text === repeatPassword.text)
                    onClicked: {
                        root.statusMessage = "";
                        if (root.verificationHash)
                            authManager.confirmEmailCode(root.recovering, emailLogin.text, emailAddress.text,
                                newPassword.text, root.verificationHash, verificationCode.text);
                        else
                            authManager.requestEmailCode(root.recovering, emailLogin.text, emailAddress.text, newPassword.text);
                    }
                }
            }
        }
    }
}
