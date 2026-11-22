import QtQuick
import QtQuick.Controls 2.15
import QtQuick.Controls.Material 2.15
import QtQuick.Layouts 1.15
import Anixart 1.0
import QtCore

ApplicationWindow {
    id: window
    width: 1280
    height: 800
    minimumWidth: 960
    minimumHeight: 600
    visible: true
    title: "Anixart"
    flags: Qt.Window | Qt.FramelessWindowHint

    Material.theme: Material.Dark
    Material.accent: "#cfbcff"
    Material.primary: "#141218"
    Material.background: "#0f0d13"

    color: "#0f0d13"

    Overlay.modal: Rectangle {
        color: Qt.rgba(0, 0, 0, 0.72)
    }

    property int activeNavIndex: 0
    onActiveNavIndexChanged: stacks[activeNavIndex]?.ensureRoot()
    function navigateTo(idx) { activeNavIndex = idx; }
    function popToRoot(tabIndex) {
        var s = stacks[tabIndex];
        if (s && s.depth > 1) {
            s.pop(null);
        }
    }
    readonly property var stacks: [homeStack, catalogStack, bookmarksStack, settingsStack, profileStack, overviewStack, feedStack]
    readonly property StackView currentStack: (stacks[activeNavIndex] !== undefined) ? stacks[activeNavIndex] : homeStack
    readonly property StackView pageStack: currentStack

    function openRelease(relId) {
        if (pageStack) {
            pageStack.push("qrc:/qml/ReleaseDetailsPage.qml", { releaseId: relId });
        }
    }

    function openEpisodes(relId, title) {
        if (pageStack) {
            pageStack.push("qrc:/qml/VoiceoverEpisodesPage.qml", { releaseId: relId, releaseTitle: title });
        }
    }

    function openProfile(userId) {
        if (!(userId > 0)) return;
        if (authManager.isLoggedIn && userId === authManager.userId) {
            navigateTo(4);
            popToRoot(4);
        } else {
            currentStack.push("qrc:/qml/ProfilePage.qml", {requestedUserId: userId});
        }
    }

    function openChannel(channelId) {
        if (channelId > 0) currentStack.push("qrc:/qml/FeedPage.qml", {channelId: channelId});
    }

    function openArticle(article) {
        if (article?.id) currentStack.push("qrc:/qml/ArticlePage.qml", {initialArticle: article});
    }

    function openVoters(section, entityId) {
        currentStack.push("qrc:/qml/VotersPage.qml", {section: section, entityId: entityId});
    }

    function openReport(section, entityId, subject) {
        if (!authManager.isLoggedIn) {
            openAuthDialog();
            return;
        }
        currentStack.push("qrc:/qml/ReportPage.qml", {section: section, entityId: entityId, subject: subject});
    }

    function openFeedGallery(images, index) {
        mediaViewer.showImages(images, index, "Изображения", "");
    }

    function openMedia(url, title, subtitle) {
        if (url) mediaViewer.showMedia(url, title, subtitle);
    }

    function openReleaseComments(id, title, commentId, canComment, replyProfile) {
        if (!(id > 0)) return;
        currentStack.push("qrc:/qml/CommentsPage.qml", {
            section: "releaseComments",
            entityId: id,
            heading: title || "",
            focusCommentId: commentId || 0,
            canComment: canComment !== false,
            initialReplyProfile: replyProfile || null
        });
    }

    function openProfileExtras(section, id, owned) {
        if (!(id > 0)) return;
        currentStack.push("qrc:/qml/ProfileExtrasPage.qml", {
            section: section,
            entityId: id,
            ownProfile: !!owned && id === authManager.userId && authManager.isLoggedIn
        });
    }

    Settings {
        id: playbackSettings
        category: "Playback"
        property real volume: 1.0
        property real audibleVolume: 1.0
        property int skipOpeningDurationSec: 85
        property int seekStepSec: 10
        property string defaultQuality: "Максимально доступное"
        property bool autoPlayNext: true
    }

    function syncPlaybackSettings() { playbackSettings.sync(); }

    property alias playbackVolume: playbackSettings.volume
    property alias audibleVolume: playbackSettings.audibleVolume

    property alias skipOpeningDurationSec: playbackSettings.skipOpeningDurationSec
    property alias seekStepSec: playbackSettings.seekStepSec
    property alias defaultQuality: playbackSettings.defaultQuality
    property alias autoPlayNext: playbackSettings.autoPlayNext

    readonly property bool isPlayerActive: currentStack && currentStack.currentItem && currentStack.currentItem.objectName === "playerPage"

    property bool restoreMaximized: false
    readonly property bool showChrome: !isPlayerActive || visibility !== Window.FullScreen
    readonly property int navigationDockInset: dock.visible ? dock.height + 24 : 0

    function selectSection(index) {
        if (activeNavIndex === index) {
            popToRoot(index);
        } else {
            navigateTo(index);
        }
    }

    function toggleMaximized() {
        if (visibility === Window.Maximized) {
            showNormal();
        } else if (visibility !== Window.FullScreen) {
            showMaximized();
        }
    }

    function toggleWindowFullscreen() {
        if (!isPlayerActive && visibility !== Window.FullScreen) return;
        if (visibility === Window.FullScreen) {
            if (restoreMaximized) showMaximized();
            else showNormal();
        } else {
            restoreMaximized = visibility === Window.Maximized;
            showFullScreen();
        }
    }

    function openSearch() {
        if (activeNavIndex === 6) {
            popToRoot(6);
            if (feedStack.currentItem && typeof feedStack.currentItem.openSearch === "function") {
                feedStack.currentItem.openSearch();
                return;
            }
        }
        navigateTo(1);
        popToRoot(1);
        catalogStack.currentItem.focusSearch();
    }

    Item {
        anchors.fill: parent

        StackLayout {
            id: sectionArea
            anchors.fill: parent
            anchors.topMargin: window.showChrome ? windowBar.height : 0
            currentIndex: window.activeNavIndex

            SectionStack { id: homeStack; initialItem: "qrc:/qml/ReleaseGridPage.qml" }
            SectionStack { id: catalogStack; rootPage: "qrc:/qml/CatalogPage.qml" }
            SectionStack { id: bookmarksStack; rootPage: "qrc:/qml/BookmarksPage.qml" }
            SectionStack { id: settingsStack; rootPage: "qrc:/qml/SettingsPage.qml" }
            SectionStack { id: profileStack; rootPage: "qrc:/qml/ProfilePage.qml" }
            SectionStack { id: overviewStack; rootPage: "qrc:/qml/HomePage.qml" }
            SectionStack { id: feedStack; rootPage: "qrc:/qml/FeedPage.qml" }
        }

        PullRefresh {
            anchors.top: sectionArea.top
            width: sectionArea.width
            surface: window.currentStack.currentItem?.pullSurface ?? null
            busy: window.currentStack.currentItem?.refreshing ?? false
            onRequested: {
                window.currentStack.currentItem.refresh();
                pending = window.currentStack.currentItem?.refreshing ?? false;
            }
        }

        Rectangle {
            id: windowBar
            objectName: "windowBar"
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            visible: window.showChrome
            height: 42
            color: "#141218"

            Rectangle {
                anchors.bottom: parent.bottom
                width: parent.width
                height: 1
                color: "#25212d"
            }

            Item {
                anchors.fill: parent
                anchors.rightMargin: windowActions.width + 6
                enabled: window.visibility !== Window.FullScreen

                DragHandler {
                    target: null
                    acceptedButtons: Qt.LeftButton
                    onActiveChanged: {
                        if (active) window.startSystemMove();
                    }
                }

                TapHandler {
                    acceptedButtons: Qt.LeftButton
                    onDoubleTapped: window.toggleMaximized()
                }
            }

            RowLayout {
                id: windowActions
                anchors.right: parent.right
                anchors.rightMargin: 9
                anchors.verticalCenter: parent.verticalCenter
                spacing: 4

                ChromeButton {
                    objectName: "settingsShortcut"
                    visible: !window.isPlayerActive
                    description: "Настройки"
                    icon.source: "qrc:/assets/icons/settings.svg"
                    selected: window.activeNavIndex === 3
                    onClicked: window.selectSection(3)
                }

                ChromeButton {
                    id: profileButton
                    objectName: "profileShortcut"
                    visible: !window.isPlayerActive
                    description: "Профиль"
                    icon.source: hasAvatar ? "" : "qrc:/assets/icons/profile.svg"
                    selected: window.activeNavIndex === 4
                    readonly property bool hasAvatar: authManager.isLoggedIn && authManager.userAvatar.length > 0
                    onClicked: window.selectSection(4)

                    CircleImage {
                        anchors.centerIn: parent
                        width: 23
                        height: 23
                        source: profileButton.hasAvatar ? authManager.userAvatar : ""
                        visible: profileButton.hasAvatar
                    }
                }

                Rectangle {
                    visible: !window.isPlayerActive
                    Layout.leftMargin: 5
                    Layout.rightMargin: 5
                    Layout.preferredWidth: 1
                    Layout.preferredHeight: 19
                    color: "#3a3247"
                }

                WindowButton {
                    description: "Свернуть"
                    icon.source: "qrc:/assets/icons/minimize_window.svg"
                    onClicked: window.showMinimized()
                }

                WindowButton {
                    visible: window.visibility !== Window.FullScreen
                    description: window.visibility === Window.Maximized ? "Восстановить окно" : "Развернуть окно"
                    icon.source: window.visibility === Window.Maximized ? "qrc:/assets/icons/restore_window.svg" : "qrc:/assets/icons/maximize_window.svg"
                    onClicked: window.toggleMaximized()
                }

                WindowButton {
                    description: "Закрыть"
                    icon.source: "qrc:/assets/icons/close.svg"
                    hoverColor: "#612d42"
                    onClicked: window.close()
                }
            }
        }

        Rectangle {
            id: dock
            objectName: "navigationDock"
            anchors.bottom: parent.bottom
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottomMargin: 12
            visible: !window.isPlayerActive
            width: dockRow.implicitWidth + 16
            height: 52
            radius: 16
            color: "#201a2b"
            border.color: "#453754"

            RowLayout {
                id: dockRow
                anchors.centerIn: parent
                spacing: 5

                Repeater {
                    model: [
                        { title: "Главная", iconName: "home", tab: 0 },
                        { title: "Обзор", iconName: "catalog", tab: 5 },
                        { title: "Закладки", iconName: "bookmarks", tab: 2 },
                        { title: "Лента", iconName: "feed", tab: 6 }
                    ]

                    delegate: ToolButton {
                        id: tabButton
                        required property var modelData
                        readonly property bool selected: window.activeNavIndex === modelData.tab

                        Layout.preferredWidth: 112
                        Layout.preferredHeight: 36
                        text: modelData.title
                        icon.source: "qrc:/assets/icons/" + modelData.iconName + ".svg"
                        icon.width: 17
                        icon.height: 17
                        icon.color: selected ? "#f4ebff" : "#c3b9d0"
                        font.weight: selected ? Font.DemiBold : Font.Medium
                        Material.foreground: selected ? "#f4ebff" : "#c3b9d0"
                        Accessible.selected: selected
                        HoverHandler { cursorShape: Qt.PointingHandCursor }
                        onClicked: window.selectSection(modelData.tab)

                        background: Rectangle {
                            radius: 10
                            color: tabButton.selected ? "#49355f" : (tabButton.hovered || tabButton.activeFocus ? "#332840" : "#201a2b")
                            Behavior on color { ColorAnimation { duration: 160 } }

                            Rectangle {
                                anchors.bottom: parent.bottom
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: tabButton.selected ? 20 : 0
                                height: 2
                                radius: 1
                                color: "#cfbcff"
                                Behavior on width { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                            }
                        }
                    }
                }

                Rectangle {
                    Layout.preferredWidth: 1
                    Layout.preferredHeight: 22
                    Layout.leftMargin: 3
                    color: "#453754"
                }

                ChromeButton {
                    objectName: "searchShortcut"
                    description: "Поиск"
                    selected: window.activeNavIndex === 1
                    icon.source: "qrc:/assets/icons/search.svg"
                    onClicked: window.openSearch()
                }
            }
        }

        Repeater {
            model: [Qt.TopEdge | Qt.LeftEdge, Qt.TopEdge, Qt.TopEdge | Qt.RightEdge,
                    Qt.LeftEdge, Qt.RightEdge, Qt.BottomEdge | Qt.LeftEdge, Qt.BottomEdge, Qt.BottomEdge | Qt.RightEdge]

            delegate: MouseArea {
                required property int modelData
                readonly property bool leftEdge: (modelData & Qt.LeftEdge) !== 0
                readonly property bool rightEdge: (modelData & Qt.RightEdge) !== 0
                readonly property bool topEdge: (modelData & Qt.TopEdge) !== 0
                readonly property bool bottomEdge: (modelData & Qt.BottomEdge) !== 0
                readonly property int grip: 5

                enabled: window.visibility === Window.Windowed
                width: leftEdge || rightEdge ? grip : parent.width - 2 * grip
                height: topEdge || bottomEdge ? grip : parent.height - 2 * grip
                x: leftEdge ? 0 : (rightEdge ? parent.width - width : grip)
                y: topEdge ? 0 : (bottomEdge ? parent.height - height : grip)
                cursorShape: leftEdge || rightEdge
                    ? (topEdge || bottomEdge ? (leftEdge === topEdge ? Qt.SizeFDiagCursor : Qt.SizeBDiagCursor) : Qt.SizeHorCursor)
                    : Qt.SizeVerCursor
                onPressed: window.startSystemResize(modelData)
            }
        }
    }

    Shortcut {
        sequence: "Ctrl+F"
        enabled: !window.isPlayerActive
        onActivated: window.openSearch()
    }

    Shortcut {
        sequence: "Ctrl+R"
        enabled: !!window.currentStack.currentItem?.pullSurface && !mediaViewer.visible
        onActivated: window.currentStack.currentItem.refresh()
    }

    Connections {
        target: anixApi
        function onNetworkRouteChanged() {
            if (!window.isPlayerActive) {
                networkRefresh.page = window.currentStack.currentItem;
                networkRefresh.restart();
            }
        }
    }

    Timer {
        id: networkRefresh
        interval: 500
        property var page: null
        onTriggered: {
            if (page !== window.currentStack.currentItem || typeof page?.refresh !== "function") {
                page = null;
            } else if (page.refreshing) {
                restart();
            } else {
                page.refresh();
                page = null;
            }
        }
    }

    MediaViewer {
        id: mediaViewer
        objectName: "mediaViewer"
        transientParent: window
    }

    component WindowButton: ChromeButton {
        focusPolicy: Qt.NoFocus
        icon.width: 13
        icon.height: 13
        Layout.preferredWidth: 29
        Layout.preferredHeight: 26
    }

    component SectionStack: StackView {
        id: sectionStack
        property url rootPage
        readonly property var currentPullSurface: currentItem?.pullSurface ?? null

        function ensureRoot() {
            if (depth === 0 && rootPage.toString()) push(rootPage, StackView.Immediate);
        }

        Binding {
            target: sectionStack.currentPullSurface
            property: "bottomMargin"
            value: window.navigationDockInset
            when: sectionStack.currentPullSurface !== null
        }

        pushEnter: Transition { PropertyAnimation { property: "opacity"; from: 0; to: 1; duration: 180 } }
        pushExit: Transition { PropertyAnimation { property: "opacity"; from: 1; to: 0; duration: 120 } }
        popEnter: Transition { PropertyAnimation { property: "opacity"; from: 0; to: 1; duration: 180 } }
        popExit: Transition { PropertyAnimation { property: "opacity"; from: 1; to: 0; duration: 120 } }
    }

    component ChromeButton: ToolButton {
        id: chromeButton
        property string description
        property bool selected: false
        property color hoverColor: "#31283e"

        Layout.preferredWidth: 35
        Layout.preferredHeight: 30
        icon.width: 17
        icon.height: 17
        icon.color: selected ? "#e9d9ff" : "#c4bacd"
        font.pixelSize: 17
        Accessible.name: description
        ToolTip.text: description
        ToolTip.delay: 500
        ToolTip.visible: hovered
        HoverHandler { cursorShape: Qt.PointingHandCursor }

        background: Rectangle {
            radius: 7
            color: chromeButton.selected ? "#453354" : (chromeButton.hovered || chromeButton.activeFocus ? chromeButton.hoverColor : "transparent")
            Behavior on color { ColorAnimation { duration: 120 } }
        }
    }

    AuthDialog {
        id: authDialog
    }

    function openAuthDialog() {
        authDialog.open();
    }
}
