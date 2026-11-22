import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Anixart 1.0

Flickable {
    id: root

    required property string section
    required property var entityId
    property bool ownProfile: false
    readonly property Flickable pullSurface: root
    readonly property bool refreshing: loading
    readonly property bool badges: section === "profileBadges"
    readonly property bool collections: section === "releaseCollections"
    readonly property bool ratings: section === "profileRatings"
    property bool loading: false
    property bool failed: false
    property bool hasMore: false
    property int page: 0
    property var rows: []
    property var groups: []
    property string selectionError: ""
    property var selectedBadgeId: 0
    property var pendingBadgeId: 0

    contentWidth: width
    contentHeight: content.implicitHeight + 48
    clip: true
    ScrollBar.vertical: AppScrollBar {}

    function load(number) {
        if (loading || !entityId) return;
        loading = true;
        failed = false;
        anixApi.fetchBrowseSection(section, number, entityId, authManager.token, "");
    }

    function refresh() { load(0); }

    Component.onCompleted: refresh()

    Connections {
        target: anixApi

        function onBrowseSectionLoaded(section, page, id, query, data) {
            if (section !== root.section || id !== root.entityId || !root.loading) return;

            root.loading = false;
            root.failed = data.code !== 0;
            if (root.failed) return;

            if (root.badges) {
                root.groups = data.sections || [];
                if ((data.recent || []).length > 0 && root.ownProfile)
                    root.groups = [{title: "Недавние", content: data.recent}].concat(root.groups);
                root.selectedBadgeId = data.profile?.badge?.id || 0;
            } else {
                const result = data.content || [];
                root.rows = page === 0 ? result : root.rows.concat(result);
                root.page = page;
                root.hasMore = result.length > 0 && root.rows.length < (data.total_count || 0);
            }
        }

        function onProfilePreferenceSaved(field, value, ok) {
            if (field !== "badge" || !root.pendingBadgeId || root.pendingBadgeId !== value) return;
            root.pendingBadgeId = 0;
            if (ok) root.selectedBadgeId = value;
            else root.selectionError = "Не удалось установить значок";
        }
    }

    ColumnLayout {
        id: content
        anchors.horizontalCenter: parent.horizontalCenter
        y: 22
        width: Math.min(root.width - 48, 820)
        spacing: 13

        RowLayout {
            Layout.fillWidth: true

            AppToolButton {
                icon.source: "qrc:/assets/icons/back.svg"
                Accessible.name: "Назад"
                ToolTip.text: Accessible.name
                ToolTip.visible: hovered
                onClicked: root.StackView.view.pop()
            }

            Label {
                text: root.badges ? (root.ownProfile ? "Установка значка" : "Значки")
                    : root.collections ? "В коллекциях" : root.ratings ? "Оценки" : "История смены никнейма"
                font.pixelSize: 23
                font.weight: Font.DemiBold
            }
        }

        BusyIndicator {
            Layout.alignment: Qt.AlignHCenter
            running: root.loading
        }

        Label {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: 38
            visible: root.failed || (!root.loading && (root.badges ? root.groups.length === 0 : root.rows.length === 0))
            text: root.failed ? "Не удалось загрузить данные"
                : root.badges ? "Значков пока нет" : root.collections ? "Коллекций пока нет" : root.ratings ? "Оценок пока нет" : "Изменений нет"
            color: "#c5b7d1"
        }

        Label {
            visible: !!root.selectionError
            text: root.selectionError
            color: "#ffb4ab"
        }

        Repeater {
            model: root.ratings ? [] : root.rows

            delegate: AppToolButton {
                required property var modelData
                Layout.fillWidth: true
                text: root.collections ? modelData.title || "Коллекция"
                    : (modelData.newLogin || modelData.new_login || "") + " · "
                        + Qt.formatDateTime(new Date(modelData.timestamp * 1000), "d MMM yyyy, hh:mm")
                enabled: root.collections
                onClicked: root.StackView.view.push("qrc:/qml/ReleaseGridPage.qml",
                    {mode: "collection", collectionId: modelData.id, heading: text})
            }
        }

        Flow {
            Layout.fillWidth: true
            spacing: 10

            Repeater {
                model: root.ratings ? root.rows : []

                delegate: AnimeCard {
                    required property var modelData
                    width: 132
                    height: 205
                    compact: true
                    releaseData: modelData.release || modelData
                    subtitle: "Оценка · " + (modelData.my_vote || modelData.vote || "—")
                    onClicked: window.openRelease(releaseData.id)
                }
            }
        }

        Repeater {
            model: root.groups

            delegate: ColumnLayout {
                id: group
                required property var modelData
                Layout.fillWidth: true

                Label {
                    Layout.topMargin: 8
                    text: group.modelData.title || "Значки"
                    font.pixelSize: 17
                    font.weight: Font.DemiBold
                }

                Flow {
                    Layout.fillWidth: true
                    spacing: 8

                    Repeater {
                        model: group.modelData.content || []

                        delegate: AppToolButton {
                            id: badge
                            required property var modelData
                            width: 100
                            height: 100
                            enabled: root.ownProfile && authManager.isLoggedIn && modelData.id > 0
                                && !root.pendingBadgeId && root.selectedBadgeId !== modelData.id
                            Accessible.name: modelData.name || "Значок"
                            ToolTip.text: modelData.description || Accessible.name
                            ToolTip.visible: hovered
                            contentItem: ColumnLayout {
                                Image {
                                    Layout.alignment: Qt.AlignHCenter
                                    Layout.preferredWidth: 42
                                    Layout.preferredHeight: 42
                                    source: badge.modelData.image_small_url || badge.modelData.image_url || ""
                                    fillMode: Image.PreserveAspectFit
                                    mipmap: true
                                    asynchronous: true
                                }
                                Label {
                                    Layout.fillWidth: true
                                    horizontalAlignment: Text.AlignHCenter
                                    text: badge.Accessible.name
                                    wrapMode: Text.Wrap
                                    maximumLineCount: 2
                                    elide: Text.ElideRight
                                }
                            }
                            background: Rectangle {
                                radius: 11
                                color: badge.hovered || root.selectedBadgeId === badge.modelData.id ? "#4f385f" : "#26202e"
                                border.color: root.selectedBadgeId === badge.modelData.id ? "#c9abe8" : "transparent"
                            }
                            onClicked: {
                                root.selectionError = "";
                                root.pendingBadgeId = modelData.id;
                                anixApi.saveProfilePreference("badge", modelData.id, authManager.token);
                            }
                        }
                    }
                }
            }
        }

        Button {
            visible: root.hasMore
            enabled: !root.loading
            text: "Показать ещё"
            onClicked: root.load(root.page + 1)
        }
    }
}
