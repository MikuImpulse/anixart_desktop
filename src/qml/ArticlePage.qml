import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Flickable {
    id: root

    required property var initialArticle
    readonly property var articleId: initialArticle.id
    property var article: initialArticle
    property bool loading: false
    property bool failed: false
    readonly property Flickable pullSurface: root
    readonly property bool refreshing: loading || discussion.loading

    contentWidth: width
    contentHeight: body.implicitHeight + 48
    clip: true
    ScrollBar.vertical: AppScrollBar {}

    function loadArticle() {
        if (loading) return;
        loading = true;
        anixApi.fetchBrowseSection("article", 0, articleId, authManager.token, "");
    }

    function refresh() {
        loadArticle();
        discussion.load(0);
    }

    Component.onCompleted: loadArticle()

    Connections {
        target: anixApi
        function onBrowseSectionLoaded(section, page, id, query, data) {
            if (section !== "article" || id !== root.articleId) return;
            root.loading = false;
            root.failed = !data.article;
            if (data.article) root.article = data.article;
        }
    }

    ColumnLayout {
        id: body
        anchors.horizontalCenter: parent.horizontalCenter
        y: 20
        width: Math.min(root.width - 48, 920)
        spacing: 15

        Button { text: "Назад"; onClicked: root.StackView.view.pop() }

        Label {
            visible: root.failed
            text: "Не удалось загрузить полную запись"
            color: "#ffb4ab"
        }

        FeedPost {
            Layout.fillWidth: true
            article: root.article
            expanded: true
        }

        Discussion {
            id: discussion
            Layout.fillWidth: true
            entityId: root.articleId
            section: "articleComments"
            canComment: !root.article.is_deleted && root.article.channel?.is_commenting_enabled !== false
                && !root.article.channel?.is_blocked
        }
    }
}
