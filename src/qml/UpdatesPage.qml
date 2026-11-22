import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import Anixart 1.0

Item {
    id: root

    readonly property var dayKeys: ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]
    readonly property var dayLabels: ["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"]
    property int selectedDay: (new Date().getDay() + 6) % 7
    property var schedule: ({})
    property bool loading: false
    property bool failed: false
    readonly property Flickable pullSurface: updates
    readonly property bool refreshing: loading

    function refresh() { reload(); }

    Component.onCompleted: reload()

    function reload() {
        if (loading) return;
        loading = true;
        failed = false;
        anixApi.fetchBrowseSection("schedule");
    }

    Connections {
        target: anixApi
        function onBrowseSectionLoaded(section, page, collectionId, query, data) {
            if (section !== "schedule") return;

            root.loading = false;
            root.failed = data.code !== 0;
            if (!root.failed) root.schedule = data;
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 24
        spacing: 16

        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            Button { text: "Назад"; onClicked: root.StackView.view.pop() }

            Label {
                text: "Расписание"
                font.pixelSize: 29
                font.weight: Font.DemiBold
                color: "#f0e9f8"
            }
            Item { Layout.fillWidth: true }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Label {
                text: "Расписание релизов"
                font.pixelSize: 17
                color: "#e2d8ed"
                Layout.rightMargin: 12
            }
            Repeater {
                model: root.dayLabels
                delegate: Button {
                    required property int index
                    required property string modelData
                    Layout.preferredWidth: 48
                    text: modelData
                    highlighted: index === root.selectedDay
                    onClicked: {
                        root.selectedDay = index;
                        updates.positionViewAtBeginning();
                    }
                }
            }
            Item { Layout.fillWidth: true }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            BusyIndicator { anchors.centerIn: parent; running: root.loading && updates.count === 0 }

            Label {
                anchors.centerIn: parent
                visible: !root.loading && updates.count === 0
                text: root.failed ? "Не удалось загрузить расписание" : "На этот день релизов нет"
                color: "#cac0d5"
            }

            GridView {
                id: updates
                anchors.fill: parent
                clip: true
                model: root.schedule[root.dayKeys[root.selectedDay]] || []
                readonly property int columns: Math.max(2, Math.floor(width / 365))
                cellWidth: width / columns
                cellHeight: 166
                ScrollBar.vertical: AppScrollBar {}

                delegate: Item {
                    id: tile
                    required property var modelData
                    width: updates.cellWidth
                    height: updates.cellHeight

                    AppToolButton {
                        id: releaseButton
                        anchors.fill: parent
                        anchors.rightMargin: 12
                        anchors.bottomMargin: 12
                        Accessible.name: tile.modelData.title_ru || tile.modelData.title_original || ""
                        HoverHandler { cursorShape: Qt.PointingHandCursor }
                        onClicked: window.openRelease(tile.modelData.id)

                        background: Rectangle {
                            color: releaseButton.hovered || releaseButton.activeFocus ? "#302440" : "#211a2d"
                            border.color: releaseButton.hovered ? "#786395" : "#3a2e4a"
                            radius: 12
                            Behavior on color { ColorAnimation { duration: 150 } }
                        }

                        contentItem: RowLayout {
                            spacing: 13

                            CircleImage {
                                Layout.preferredWidth: 86
                                Layout.fillHeight: true
                                source: tile.modelData.image || ""
                                cornerRadius: 8
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignVCenter
                                spacing: 6

                                Label {
                                    Layout.fillWidth: true
                                    text: releaseButton.Accessible.name
                                    color: "#f0e9f8"
                                    font.pixelSize: 16
                                    font.weight: Font.DemiBold
                                    wrapMode: Text.Wrap
                                    maximumLineCount: 2
                                    elide: Text.ElideRight
                                }
                                Label {
                                    Layout.fillWidth: true
                                    text: (tile.modelData.episodes_released || 0) + " из " + (tile.modelData.episodes_total || "?") + " эп."
                                    color: "#cfbcff"
                                    elide: Text.ElideRight
                                }
                                Label {
                                    Layout.fillWidth: true
                                    text: tile.modelData.genres || ""
                                    color: "#b7adc4"
                                    wrapMode: Text.Wrap
                                    maximumLineCount: 2
                                    elide: Text.ElideRight
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
