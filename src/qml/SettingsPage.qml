import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Controls.Material 2.15
import QtQuick.Layouts 1.15

Item {
    id: root
    readonly property Flickable pullSurface: settingsScroll.contentItem

    function refresh() { window.syncPlaybackSettings(); }

    ScrollView {
        id: settingsScroll
        anchors.fill: parent
        contentWidth: availableWidth
        contentHeight: contentCol.implicitHeight + topPadding + bottomPadding + 40
        clip: true
        topPadding: 32
        bottomPadding: 36
        leftPadding: 24
        rightPadding: 24

        ScrollBar.vertical: AppScrollBar {}

        ColumnLayout {
            id: contentCol
            width: Math.min(parent.width - 48, 800)
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 24

            RowLayout {
                Layout.fillWidth: true
                spacing: 16

                Rectangle {
                    width: 48
                    height: 48
                    radius: 24
                    color: "#2b2930"

                    Image {
                        anchors.centerIn: parent
                        width: 24
                        height: 24
                        source: "qrc:/assets/icons/settings.svg"
                        sourceSize: Qt.size(24, 24)
                    }
                }

                ColumnLayout {
                    spacing: 2
                    Text {
                        text: "Настройки"
                        font.pixelSize: 26
                        font.bold: true
                        color: "#e6e1e5"
                    }
                    Text {
                        text: "Параметры воспроизведения, интерфейса и учетной записи"
                        font.pixelSize: 13
                        color: "#938f99"
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: "#2b2930"
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 16

                Text {
                    text: "ВОСПРОИЗВЕДЕНИЕ"
                    font.pixelSize: 12
                    font.bold: true
                    color: "#cfbcff"
                    font.letterSpacing: 1.2
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 80
                    Layout.preferredHeight: 80
                    radius: 12
                    color: "#1c1b1f"

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 20
                        anchors.rightMargin: 20
                        spacing: 16

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 4

                            Text {
                                text: "Длительность пропуска опенинга"
                                font.pixelSize: 15
                                font.weight: Font.Medium
                                color: "#e6e1e5"
                            }
                            Text {
                                text: {
                                    var mins = Math.floor(window.skipOpeningDurationSec / 60);
                                    var secs = window.skipOpeningDurationSec % 60;
                                    if (mins > 0 && secs > 0) return mins + " мин " + secs + " сек";
                                    if (mins > 0) return mins + " мин";
                                    return secs + " сек";
                                }
                                font.pixelSize: 12
                                color: "#cac4d0"
                            }
                        }

                        Slider {
                            Layout.preferredWidth: 200
                            Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                            from: 30
                            to: 120
                            stepSize: 5
                            value: window.skipOpeningDurationSec
                            Material.accent: "#cfbcff"
                            onMoved: {
                                window.skipOpeningDurationSec = Math.round(value);
                            }
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 72
                    Layout.preferredHeight: 72
                    radius: 12
                    color: "#1c1b1f"

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 20
                        anchors.rightMargin: 20
                        spacing: 16

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 4

                            Text {
                                text: "Шаг перемотки кнопками и стрелками"
                                font.pixelSize: 15
                                font.weight: Font.Medium
                                color: "#e6e1e5"
                            }
                            Text {
                                text: "Стрелки влево / вправо на клавиатуре и кнопки ↺ ↻"
                                font.pixelSize: 12
                                color: "#938f99"
                            }
                        }

                        ComboBox {
                            Layout.preferredWidth: 200
                            Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                            model: ["5 сек", "10 сек", "15 сек", "30 сек"]
                            currentIndex: window.seekStepSec === 5 ? 0 : (window.seekStepSec === 15 ? 2 : (window.seekStepSec === 30 ? 3 : 1))
                            onActivated: {
                                if (index === 0) window.seekStepSec = 5;
                                else if (index === 1) window.seekStepSec = 10;
                                else if (index === 2) window.seekStepSec = 15;
                                else if (index === 3) window.seekStepSec = 30;
                            }
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 72
                    Layout.preferredHeight: 72
                    radius: 12
                    color: "#1c1b1f"

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 20
                        anchors.rightMargin: 20
                        spacing: 16

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 4

                            Text {
                                text: "Качество видео во встроенном плеере"
                                font.pixelSize: 15
                                font.weight: Font.Medium
                                color: "#e6e1e5"
                            }
                            Text {
                                text: "При наличии выбирается автоматически"
                                font.pixelSize: 12
                                color: "#938f99"
                            }
                        }

                        ComboBox {
                            Layout.preferredWidth: 200
                            Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                            model: ["Максимально доступное", "1080p", "720p", "480p", "360p", "Минимально доступное"]
                            currentIndex: {
                                var idx = model.indexOf(window.defaultQuality);
                                return idx >= 0 ? idx : 0;
                            }
                            Material.accent: "#cfbcff"
                            onActivated: {
                                window.defaultQuality = currentText;
                            }
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 72
                    Layout.preferredHeight: 72
                    radius: 12
                    color: "#1c1b1f"

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 20
                        anchors.rightMargin: 20
                        spacing: 16

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 4

                            Text {
                                text: "Автоматический переход к следующей серии"
                                font.pixelSize: 15
                                font.weight: Font.Medium
                                color: "#e6e1e5"
                            }
                            Text {
                                text: "Включать следующий эпизод после завершения текущего"
                                font.pixelSize: 12
                                color: "#938f99"
                            }
                        }

                        Item {
                            Layout.preferredWidth: 200
                            Layout.preferredHeight: 32
                            Layout.alignment: Qt.AlignRight | Qt.AlignVCenter

                            Switch {
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                checked: window.autoPlayNext
                                Material.accent: "#cfbcff"
                                onToggled: {
                                    window.autoPlayNext = checked;
                                }
                            }
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: "#2b2930"
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 16

                Text {
                    text: "О ПРИЛОЖЕНИИ"
                    font.pixelSize: 12
                    font.bold: true
                    color: "#cfbcff"
                    font.letterSpacing: 1.2
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 80
                    Layout.preferredHeight: 80
                    radius: 12
                    color: "#1c1b1f"

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 20
                        anchors.rightMargin: 20
                        spacing: 16

                        Item {
                            Layout.preferredWidth: 44
                            Layout.preferredHeight: 44
                            width: 44
                            height: 44
                            clip: true

                            Image {
                                anchors.fill: parent
                                sourceSize: Qt.size(44, 44)
                                source: "qrc:/assets/anixart_app.png"
                                fillMode: Image.PreserveAspectFit
                                smooth: true
                                mipmap: true
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 4

                            Text {
                                text: "Anixart"
                                font.pixelSize: 16
                                font.bold: true
                                color: "#e6e1e5"
                            }
                            Text {
                                text: "Версия 11 BETA 3 • Сборка 26111702 • Hardware Accelerated"
                                font.pixelSize: 12
                                color: "#938f99"
                            }
                        }
                    }
                }

                Item { Layout.preferredHeight: 24 }
            }
        }
    }
}
