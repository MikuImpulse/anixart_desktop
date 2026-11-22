import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Controls.Material 2.15
import QtQuick.Layouts 1.15
import Anixart 1.0

Item {
    id: root
    objectName: "playerPage"

    property var releaseId: 0
    property var typeId: 0
    property var sourceId: 0
    property string releaseTitle: ""
    property string episodeName: ""
    property var streamsMap: ({})
    property string currentStreamUrl: ""
    property string selectedQuality: ""
    property real startupPosition: 0
    property bool playbackWanted: false
    property bool reconnecting: false
    property bool refreshAfterRouteChange: false
    property int currentPosition: 1
    property var openNextEpisode: null
    property bool nextEpisodePending: false
    property string nextEpisodeError: ""

    property bool showControls: true
    property bool showSeekIndicator: false
    property bool playbackFinished: false
    property bool hasSavedCheckpoint: false
    property string playbackError: ""
    property real resumePosition: 0
    readonly property var qualities: ["360p", "480p", "720p", "1080p"].filter(q => root.streamsMap[q])
    readonly property bool isNetworkSource: /^https?:\/\//i.test(player.source)
    readonly property bool isLoading: reconnecting || (player.source.length > 0 && !playbackError && (!player.isReady || player.isBuffering))
    readonly property int controlsMargin: Math.max(20, Math.min(48, width * 0.032))
    readonly property real timelinePosition: player.seekPosition >= 0 ? player.seekPosition : player.position
    readonly property real displayedPosition: isGestureScrubbing ? scrubTargetPosition
                                              : (timeSlider.pressed ? timeSlider.dragPosition : timelinePosition)

    property bool isGestureScrubbing: false
    property real scrubStartX: 0
    property real scrubStartY: 0
    property real scrubStartPosition: 0
    property real scrubTargetPosition: 0

    focus: true
    Keys.priority: Keys.BeforeItem

    Component.onCompleted: {
        forceActiveFocus();
        if (root.releaseId > 0) {
            root.resumePosition = anixApi.getEpisodePlaybackPosition(root.releaseId, root.typeId, root.sourceId, root.currentPosition);
        }
        if (root.resumePosition > 1000) {
            resumeDialog.open();
        } else {
            root.startPlayback(0);
        }
    }

    function startPlayback(position) {
        if (!root.currentStreamUrl) return;

        root.loadStream(root.currentStreamUrl, position, true);
        anixApi.recordEpisodeOpened(root.releaseId, root.typeId, root.sourceId, root.currentPosition, authManager.token);
        root.forceActiveFocus();
    }

    function loadStream(url, position, autoplay, preserveFrame = false) {
        root.startupPosition = position;
        root.playbackWanted = autoplay;
        root.playbackError = "";
        player.load(url, position, autoplay, preserveFrame);
    }

    function reconnect(delay) {
        if (!root.isNetworkSource || root.playbackFinished || root.nextEpisodePending) return;

        if (!root.reconnecting) {
            root.startupPosition = player.seekPosition >= 0 ? player.seekPosition : Math.max(player.position, root.startupPosition);
            root.reconnecting = true;
        }
        root.playbackError = "";
        reconnectDelay.interval = delay;
        reconnectDelay.restart();
    }

    function reconnectFailed(message, retryable) {
        if (root.isNetworkSource && retryable) {
            if (root.playbackWanted) root.reconnect(5000);
        } else {
            root.reconnecting = false;
            root.playbackError = message;
            root.showControls = true;
        }
    }

    function closePlayer() {
        const stack = root.StackView.view;
        if (!stack || stack.currentItem !== root) return;

        root.saveWatchProgress();
        player.stop();
        if (window.visibility === Window.FullScreen) window.toggleWindowFullscreen();
        stack.pop();
    }

    function togglePlayback() {
        if (root.nextEpisodePending) return;

        root.nextEpisodeError = "";
        if (root.reconnecting) {
            root.playbackWanted = !root.playbackWanted;
            if (root.playbackWanted) reconnectDelay.restart();
            else reconnectDelay.stop();
        } else if (root.playbackError && player.source) {
            root.playbackWanted = true;
            if (root.isNetworkSource) root.reconnect(0);
            else root.loadStream(player.source, Math.max(player.position, root.startupPosition), true);
        } else {
            player.togglePlay();
            root.playbackWanted = player.isPlaying;
        }
    }

    function togglePlaybackWithFeedback() {
        if (!player.source || root.nextEpisodePending) return;

        root.togglePlayback();
        playbackFeedbackIcon.source = root.playbackWanted ? "qrc:/assets/icons/play.svg" : "qrc:/assets/icons/pause.svg";
        playbackFeedbackAnimation.restart();
        root.resetControlsTimer();
    }

    Timer {
        id: reconnectDelay
        onTriggered: {
            if (root.StackView.view?.currentItem !== root || reconnectResolver.isResolving || root.refreshingTarget) return;
            root.refreshAfterRouteChange = false;
            if (root.releaseId > 0 && root.sourceId > 0) {
                root.refreshingTarget = true;
                anixApi.fetchEpisodeTarget(root.releaseId, root.sourceId, root.currentPosition);
            } else {
                root.reconnecting = false;
                root.loadStream(player.source, root.startupPosition, root.playbackWanted, true);
            }
        }
    }

    property bool refreshingTarget: false

    StreamResolver {
        id: reconnectResolver
        onStreamsReady: (streams, defaultStream) => {
            if (!root.reconnecting || root.StackView.view?.currentItem !== root) return;
            if (root.refreshAfterRouteChange) {
                root.reconnect(0);
                return;
            }

            const url = root.selectedQuality ? streams[root.selectedQuality] : defaultStream;
            if (!url) {
                root.reconnectFailed("Выбранное качество пока недоступно.", true);
                return;
            }
            root.streamsMap = streams;
            root.reconnecting = false;
            root.loadStream(url, root.startupPosition, root.playbackWanted, true);
        }
        onResolveFailed: (message, retryable) => {
            if (root.refreshAfterRouteChange && root.reconnecting) root.reconnect(0);
            else if (root.reconnecting) root.reconnectFailed(message, retryable);
        }
    }

    Component.onDestruction: {
        saveWatchProgress();
    }

    function saveWatchProgress() {
        if (!anixApi || root.releaseId <= 0 || !player.isReady || player.seekPosition >= 0) return;
        if (!root.playbackFinished && player.position <= 1000) return;

        anixApi.saveEpisodeProgress(root.releaseId, root.typeId, root.sourceId, root.currentPosition,
                                    root.playbackFinished ? -1 : player.position, player.duration);
        root.hasSavedCheckpoint = true;
    }

    Timer {
        interval: 5000
        repeat: true
        running: player.isPlaying
        onTriggered: root.saveWatchProgress()
    }

    Connections {
        target: anixApi
        function onNetworkRouteChanged() {
            reconnectResolver.resetConnections();
            root.refreshAfterRouteChange = root.refreshingTarget || reconnectResolver.isResolving;
            if (root.StackView.view?.currentItem === root && root.playbackWanted && root.reconnecting) root.reconnect(0);
        }
        function onEpisodeTargetLoaded(releaseId, sourceId, position, target) {
            if (!root.refreshingTarget || releaseId !== root.releaseId || sourceId !== root.sourceId || position !== root.currentPosition) return;

            root.refreshingTarget = false;
            if (!root.reconnecting || root.StackView.view?.currentItem !== root) return;
            if (root.refreshAfterRouteChange) root.reconnect(0);
            else if (target.url) reconnectResolver.resolve(target.url);
            else root.reconnectFailed("Не удалось обновить ссылку на серию.", target.retryable);
        }
        function onFlushPlaybackProgress() {
            root.saveWatchProgress();
        }
    }

    Keys.onLeftPressed: (event) => {
        var step = (window.seekStepSec > 0 ? window.seekStepSec : 10) * 1000;
        player.skip(-step);
        resetControlsTimer();
        event.accepted = true;
    }
    Keys.onRightPressed: (event) => {
        var step = (window.seekStepSec > 0 ? window.seekStepSec : 10) * 1000;
        player.skip(step);
        resetControlsTimer();
        event.accepted = true;
    }
    Keys.onUpPressed: (event) => {
        player.setVolume(Math.min(1.0, player.volume + 0.05));
        resetControlsTimer();
        event.accepted = true;
    }
    Keys.onDownPressed: (event) => {
        player.setVolume(Math.max(0.0, player.volume - 0.05));
        resetControlsTimer();
        event.accepted = true;
    }
    Keys.onSpacePressed: (event) => {
        if (!event.isAutoRepeat) root.togglePlaybackWithFeedback();
        event.accepted = true;
    }
    Keys.onBackPressed: root.closePlayer()
    Keys.onEscapePressed: {
        if (window.visibility === Window.FullScreen) {
            window.toggleWindowFullscreen();
        } else {
            root.closePlayer();
        }
    }
    Keys.onPressed: (event) => {
        if (event.key === Qt.Key_F || event.key === Qt.Key_F11) {
            toggleFullScreen();
            event.accepted = true;
        } else if (event.key === Qt.Key_S) {
            skipOpening();
            event.accepted = true;
        } else if (event.key === Qt.Key_M) {
            toggleMute();
            event.accepted = true;
        }
    }

    function toggleFullScreen() {
        window.toggleWindowFullscreen();
    }

    function skipOpening() {
        player.skip(window.skipOpeningDurationSec * 1000);
    }

    function toggleMute() {
        if (player.volume > 0.01) {
            player.setVolume(0.0);
        } else {
            player.setVolume(window.audibleVolume > 0.01 ? window.audibleVolume : 1.0);
        }
    }

    Timer {
        id: hideControlsTimer
        interval: 3500
        repeat: false
        running: root.showControls && player.isPlaying && !root.isLoading && !gestureArea.pressed
                 && !timeSlider.pressed && !volumeSlider.pressed && !qualityMenu.opened
        onTriggered: {
            root.showControls = false;
        }
    }

    function resetControlsTimer() {
        root.showControls = true;
        if (hideControlsTimer.running) {
            hideControlsTimer.restart();
        }
    }

    function formatTime(ms) {
        if (!ms || ms < 0) return "00:00";
        var totalSec = Math.floor(ms / 1000);
        var min = Math.floor(totalSec / 60);
        var sec = totalSec % 60;
        var minStr = (min < 10 ? "0" : "") + min;
        var secStr = (sec < 10 ? "0" : "") + sec;
        return minStr + ":" + secStr;
    }

    Rectangle {
        anchors.fill: parent
        color: "#000000"

        VideoPlayer {
            id: player
            anchors.fill: parent
            volume: window.playbackVolume

            onSeekPositionChanged: {
                if (player.seekPosition < 0) {
                    root.showSeekIndicator = false;
                } else {
                    root.playbackFinished = false;
                }
            }
            onPositionChanged: {
                if (root.startupPosition > 0 && player.isReady && player.seekPosition < 0 && player.position > root.startupPosition + 250) {
                    root.startupPosition = 0;
                }
                if (!root.hasSavedCheckpoint) root.saveWatchProgress();
            }
            onVolumeChanged: {
                window.playbackVolume = player.volume;
                if (player.volume > 0.01) window.audibleVolume = player.volume;
            }

            onPlayingChanged: {
                if (player.isPlaying) {
                    root.playbackError = "";
                } else {
                    root.saveWatchProgress();
                }
            }
            onErrorOccurred: (message, retryable) => {
                if (root.isNetworkSource && root.playbackWanted && retryable) {
                    root.reconnect(3000);
                    return;
                }
                root.playbackError = message;
                root.showControls = true;
                hideControlsTimer.stop();
            }
            onEndOfStream: {
                root.playbackFinished = true;
                root.saveWatchProgress();
                if (window.autoPlayNext && root.openNextEpisode) {
                    root.nextEpisodePending = root.openNextEpisode(root);
                }
                if (!root.nextEpisodePending) Qt.callLater(root.closePlayer);
            }
        }

        MouseArea {
            id: gestureArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: root.showControls ? Qt.ArrowCursor : Qt.BlankCursor

            onPressed: (mouse) => {
                root.scrubStartX = mouse.x;
                root.scrubStartY = mouse.y;
                root.scrubStartPosition = root.timelinePosition;
                root.scrubTargetPosition = root.timelinePosition;
                root.isGestureScrubbing = false;
            }

            onPositionChanged: (mouse) => {
                if (!pressed) {
                    root.resetControlsTimer();
                    return;
                }

                var dx = mouse.x - root.scrubStartX;
                var dy = mouse.y - root.scrubStartY;
                if (player.duration > 0 && (root.isGestureScrubbing || (Math.abs(dx) > 12 && Math.abs(dx) > Math.abs(dy)))) {
                    root.isGestureScrubbing = true;
                    var offset = Math.round(dx * 180000 / Math.max(1, width));
                    root.scrubTargetPosition = Math.max(0, Math.min(player.duration, root.scrubStartPosition + offset));
                    root.showControls = true;
                }
            }

            onReleased: {
                if (root.isGestureScrubbing) {
                    player.seek(root.scrubTargetPosition);
                    root.isGestureScrubbing = false;
                    root.resetControlsTimer();
                } else {
                    root.togglePlaybackWithFeedback();
                }
            }

            onCanceled: root.isGestureScrubbing = false
        }

        Rectangle {
            id: playbackFeedback
            anchors.centerIn: parent
            width: 76
            height: width
            radius: width / 2
            color: "#cc211b30"
            z: 1
            visible: playbackFeedbackAnimation.running

            Image {
                id: playbackFeedbackIcon
                anchors.centerIn: parent
                width: 38
                height: 38
                sourceSize: Qt.size(width, height)
            }

            ParallelAnimation {
                id: playbackFeedbackAnimation
                NumberAnimation { target: playbackFeedback; property: "scale"; from: 0.82; to: 1.38; duration: 360; easing.type: Easing.OutCubic }
                SequentialAnimation {
                    PropertyAction { target: playbackFeedback; property: "opacity"; value: 1 }
                    PauseAnimation { duration: 85 }
                    NumberAnimation { target: playbackFeedback; property: "opacity"; from: 1; to: 0; duration: 275; easing.type: Easing.InQuad }
                }
            }
        }

        Timer {
            id: seekIndicatorDelay
            interval: 200
            running: player.seekPosition >= 0
            onTriggered: root.showSeekIndicator = true
        }

        ColumnLayout {
            anchors.centerIn: parent
            visible: (root.nextEpisodePending || root.isLoading || (root.showSeekIndicator && player.seekPosition >= 0)) && !root.isGestureScrubbing
            spacing: 14

            BusyIndicator {
                Layout.alignment: Qt.AlignHCenter
                running: parent.visible
                Material.accent: "#cfbcff"
            }

            Label {
                text: root.nextEpisodePending ? "Загрузка следующей серии…"
                    : root.reconnecting ? (root.playbackWanted ? "Повторное подключение…" : "Подключение приостановлено")
                    : !player.isReady ? "Загрузка видео…"
                    : player.seekPosition >= 0 ? "Перемотка…" : "Буферизация…"
                color: "#e6e1e5"
            }
        }

        Rectangle {
            anchors.centerIn: parent
            visible: root.playbackError.length > 0
            width: Math.min(parent.width - 32, 480)
            height: playbackErrorContent.implicitHeight + 32
            radius: 12
            color: "#1d192b"

            ColumnLayout {
                id: playbackErrorContent
                anchors.fill: parent
                anchors.margins: 16

                Text {
                    Layout.fillWidth: true
                    text: "Не удалось воспроизвести видео.\n" + root.playbackError
                    textFormat: Text.PlainText
                    wrapMode: Text.Wrap
                    horizontalAlignment: Text.AlignHCenter
                    color: "#ffb4ab"
                }

                Button {
                    Layout.alignment: Qt.AlignHCenter
                    text: "Повторить"
                    focusPolicy: Qt.NoFocus
                    onClicked: root.togglePlayback()
                }
            }
        }

        Item {
            anchors.fill: parent
            opacity: root.showControls ? 1 : 0
            visible: opacity > 0
            enabled: root.showControls

            Behavior on opacity { NumberAnimation { duration: 200 } }

            Rectangle {
                anchors.fill: parent
                color: "#300f0d13"
                visible: root.isGestureScrubbing
            }

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                height: 100
                gradient: Gradient {
                    GradientStop { position: 0.0; color: "#df0f0d13" }
                    GradientStop { position: 1.0; color: "transparent" }
                }
            }

            RowLayout {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: root.controlsMargin
                anchors.topMargin: 16
                spacing: 14

                PlayerButton {
                    iconName: "back"
                    description: "Назад"
                    onClicked: root.closePlayer()
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    Label {
                        Layout.fillWidth: true
                        text: root.releaseTitle
                        elide: Text.ElideRight
                        color: "#ffffff"
                        font.pixelSize: 18
                        font.weight: Font.DemiBold
                    }
                    Label {
                        Layout.fillWidth: true
                        text: root.episodeName
                        elide: Text.ElideRight
                        color: "#cac4d0"
                        font.pixelSize: 13
                    }
                }

                Button {
                    id: qualityButton
                    visible: root.qualities.length > 0
                    text: (root.selectedQuality || "Качество") + "  ▾"
                    focusPolicy: Qt.NoFocus
                    Material.foreground: "#f1eaff"
                    Accessible.name: "Качество видео " + root.selectedQuality
                    ToolTip.visible: hovered && player.videoHeight > 0 && !qualityMenu.opened
                    ToolTip.text: "Высота кадра — " + player.videoHeight + " пикселей"
                    onClicked: qualityMenu.open()

                    background: Rectangle {
                        y: 4
                        height: parent.height - 8
                        radius: 10
                        color: qualityButton.hovered || qualityMenu.opened ? "#4f4364" : "#392f4d"
                    }

                    Menu {
                        id: qualityMenu
                        x: qualityButton.width - width
                        y: qualityButton.height + 4
                        width: 152
                        padding: 6

                        background: Rectangle {
                            color: "#211b30"
                            radius: 12
                            border.color: "#4f4364"
                        }

                        Instantiator {
                            model: root.qualities
                            delegate: MenuItem {
                                id: qualityItem
                                readonly property bool selected: modelData === root.selectedQuality

                                text: modelData
                                font.weight: selected ? Font.DemiBold : Font.Normal
                                Material.foreground: selected ? "#e7d9ff" : "#e6e1e5"

                                background: Rectangle {
                                    radius: 6
                                    color: qualityItem.highlighted ? "#4f4364" : (qualityItem.selected ? "#392f4d" : "transparent")
                                }

                                onTriggered: {
                                    const url = root.streamsMap[modelData];
                                    root.selectedQuality = modelData;
                                    if (root.reconnecting) {
                                        if (root.playbackWanted) root.reconnect(0);
                                    } else if (url !== player.source || root.playbackError) {
                                        const position = root.timelinePosition;
                                        const wasPlaying = root.playbackWanted;
                                        root.saveWatchProgress();
                                        root.hasSavedCheckpoint = false;
                                        root.loadStream(url, position, wasPlaying, true);
                                    }
                                    root.resetControlsTimer();
                                }
                            }
                            onObjectAdded: (index, object) => qualityMenu.insertItem(index, object)
                            onObjectRemoved: (index, object) => qualityMenu.removeItem(object)
                        }
                    }
                }
            }

            RowLayout {
                anchors.centerIn: parent
                spacing: root.width >= 1100 ? 28 : 18
                visible: player.isReady && !root.nextEpisodePending && !root.isLoading && !root.showSeekIndicator && !root.isGestureScrubbing && !root.playbackError

                PlayerButton {
                    iconName: "replay_10"
                    description: "Назад на " + window.seekStepSec + " сек"
                    onClicked: player.skip(-window.seekStepSec * 1000)
                }

                PlayerButton {
                    primary: true
                    implicitWidth: 68
                    implicitHeight: 68
                    icon.width: 38
                    icon.height: 38
                    iconName: player.isPlaying ? "pause" : "play"
                    description: player.isPlaying ? "Пауза" : "Воспроизвести"
                    opacity: playbackFeedbackAnimation.running ? 0 : 1
                    onClicked: root.togglePlayback()
                }

                PlayerButton {
                    iconName: "forward_10"
                    description: "Вперёд на " + window.seekStepSec + " сек"
                    onClicked: player.skip(window.seekStepSec * 1000)
                }
            }

            Label {
                anchors.horizontalCenter: parent.horizontalCenter
                y: parent.height / 2 + 56
                width: Math.min(parent.width - 32, 480)
                visible: root.nextEpisodeError.length > 0
                text: "Не удалось открыть следующую серию.\n" + root.nextEpisodeError
                textFormat: Text.PlainText
                wrapMode: Text.Wrap
                horizontalAlignment: Text.AlignHCenter
                color: "#ffb4ab"
            }

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: 136
                gradient: Gradient {
                    GradientStop { position: 0.0; color: "transparent" }
                    GradientStop { position: 1.0; color: "#f20f0d13" }
                }
            }

            ColumnLayout {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: root.controlsMargin
                anchors.bottomMargin: 12
                spacing: 2

                Slider {
                    id: timeSlider
                    property real dragPosition: 0

                    Layout.fillWidth: true
                    focusPolicy: Qt.NoFocus
                    enabled: player.isReady && player.duration > 0
                    to: Math.max(1, player.duration)
                    live: false
                    Accessible.name: "Позиция воспроизведения"

                    Binding on value {
                        when: !timeSlider.pressed
                        value: root.isGestureScrubbing ? root.scrubTargetPosition : root.timelinePosition
                        restoreMode: Binding.RestoreNone
                    }

                    onMoved: {
                        if (pressed) {
                            dragPosition = valueAt(position);
                        } else {
                            player.seek(valueAt(position));
                        }
                    }
                    onPressedChanged: {
                        if (pressed) {
                            dragPosition = valueAt(position);
                        } else if (enabled) {
                            player.seek(dragPosition);
                        }
                        root.resetControlsTimer();
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Label {
                        Layout.leftMargin: 6
                        text: root.formatTime(root.displayedPosition) + " / " + root.formatTime(player.duration)
                        color: "#e6e1e5"
                        font.pixelSize: 14
                    }

                    Item { Layout.fillWidth: true }

                    PlayerButton {
                        iconName: "skip_opening"
                        description: "Пропустить опенинг"
                        enabled: player.isReady
                        onClicked: root.skipOpening()
                    }

                    PlayerButton {
                        iconName: player.volume <= 0.01 ? "volume_mute" : "volume_up"
                        description: player.volume <= 0.01 ? "Включить звук" : "Выключить звук"
                        onClicked: root.toggleMute()
                    }

                    Slider {
                        id: volumeSlider
                        Layout.preferredWidth: 88
                        focusPolicy: Qt.NoFocus
                        value: player.volume
                        Accessible.name: "Громкость"
                        onMoved: player.setVolume(value)
                    }

                    PlayerButton {
                        iconName: window.visibility === Window.FullScreen ? "fullscreen_exit" : "fullscreen"
                        description: window.visibility === Window.FullScreen ? "Выйти из полноэкранного режима" : "На весь экран"
                        onClicked: root.toggleFullScreen()
                    }
                }
            }
        }

        Label {
            anchors.centerIn: parent
            visible: root.isGestureScrubbing
            text: (root.scrubTargetPosition < root.scrubStartPosition ? "−" : "+")
                  + root.formatTime(Math.abs(root.scrubTargetPosition - root.scrubStartPosition))
            color: "#ffffff"
            font.pixelSize: Math.max(30, Math.min(54, root.width * 0.042))
            font.weight: Font.DemiBold
            style: Text.Outline
            styleColor: "#80000000"
        }
    }

    Dialog {
        id: resumeDialog
        anchors.centerIn: parent
        width: Math.min(root.width - 40, 410)
        title: "Продолжить просмотр?"
        header: Item {}
        padding: 24
        modal: true
        focus: true
        closePolicy: Popup.CloseOnEscape
        Material.background: "#211b30"
        onAccepted: root.startPlayback(root.resumePosition)
        onRejected: root.closePlayer()

        Overlay.modal: Rectangle { color: "#99000000" }

        background: Rectangle {
            radius: 24
            color: "#211b30"
            border.color: "#4f4364"
        }

        contentItem: ColumnLayout {
            spacing: 16

            Label {
                Layout.fillWidth: true
                text: resumeDialog.title
                color: "#ffffff"
                font.pixelSize: 24
                font.weight: Font.DemiBold
                wrapMode: Text.WordWrap
            }

            Label {
                Layout.fillWidth: true
                text: "Сохранённая позиция · " + root.formatTime(root.resumePosition)
                color: "#cac4d0"
                wrapMode: Text.WordWrap
            }

            RowLayout {
                Layout.alignment: Qt.AlignRight
                spacing: 8

                Button {
                    text: "С начала"
                    onClicked: {
                        root.startPlayback(0);
                        resumeDialog.close();
                    }
                }

                Button {
                    text: "Продолжить"
                    highlighted: true
                    onClicked: resumeDialog.accept()
                }
            }
        }
    }

    component PlayerButton: RoundButton {
        id: button
        property string iconName
        property string description
        property bool primary: false

        implicitWidth: 44
        implicitHeight: 44
        focusPolicy: Qt.NoFocus
        icon.source: "qrc:/assets/icons/" + iconName + ".svg"
        icon.width: 21
        icon.height: 21
        icon.color: primary ? "#211635" : "#ffffff"
        Accessible.name: description
        ToolTip.delay: 650
        ToolTip.visible: hovered
        ToolTip.text: description
        onClicked: root.resetControlsTimer()

        background: Rectangle {
            radius: width / 2
            opacity: button.enabled ? 1 : 0.42
            color: button.primary ? (button.hovered ? "#e1d4ff" : "#cfbcff")
                                  : (button.hovered ? "#e64f4364" : "#cc211b30")
        }
    }
}
