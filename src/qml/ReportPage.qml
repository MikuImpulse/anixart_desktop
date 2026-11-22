import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ColumnLayout {
    id: root

    required property string section
    required property var entityId
    required property string subject
    property var reasons: []
    property bool loading: false
    property bool sending: false
    property bool sent: false
    property string errorMessage: ""

    function loadReasons() {
        errorMessage = "";
        loading = true;
        anixApi.fetchReportReasons(section, authManager.token);
    }

    Component.onCompleted: loadReasons()

    Connections {
        target: anixApi
        function onReportReasonsLoaded(section, reasons) {
            if (section !== root.section || !root.loading) return;
            root.loading = false;
            root.reasons = reasons;
            reason.currentIndex = -1;
            if (!reasons.length) root.errorMessage = "Не удалось загрузить причины жалобы.";
        }
        function onReportSubmitted(section, entityId, code) {
            if (section !== root.section || entityId !== root.entityId || !root.sending) return;
            root.sending = false;
            root.sent = code === 0;
            if (!root.sent) root.errorMessage = "Не удалось отправить жалобу" + (code > 0 ? " · код " + code : ".");
        }
    }

    RowLayout {
        Layout.fillWidth: true
        Layout.margins: 16

        AppToolButton {
            icon.source: "qrc:/assets/icons/back.svg"
            Accessible.name: "Назад"
            enabled: !root.sending
            onClicked: root.StackView.view.pop()
        }

        Label { text: "Пожаловаться"; font.pixelSize: 22; font.bold: true; Layout.fillWidth: true }
    }

    ScrollView {
        Layout.fillHeight: true
        Layout.fillWidth: true
        contentWidth: availableWidth

        ColumnLayout {
            width: Math.min(parent.width - 32, 660)
            x: (parent.width - width) / 2
            spacing: 12

            Label { text: "Объект жалобы"; color: "#c8bbd3" }
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: subjectLabel.implicitHeight + 24
                radius: 12
                color: "#211a2b"
                border.color: "#4a3a59"

                Label {
                    id: subjectLabel
                    anchors.fill: parent
                    anchors.margins: 12
                    text: root.subject
                    maximumLineCount: 5
                    elide: Text.ElideRight
                    textFormat: Text.PlainText
                    wrapMode: Text.Wrap
                }
            }

            ComboBox {
                id: reason
                objectName: "reportReason"
                Layout.fillWidth: true
                model: root.reasons
                textRole: "name"
                valueRole: "id"
                currentIndex: -1
                displayText: currentIndex < 0 ? "Причина жалобы" : currentText
                Accessible.name: "Причина жалобы"
                enabled: root.reasons.length > 0 && !root.sending && !root.sent
            }

            TextArea {
                id: description
                Layout.fillWidth: true
                Layout.preferredHeight: 135
                Accessible.name: "Опишите проблему (от 3 символов)"
                topInset: 0
                bottomInset: 0
                topPadding: 14
                bottomPadding: 14
                leftPadding: 14
                rightPadding: 14
                verticalAlignment: TextEdit.AlignTop
                wrapMode: Text.Wrap
                readOnly: root.sending || root.sent
                onTextChanged: {
                    if (length > 400) remove(400, length);
                }
                Label {
                    x: description.leftPadding
                    y: description.topPadding
                    width: Math.max(0, description.width - description.leftPadding - description.rightPadding)
                    text: description.Accessible.name
                    color: "#bcb1c9"
                    elide: Text.ElideRight
                    visible: !description.text && !description.preeditText
                }
                background: Rectangle {
                    radius: 12
                    color: "#211a2b"
                    border.color: description.activeFocus ? "#cfbcff" : "#4a3a59"
                }
            }

            RowLayout {
                Layout.fillWidth: true
                AppToolButton {
                    text: "Правила сообщества ↗"
                    onClicked: Qt.openUrlExternally("https://www.anixart-app.com/rules")
                }
                Item { Layout.fillWidth: true }
                Label { text: description.length + "/400"; color: "#c8bbd3" }
            }

            Label {
                Layout.fillWidth: true
                visible: root.sent || root.errorMessage.length > 0
                text: root.sent ? "Жалоба отправлена" : root.errorMessage
                color: root.sent ? "#8ae69c" : "#ffb4ab"
                wrapMode: Text.Wrap
            }

            RowLayout {
                Layout.fillWidth: true
                Button {
                    text: root.sent ? "Готово" : "Отмена"
                    enabled: !root.sending
                    onClicked: root.StackView.view.pop()
                }
                Item { Layout.fillWidth: true }
                Button {
                    visible: !root.loading && root.reasons.length === 0
                    text: "Повторить загрузку"
                    onClicked: root.loadReasons()
                }
                BusyIndicator { running: root.loading || root.sending; visible: running }
                Button {
                    visible: !root.sent
                    enabled: !root.sending && reason.currentIndex >= 0 && description.text.trim().length >= 3
                    text: "Отправить"
                    highlighted: true
                    onClicked: {
                        root.sending = true;
                        root.errorMessage = "";
                        anixApi.submitReport(root.section, root.entityId, reason.currentValue, description.text, authManager.token);
                    }
                }
            }
        }
    }
}
