import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Dialog {
    id: root

    property var criteria: ({})
    signal criteriaSelected(var criteria)
    readonly property var countries: ["Неважно", "Япония", "Китай", "Корея"]
    readonly property var categories: ["Неважно", "ТВ", "Фильмы", "OVA", "ONA", "Спецвыпуски"]
    readonly property var genres: ["авангард", "гурман", "драма", "комедия", "повседневность", "приключения",
        "романтика", "сверхъестественное", "спорт", "тайна", "триллер", "ужасы", "фантастика", "фэнтези", "экшен"]
    property var selectedGenres: []
    property bool excludesBookmarks: false

    anchors.centerIn: parent
    width: Math.min(parent.width - 40, 670)
    title: "Настроить мою вкладку"
    modal: true
    Overlay.modal: Rectangle { color: "#bb000000" }
    standardButtons: Dialog.Apply | Dialog.Reset | Dialog.Cancel

    function restore(data) {
        country.currentIndex = Math.max(0, countries.indexOf(data.country || ""));
        category.currentIndex = Math.max(0, data.category_id || 0);
        selectedGenres = data.genres || [];
        genreMode.currentIndex = [1, 0, 2].indexOf(data.genres_mode ?? 1);
        excludesBookmarks = (data.profile_list_exclusions || []).length > 0;
    }

    function applyCriteria() {
        const result = {};
        if (country.currentIndex > 0) result.country = country.currentText;
        if (category.currentIndex > 0) result.category_id = category.currentIndex;
        if (selectedGenres.length > 0) {
            result.genres = selectedGenres;
            result.genres_mode = [1, 0, 2][genreMode.currentIndex];
        }
        if (excludesBookmarks) result.profile_list_exclusions = [1, 2, 3, 4, 5];
        root.criteriaSelected(result);
        root.close();
    }

    onOpened: {
        restore(criteria);
        standardButton(Dialog.Apply).text = "Применить";
        standardButton(Dialog.Reset).text = "Сбросить";
        standardButton(Dialog.Cancel).text = "Отмена";
    }
    onApplied: applyCriteria()
    onReset: restore({})

    contentItem: ColumnLayout {
        spacing: 12

        Label {
            Layout.fillWidth: true
            text: "Фильтры сохраняются на этом устройстве."
            color: "#cabdd5"
            wrapMode: Text.Wrap
        }

        RowLayout {
            Layout.fillWidth: true

            ColumnLayout {
                Layout.fillWidth: true
                Label { text: "Страна" }
                ComboBox { id: country; Layout.fillWidth: true; model: root.countries }
            }
            ColumnLayout {
                Layout.fillWidth: true
                Label { text: "Категория" }
                ComboBox { id: category; Layout.fillWidth: true; model: root.categories }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Label { text: "Жанры" }
            ComboBox {
                id: genreMode
                Layout.fillWidth: true
                model: ["Хотя бы один", "Все выбранные", "Без выбранных"]
            }
        }

        Flow {
            id: genreChoices
            Layout.fillWidth: true
            Layout.preferredHeight: implicitHeight
            spacing: 4

            Repeater {
                model: root.genres
                delegate: CheckBox {
                    required property string modelData
                    text: modelData
                    checked: root.selectedGenres.includes(modelData)
                    onClicked: {
                        if (root.selectedGenres.includes(modelData)) {
                            root.selectedGenres = root.selectedGenres.filter(genre => genre !== modelData);
                        } else {
                            root.selectedGenres = root.selectedGenres.concat([modelData]);
                        }
                    }
                }
            }
        }

        CheckBox {
            text: "Исключить закладки"
            enabled: authManager.isLoggedIn
            checked: root.excludesBookmarks
            onClicked: root.excludesBookmarks = checked
        }
    }
}
