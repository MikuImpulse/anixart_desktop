import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Controls.Material 2.15
import QtQuick.Layouts 1.15
import Anixart 1.0

Flickable {
    id: root
    property var releaseId: 0
    property string releaseTitle: ""
    property string releasePoster: ""

    property var typesList: []
    property int selectedTypeIndex: 0
    readonly property var currentTypeId: typesList[selectedTypeIndex]?.id ?? 0
    property var sourcesList: []
    property var currentSourceId: 0
    property var episodesList: []

    property var pendingEpisodeTarget: null
    property int pendingWatchPosition: -1
    readonly property bool isResolvingStream: pendingEpisodeTarget !== null
    property string errorMessage: ""
    readonly property Flickable pullSurface: root
    readonly property bool refreshing: anixApi.isLoading

    function refresh() {
        if (root.isResolvingStream || !releaseId) return;
        if (currentTypeId > 0 && currentSourceId > 0) {
            anixApi.fetchEpisodes(releaseId, currentTypeId, currentSourceId, authManager.token);
        } else {
            anixApi.fetchEpisodeTypes(releaseId, authManager.token);
        }
    }

    contentWidth: width
    contentHeight: contentCol.implicitHeight + 60
    clip: true
    flickableDirection: Flickable.VerticalFlick

    ScrollBar.vertical: AppScrollBar {}

    function formatTime(ms) {
        if (ms <= 0) return "00:00";
        var totalSec = Math.floor(ms / 1000);
        var m = Math.floor(totalSec / 60);
        var s = totalSec % 60;
        return (m < 10 ? "0" + m : m) + ":" + (s < 10 ? "0" + s : s);
    }

    function openEpisode(episode, typeId, sourceId, replacePlayer) {
        if (root.isResolvingStream) return false;

        root.pendingEpisodeTarget = {
            typeId: typeId,
            sourceId: sourceId,
            position: episode.position,
            name: episode.name?.trim() || "Неизвестная серия",
            isLibria: root.sourcesList.some(source => source.id === sourceId && (source.name === "Liberty" || source.name === "Libria")),
            replacePlayer: replacePlayer
        };
        anixApi.fetchEpisodeTarget(root.releaseId, sourceId, episode.position);

        return true;
    }

    function openNextEpisode(playerPage) {
        if (playerPage.sourceId !== root.currentSourceId || playerPage.typeId !== root.currentTypeId) return false;

        const index = root.episodesList.findIndex(episode => episode.position === playerPage.currentPosition);
        if (index < 0 || index + 1 >= root.episodesList.length) return false;

        return root.openEpisode(root.episodesList[index + 1], playerPage.typeId, playerPage.sourceId, playerPage);
    }

    function failEpisode(reason) {
        const selection = root.pendingEpisodeTarget;
        root.pendingEpisodeTarget = null;
        const currentPage = root.StackView.view?.currentItem;
        if (!selection || !currentPage) return;

        if (selection.replacePlayer === currentPage) {
            currentPage.nextEpisodePending = false;
            currentPage.nextEpisodeError = reason;
        } else if (selection.replacePlayer === null && currentPage === root) {
            root.errorMessage = reason;
            errorPopup.open();
        }
    }

    function retryEpisode(reason, retryable) {
        if (retryable && root.pendingEpisodeTarget?.isLibria) {
            retryTarget.restart();
        } else {
            root.failEpisode(reason);
        }
    }

    Timer {
        id: retryTarget
        interval: 5000
        onTriggered: {
            const selection = root.pendingEpisodeTarget;
            if (!selection) return;
            const currentPage = root.StackView.view?.currentItem;
            if (currentPage && currentPage === (selection.replacePlayer ?? root)) {
                anixApi.fetchEpisodeTarget(root.releaseId, selection.sourceId, selection.position);
            } else {
                root.pendingEpisodeTarget = null;
            }
        }
    }

    Component.onCompleted: {
        if (root.releaseId) {
            anixApi.fetchEpisodeTypes(root.releaseId, authManager.token);
        }
    }

    Connections {
        target: anixApi
        function onNetworkRouteChanged() {
            resolver.resetConnections();
            if (retryTarget.running) retryTarget.restart();
        }
        function onEpisodeWatchUpdated(releaseId, typeId, sourceId, position, watched, playbackPosition) {
            if (releaseId === root.releaseId && typeId === root.currentTypeId && sourceId === root.currentSourceId && position === root.pendingWatchPosition) {
                root.pendingWatchPosition = -1;
            }
        }
        function onEpisodeWatchChangeFailed(releaseId, typeId, sourceId, position, watched) {
            if (releaseId !== root.releaseId || typeId !== root.currentTypeId || sourceId !== root.currentSourceId || position !== root.pendingWatchPosition) return;

            root.pendingWatchPosition = -1;
            root.errorMessage = watched ? "Не удалось поставить отметку о просмотре." : "Не удалось снять отметку о просмотре.";
            errorPopup.open();
        }
        function onEpisodeTypesLoaded(releaseId, types) {
            if (releaseId !== root.releaseId) return;

            root.typesList = types;
            if (types.length > 0) {
                root.selectedTypeIndex = 0;
                var t0 = types[0];
                anixApi.fetchEpisodeSources(root.releaseId, t0.id);
            }
        }
        function onEpisodeSourcesLoaded(releaseId, typeId, sources) {
            if (releaseId !== root.releaseId || typeId !== root.currentTypeId) return;

            root.sourcesList = sources;
            if (sources.length > 0) {
                root.currentSourceId = sources[0].id;
                var currentType = root.typesList[root.selectedTypeIndex];
                if (currentType) {
                    anixApi.fetchEpisodes(root.releaseId, currentType.id, root.currentSourceId, authManager.token);
                }
            } else {
                root.currentSourceId = 0;
                root.episodesList = [];
            }
        }
        function onEpisodesLoaded(releaseId, typeId, sourceId, episodes) {
            if (releaseId !== root.releaseId || typeId !== root.currentTypeId || sourceId !== root.currentSourceId) return;

            root.episodesList = episodes;
        }
        function onEpisodeTargetLoaded(releaseId, sourceId, position, target) {
            var selection = root.pendingEpisodeTarget;
            if (!selection || releaseId !== root.releaseId || sourceId !== selection.sourceId || position !== selection.position) return;

            if (target.url) {
                resolver.resolve(target.url);
            } else {
                root.retryEpisode("Ссылка на видео не найдена для этой серии.", target.retryable);
            }
        }
    }

    StreamResolver {
        id: resolver

        onStreamsReady: (streams, defaultStream) => {
            if (root.pendingEpisodeTarget) {
                var selection = root.pendingEpisodeTarget;
                root.pendingEpisodeTarget = null;

                var stack = root.StackView.view;
                if (!stack || stack.currentItem !== (selection.replacePlayer === null ? root : selection.replacePlayer)) return;

                var chosenQuality = ["720p", "1080p", "480p", "360p"].find(q => streams[q] === defaultStream) || "";
                var pref = window.defaultQuality;
                var orderHigh = ["1080p", "720p", "480p", "360p"];
                var orderLow = ["360p", "480p", "720p", "1080p"];

                if (pref === "Максимально доступное") {
                    for (var i = 0; i < orderHigh.length; ++i) {
                        if (streams && streams[orderHigh[i]]) {
                            chosenQuality = orderHigh[i];
                            break;
                        }
                    }
                } else if (pref === "Минимально доступное") {
                    for (var j = 0; j < orderLow.length; ++j) {
                        if (streams && streams[orderLow[j]]) {
                            chosenQuality = orderLow[j];
                            break;
                        }
                    }
                } else if (streams && streams[pref]) {
                    chosenQuality = pref;
                }

                const page = "qrc:/qml/PlayerPage.qml";
                const properties = {
                    releaseId: root.releaseId,
                    releaseTitle: root.releaseTitle,
                    episodeName: selection.name,
                    typeId: selection.typeId,
                    sourceId: selection.sourceId,
                    streamsMap: streams,
                    currentStreamUrl: streams[chosenQuality] || defaultStream,
                    selectedQuality: chosenQuality,
                    currentPosition: selection.position,
                    openNextEpisode: root.openNextEpisode
                };
                if (selection.replacePlayer === null) stack.push(page, properties);
                else stack.replace(page, properties);
            }
        }
        onResolveFailed: (reason, retryable) => {
            root.retryEpisode(reason || "Не удалось воспроизвести видео из этого источника.", retryable);
        }
    }

    ColumnLayout {
        id: contentCol
        width: Math.min(parent.width - 48, 1100)
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: 20
        spacing: 20

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

            ColumnLayout {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                spacing: 2
                Text {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    text: root.releaseTitle
                    font.pixelSize: 22
                    font.bold: true
                    color: "#ffffff"
                    elide: Text.ElideRight
                }
                Text {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    text: "Выбор озвучки, источника и серии"
                    font.pixelSize: 13
                    color: "#938f99"
                    elide: Text.ElideRight
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 10

            Text {
                text: "Озвучка / Перевод"
                font.pixelSize: 16
                font.bold: true
                color: "#e6e1e5"
            }

            Flickable {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                height: 48
                flickableDirection: Flickable.HorizontalFlick
                contentWidth: voiceRow.implicitWidth
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                RowLayout {
                    id: voiceRow
                    spacing: 10

                    Repeater {
                        model: root.typesList
                        delegate: Button {
                            id: voiceButton
                            readonly property bool isSelected: root.selectedTypeIndex === index
                            text: modelData.name + (modelData.episodes_count > 0 ? (" (" + modelData.episodes_count + ")") : "")
                            rightPadding: leftPadding + (voiceQuality.visible ? voiceQuality.width + 8 : 0)
                            enabled: !root.isResolvingStream && root.pendingWatchPosition < 0
                            checkable: true
                            checked: isSelected
                            Material.background: isSelected ? "#4f378b" : "#1d192b"
                            Material.foreground: isSelected ? "#ffffff" : "#cac4d0"
                            font.bold: isSelected

                            QualityBadge {
                                id: voiceQuality
                                visible: modelData.quality === 1
                                anchors.right: parent.right
                                anchors.rightMargin: voiceButton.leftPadding
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            onClicked: {
                                if (root.selectedTypeIndex !== index) {
                                    root.selectedTypeIndex = index;
                                    root.currentSourceId = 0;
                                    root.sourcesList = [];
                                    root.episodesList = [];
                                    anixApi.fetchEpisodeSources(root.releaseId, modelData.id);
                                }
                            }
                        }
                    }
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 10
            visible: root.sourcesList.length > 0

            Text {
                text: "Источник"
                font.pixelSize: 16
                font.bold: true
                color: "#cfbcff"
            }

            Flickable {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                height: 44
                flickableDirection: Flickable.HorizontalFlick
                contentWidth: sourcesRow.implicitWidth
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                RowLayout {
                    id: sourcesRow
                    spacing: 10

                    Repeater {
                        model: root.sourcesList
                        delegate: Rectangle {
                            readonly property bool isSelected: root.currentSourceId === modelData.id
                            implicitWidth: sourceLabel.implicitWidth + 28
                            implicitHeight: 38
                            radius: 19
                            color: isSelected ? "#4f378b" : (srcMouse.containsMouse ? "#2f2c38" : "#232128")
                            border.color: isSelected ? "#cfbcff" : (srcMouse.containsMouse ? "#4f378b" : "#36343b")
                            border.width: isSelected ? 2 : 1

                            Behavior on color { ColorAnimation { duration: 150 } }

                            Row {
                                id: sourceLabel
                                anchors.centerIn: parent
                                spacing: 8

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: modelData.name + (modelData.episodes_count > 0 ? (" • " + modelData.episodes_count + " эп.") : "")
                                    font.pixelSize: 13
                                    font.bold: isSelected
                                    color: isSelected ? "#ffffff" : "#cac4d0"
                                }

                                QualityBadge {
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: modelData.quality === 1
                                }
                            }

                            MouseArea {
                                id: srcMouse
                                enabled: !root.isResolvingStream && root.pendingWatchPosition < 0
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (root.currentSourceId !== modelData.id) {
                                        root.currentSourceId = modelData.id;
                                        root.episodesList = [];
                                        var currentType = root.typesList[root.selectedTypeIndex];
                                        if (currentType) {
                                            anixApi.fetchEpisodes(root.releaseId, currentType.id, root.currentSourceId, authManager.token);
                                        }
                                    }
                                }
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

        RowLayout {
            Layout.fillWidth: true

            Text {
                text: "Серии (" + root.episodesList.length + ")"
                font.pixelSize: 18
                font.bold: true
                color: "#e6e1e5"
            }

            Item { Layout.fillWidth: true }

            Label {
                visible: root.isResolvingStream
                text: retryTarget.running ? "Повторное подключение…" : "Открываем серию…"
            }

            Button {
                visible: retryTarget.running && root.pendingEpisodeTarget?.replacePlayer === null
                text: "Отменить"
                onClicked: {
                    retryTarget.stop();
                    root.pendingEpisodeTarget = null;
                }
            }

            BusyIndicator {
                Layout.preferredWidth: 24
                Layout.preferredHeight: 24
                running: root.isResolvingStream
                visible: root.isResolvingStream
                Material.accent: "#cfbcff"
            }
        }

        Column {
            id: episodesCol
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            spacing: 0

            Repeater {
                model: root.episodesList
                delegate: Rectangle {
                    id: episodeRow
                    width: episodesCol.width
                    height: 58
                    radius: 10
                    color: epMouse.containsMouse ? "#232128" : "transparent"

                    Behavior on color { ColorAnimation { duration: 120 } }

                    property var watchUpdate: null
                    readonly property string watchKey: [root.releaseId, root.currentTypeId, root.currentSourceId, modelData.position].join("/")
                    readonly property bool hasWatchUpdate: watchUpdate !== null && watchUpdate.key === watchKey
                    readonly property bool isWatched: hasWatchUpdate ? watchUpdate.watched
                        : (modelData.is_watched || anixApi.isEpisodeWatched(root.releaseId, root.currentTypeId, root.currentSourceId, modelData.position))
                    readonly property real playbackPos: hasWatchUpdate ? watchUpdate.playbackPosition
                        : anixApi.getEpisodePlaybackPosition(root.releaseId, root.currentTypeId, root.currentSourceId, modelData.position)

                    Connections {
                        target: anixApi
                        function onEpisodeWatchUpdated(releaseId, typeId, sourceId, position, watched, playbackPosition) {
                            if (releaseId === root.releaseId && typeId === root.currentTypeId && sourceId === root.currentSourceId && position === modelData.position) {
                                episodeRow.watchUpdate = {key: episodeRow.watchKey, watched: watched, playbackPosition: playbackPosition};
                            }
                        }
                    }

                    readonly property string epTitle: {
                        if (modelData.name && modelData.name.trim().length > 0) {
                            return modelData.name.trim();
                        }
                        return "Неизвестная серия";
                    }

                    readonly property string epSubtitle: {
                        var text = "";
                        if (modelData.is_filler) {
                            text = "Филлер";
                        }
                        if (playbackPos > 1000) {
                            var statusText = "Просмотрено до " + formatTime(playbackPos);
                            text = text.length > 0 ? (text + " • " + statusText) : statusText;
                        } else if (playbackPos === -1) {
                            var statusText = "Просмотрено целиком";
                            text = text.length > 0 ? (text + " • " + statusText) : statusText;
                        }
                        return text;
                    }

                    RowLayout {
                        anchors.left: parent.left
                        anchors.right: episodeQuality.visible ? episodeQuality.left : watchedIcon.left
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: 16
                        anchors.rightMargin: 12

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 3

                            Text {
                                Layout.fillWidth: true
                                text: epTitle
                                font.pixelSize: 15
                                font.weight: Font.Medium
                                color: "#ffffff"
                                elide: Text.ElideRight
                            }

                            Text {
                                Layout.fillWidth: true
                                visible: epSubtitle.length > 0
                                text: epSubtitle
                                font.pixelSize: 13
                                color: "#938f99"
                                elide: Text.ElideRight
                            }
                        }
                    }

                    QualityBadge {
                        id: episodeQuality
                        visible: modelData.quality === 1
                        anchors.right: watchedIcon.left
                        anchors.rightMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Image {
                        id: watchedIcon
                        visible: episodeRow.isWatched
                        anchors.right: parent.right
                        anchors.rightMargin: 16
                        anchors.verticalCenter: parent.verticalCenter
                        width: 22
                        height: 22
                        source: "qrc:/assets/icons/check_circle.svg"
                        sourceSize: Qt.size(22, 22)
                        smooth: true
                    }

                    MouseArea {
                        id: epMouse
                        property bool held: false

                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        cursorShape: Qt.PointingHandCursor
                        enabled: !root.isResolvingStream && root.pendingWatchPosition < 0
                        pressAndHoldInterval: 500
                        onPressed: held = false
                        function toggleWatched() {
                            held = true;
                            root.pendingWatchPosition = modelData.position;
                            anixApi.setEpisodeWatched(root.releaseId, root.currentTypeId, root.currentSourceId, modelData.position, !episodeRow.isWatched, authManager.token);
                        }
                        onPressAndHold: mouse => {
                            if (mouse.button === Qt.LeftButton) toggleWatched();
                            else mouse.accepted = false;
                        }
                        onClicked: mouse => {
                            if (held) return;
                            if (mouse.button === Qt.RightButton) toggleWatched();
                            else root.openEpisode(modelData, root.currentTypeId, root.currentSourceId, null);
                        }
                    }
                }
            }
        }

        Item { Layout.preferredHeight: 40 }
    }

    component QualityBadge: Rectangle {
        implicitWidth: qualityLabel.implicitWidth + 12
        implicitHeight: 20
        radius: 5
        color: "#29243c"

        Text {
            id: qualityLabel
            anchors.centerIn: parent
            text: "1080p"
            font.pixelSize: 11
            font.weight: Font.DemiBold
            color: "#ded2f7"
        }
    }

    Dialog {
        id: errorPopup
        anchors.centerIn: parent
        width: Math.min(420, parent.width - 40)
        modal: true
        Material.theme: Material.Dark
        Material.background: "#1d192b"

        Overlay.modal: Rectangle {
            color: "#b3000000"
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 14

            Text {
                text: "Видео недоступно"
                font.pixelSize: 18
                font.bold: true
                color: "#ffb4ab"
            }

            Text {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                text: root.errorMessage
                font.pixelSize: 14
                lineHeight: 1.3
                color: "#cac4d0"
            }

            Button {
                Layout.alignment: Qt.AlignRight
                text: "Понятно"
                Material.background: "#cfbcff"
                Material.foreground: "#381e72"
                font.bold: true
                onClicked: errorPopup.close()
            }
        }
    }
}
