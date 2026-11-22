import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import Anixart 1.0

ColumnLayout {
    id: root

    required property string section
    required property var entityId
    property bool canComment: true
    property bool preview: false
    property Item composerHost: null
    property var previewComments: null
    property var focusedComment: null
    property bool loading: false
    property bool refreshAfterLoad: false
    property bool sending: false
    property bool failed: false
    property string sendError: ""
    property var comments: []
    property var deletedComments: ({})
    property var editedComments: ({})
    property int page: 0
    property int totalCount: 0
    property int totalPageCount: 0
    property int sort: 0
    property var focusCommentId: 0
    property var replyParentId: 0
    property var replyToProfileId: 0
    property string replyToLogin: ""
    readonly property var sortValues: [1, 2, 3]
    readonly property bool hasMore: page < totalPageCount
    readonly property var visibleComments: {
        const rows = preview && previewComments !== null ? previewComments : comments;
        if (preview) return rows.slice(0, 5);
        if (focusedComment && !rows.some(comment => comment.id === focusedComment.id))
            return [focusedComment].concat(rows);
        return rows;
    }

    signal openAll(var commentId, var replyProfile)

    function openCommentActions(comment, author, revealed, hitArea, mouse) {
        if (comment.is_deleted || deletedComments[comment.id] || !(comment.id > 0)) return;

        commentMenu.commentId = comment.id;
        commentMenu.authorId = author.id || 0;
        const current = editedComments[comment.id] || comment;
        commentMenu.message = current.message || "";
        commentMenu.spoiler = !!current.is_spoiler;
        commentMenu.concealed = commentMenu.spoiler && !revealed;
        const point = hitArea.mapToItem(commentMenu.parent, mouse.x, mouse.y);
        commentMenu.x = point.x;
        commentMenu.y = point.y;
        commentMenu.open();
    }

    Menu {
        id: commentMenu
        parent: root
        popupType: Popup.Item
        property var commentId
        property var authorId
        property string message
        property bool spoiler
        property bool concealed
        readonly property bool ownComment: authManager.isLoggedIn && authorId === authManager.userId

        MenuItem { text: "Оценили"; onTriggered: window.openVoters(root.section, commentMenu.commentId) }
        MenuItem {
            text: "Скопировать"
            enabled: commentMenu.message.length > 0 && !commentMenu.concealed
            onTriggered: authManager.copyToClipboard(commentMenu.message)
        }
        MenuItem {
            text: "Пожаловаться"
            visible: !commentMenu.ownComment
            height: visible ? implicitHeight : 0
            onTriggered: window.openReport(root.section, commentMenu.commentId,
                commentMenu.concealed ? "Комментарий со спойлером" : "Комментарий «" + commentMenu.message + "»")
        }
        MenuItem {
            text: "Редактировать"
            visible: commentMenu.ownComment
            height: visible ? implicitHeight : 0
            onTriggered: {
                editDialog.commentId = commentMenu.commentId;
                editDialog.authorId = commentMenu.authorId;
                editDialog.originalMessage = commentMenu.message;
                editDialog.originalSpoiler = commentMenu.spoiler;
                editMessage.text = editDialog.originalMessage;
                editSpoiler.checked = editDialog.originalSpoiler;
                editDialog.errorCode = 0;
                editDialog.open();
            }
        }
        MenuItem {
            text: "Удалить"
            visible: commentMenu.ownComment
            height: visible ? implicitHeight : 0
            onTriggered: {
                deleteDialog.commentId = commentMenu.commentId;
                deleteDialog.authorId = commentMenu.authorId;
                deleteDialog.errorCode = 0;
                deleteDialog.open();
            }
        }
    }

    Dialog {
        id: editDialog
        parent: Overlay.overlay
        anchors.centerIn: parent
        width: Math.min(parent.width - 40, 480)
        title: "Редактировать комментарий"
        modal: true
        closePolicy: pending ? Popup.NoAutoClose : Popup.CloseOnEscape
        Overlay.modal: Rectangle { color: "#bb000000" }

        property var commentId
        property var authorId
        property string originalMessage
        property bool originalSpoiler
        property bool pending: false
        property int errorCode: 0
        readonly property string message: editMessage.text.trim()

        onOpened: {
            editMessage.forceActiveFocus();
            editMessage.cursorPosition = editMessage.length;
        }

        contentItem: ColumnLayout {
            ScrollView {
                Layout.fillWidth: true
                Layout.preferredHeight: 128
                contentWidth: availableWidth
                clip: true

                TextArea {
                    id: editMessage
                    Accessible.name: "Текст комментария"
                    textFormat: TextEdit.PlainText
                    wrapMode: TextEdit.Wrap
                    verticalAlignment: TextEdit.AlignTop
                    topInset: 0
                    bottomInset: 0
                    topPadding: 14
                    bottomPadding: 14
                    leftPadding: 14
                    rightPadding: 14
                    readOnly: editDialog.pending
                    selectByMouse: true
                    background: Rectangle {
                        radius: 12
                        color: "#211a2b"
                        border.color: editMessage.activeFocus ? "#cfbcff" : "#4a3a59"
                    }
                }
            }

            CheckBox {
                id: editSpoiler
                text: "Содержит спойлер"
                enabled: !editDialog.pending
            }

            Label {
                Layout.fillWidth: true
                visible: editDialog.errorCode !== 0
                text: editDialog.errorCode === 402 ? "Anixart отклонил редактирование комментария (402)"
                    : "Не удалось сохранить изменения" + (editDialog.errorCode > 0 ? " · код " + editDialog.errorCode : "")
                color: "#ffb4ab"
                wrapMode: Text.Wrap
            }
        }

        footer: DialogButtonBox {
            Button { text: "Отмена"; enabled: !editDialog.pending; onClicked: editDialog.close() }

            Button {
                text: editDialog.pending ? "Сохранение…" : "Сохранить"
                highlighted: true
                enabled: !editDialog.pending && authManager.isLoggedIn && editDialog.authorId === authManager.userId
                    && editDialog.message.length > 0
                    && (editDialog.message !== editDialog.originalMessage.trim() || editSpoiler.checked !== editDialog.originalSpoiler)
                onClicked: {
                    editDialog.errorCode = 0;
                    editDialog.pending = true;
                    anixApi.editComment(root.section, editDialog.commentId, editDialog.message, editSpoiler.checked, authManager.token);
                }
            }
        }
    }

    Dialog {
        id: deleteDialog
        parent: Overlay.overlay
        anchors.centerIn: parent
        width: Math.min(parent.width - 40, 420)
        title: "Удалить комментарий?"
        modal: true
        closePolicy: pending ? Popup.NoAutoClose : Popup.CloseOnEscape
        Overlay.modal: Rectangle { color: "#bb000000" }
        property var commentId
        property var authorId
        property bool pending: false
        property int errorCode: 0

        contentItem: Label {
            wrapMode: Text.Wrap
            text: deleteDialog.errorCode === 0 ? "Восстановить комментарий после удаления нельзя."
                : "Не удалось удалить комментарий" + (deleteDialog.errorCode > 0 ? " · код " + deleteDialog.errorCode : "")
            color: deleteDialog.errorCode === 0 ? "#eee7f1" : "#ffb4ab"
        }

        footer: DialogButtonBox {
            Button {
                text: "Отмена"
                enabled: !deleteDialog.pending
                onClicked: deleteDialog.close()
            }
            Button {
                text: deleteDialog.pending ? "Удаление…" : "Удалить"
                enabled: !deleteDialog.pending && authManager.isLoggedIn && deleteDialog.authorId === authManager.userId
                highlighted: true
                onClicked: {
                    deleteDialog.pending = true;
                    deleteDialog.errorCode = 0;
                    anixApi.deleteComment(root.section, deleteDialog.commentId, authManager.token);
                }
            }
        }
    }

    function load(number) {
        if (entityId <= 0 || preview) return;
        if (loading) {
            if (number === 0) refreshAfterLoad = true;
            return;
        }

        loading = true;
        failed = false;
        anixApi.fetchComments(section, entityId, number, preview ? 3 : sortValues[sort], authManager.token);
    }

    function setReply(commentId, profile) {
        if (preview) {
            openAll(commentId, profile);
            return;
        }
        replyParentId = commentId;
        replyToProfileId = profile?.id || 0;
        replyToLogin = profile?.login || "пользователю";
        composer.forceActiveFocus();
    }

    function clearReply() {
        replyParentId = 0;
        replyToProfileId = 0;
        replyToLogin = "";
    }

    onSortChanged: {
        if (!preview && entityId > 0) load(0);
    }

    Component.onCompleted: {
        if (focusCommentId > 0) anixApi.fetchComment(section, focusCommentId, authManager.token);
        load(0);
    }

    Connections {
        target: anixApi

        function onCommentEditProcessed(section, id, message, spoiler, code) {
            if (section !== root.section) return;
            if (code === 0) {
                const edit = { message: message, is_spoiler: spoiler };
                root.editedComments = Object.assign({}, root.editedComments, {[id]: edit});
            }
            if (!editDialog.pending || id !== editDialog.commentId) return;

            editDialog.pending = false;
            editDialog.errorCode = code;
            if (code === 0) editDialog.close();
        }

        function onCommentDeleteProcessed(section, id, code) {
            if (section !== root.section) return;
            if (code === 0) {
                root.deletedComments = Object.assign({}, root.deletedComments, {[id]: true});
                if (id === root.replyParentId) root.clearReply();
            }
            if (!deleteDialog.pending || id !== deleteDialog.commentId) return;

            deleteDialog.pending = false;
            deleteDialog.errorCode = code;
            if (code === 0) deleteDialog.close();
        }

        function onCommentsLoaded(section, entityId, rows, loadedPage, total, totalPages, success) {
            if (section !== root.section || entityId !== root.entityId || !root.loading) return;
            root.loading = false;
            root.failed = !success;
            if (success) {
                root.comments = loadedPage === 0 ? rows : root.comments.concat(rows);
                root.page = loadedPage;
                root.totalCount = total;
                root.totalPageCount = totalPages;
            }
            if (root.refreshAfterLoad) {
                root.refreshAfterLoad = false;
                root.load(0);
            }
        }

        function onCommentLoaded(section, id, comment) {
            if (section === root.section && id === root.focusCommentId && comment.release?.id === root.entityId)
                root.focusedComment = comment;
        }

        function onCommentAdded(section, entityId, data) {
            if (section !== root.section || entityId !== root.entityId || !root.sending) return;
            root.sending = false;
            if (data.code !== 0) {
                root.sendError = data.code === 402 ? "Anixart отклонил отправку комментария (402)"
                    : data.code === 7 ? "Достигнут лимит комментариев"
                    : "Не удалось отправить комментарий" + (data.code > 0 ? " · код " + data.code : "");
                return;
            }
            composer.clear();
            spoiler.checked = false;
            root.clearReply();
            root.load(0);
        }
    }

    spacing: 10

    RowLayout {
        Layout.fillWidth: true

        Label {
            text: root.preview ? "Комментарии" : "Комментарии · " + root.totalCount
            font.pixelSize: 24
            font.weight: Font.DemiBold
        }

        Item { Layout.fillWidth: true }

        ComboBox {
            visible: !root.preview
            model: ["Сначала новые", "Сначала старые", "По рейтингу"]
            currentIndex: root.sort
            enabled: !root.loading
            onActivated: root.sort = currentIndex
        }
    }

    BusyIndicator {
        Layout.alignment: Qt.AlignHCenter
        running: root.loading && root.comments.length === 0
        visible: running
    }

    Label {
        visible: root.failed || (!root.loading && root.visibleComments.length === 0)
        text: root.failed ? "Не удалось загрузить комментарии" : "Комментариев пока нет"
        color: root.failed ? "#ffb4ab" : "#c8bbd3"
    }

    Repeater {
        model: root.visibleComments

        delegate: CommentCard {
            required property var modelData
            Layout.fillWidth: true
            section: root.section
            comment: modelData
            compact: root.preview
            highlighted: modelData.id === root.focusCommentId
            onReplyRequested: (commentId, profile) => root.setReply(commentId, profile)
        }
    }

    Button {
        visible: root.preview && (root.totalCount > 5 || root.visibleComments.length >= 5)
        text: "Все комментарии"
        onClicked: root.openAll(0, null)
    }

    Button {
        visible: !root.preview && root.hasMore
        enabled: !root.loading
        text: "Ещё комментарии"
        onClicked: root.load(root.page + 1)
    }

    Rectangle {
        Layout.fillWidth: true
        visible: root.preview && root.canComment && authManager.isLoggedIn
        implicitHeight: 50
        radius: 14
        color: "#211a2b"
        border.color: "#382d49"

        Label {
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: 14
            text: "Написать комментарий"
            color: "#cdbdff"
        }

        TapHandler { onTapped: root.openAll(0, null) }
    }

    ColumnLayout {
        parent: root.composerHost || root
        Layout.fillWidth: true
        visible: !root.preview

        ColumnLayout {
            Layout.fillWidth: true
            visible: !root.preview && root.canComment && authManager.isLoggedIn
            spacing: 7

            RowLayout {
                Layout.fillWidth: true
                visible: root.replyParentId > 0

                Label {
                    Layout.fillWidth: true
                    text: "Ответ для " + root.replyToLogin
                    color: "#cdbdff"
                    elide: Text.ElideRight
                }

                AppToolButton { text: "×"; onClicked: root.clearReply() }
            }

            TextArea {
                id: composer
                Layout.fillWidth: true
                Layout.preferredHeight: 88
                objectName: "commentInput"
                Accessible.name: root.replyParentId > 0 ? "Ваш ответ" : "Ваш комментарий"
                topPadding: 12
                bottomPadding: 12
                leftPadding: 14
                rightPadding: 14
                verticalAlignment: TextEdit.AlignTop

                Label {
                    x: composer.leftPadding
                    y: composer.topPadding
                    text: composer.Accessible.name
                    color: "#bcb1c9"
                    visible: !composer.text && !composer.preeditText
                }
                wrapMode: TextEdit.Wrap
                enabled: !root.sending
                selectByMouse: true
                background: Rectangle { radius: 14; color: "#211a2b"; border.color: "#382d49" }
            }

            RowLayout {
                Layout.fillWidth: true

                CheckBox {
                    id: spoiler
                    text: "Спойлер"
                    enabled: !root.sending
                }

                Item { Layout.fillWidth: true }

                Button {
                    text: root.sending ? "Отправка…" : "Отправить"
                    highlighted: true
                    Material.foreground: "#211331"
                    enabled: !root.sending && composer.text.trim().length > 0
                    onClicked: {
                        root.sendError = "";
                        root.sending = true;
                        anixApi.addCommentReply(root.section, root.entityId, composer.text, spoiler.checked,
                            root.replyParentId, root.replyToProfileId, authManager.token);
                    }
                }
            }
        }

        Button {
            visible: !root.preview && root.canComment && !authManager.isLoggedIn
            text: "Войти, чтобы комментировать"
            onClicked: window.openAuthDialog()
        }

        Label {
            visible: root.sendError !== ""
            text: root.sendError
            color: "#ffb4ab"
        }

    }

    component CommentVote: RowLayout {
        id: rating

        required property string section
        required property var comment
        property int voteValue: comment.vote === 2 ? 1 : comment.vote === 1 ? -1 : 0
        property int voteCount: comment.vote_count || 0
        property bool pending: false
        property int errorCode: 0
        readonly property bool canVote: !pending && authManager.isLoggedIn && comment.can_like !== false

        function vote(value) {
            if (!canVote) return;

            errorCode = 0;
            pending = true;
            anixApi.sendCommentVote(section, comment.id, value, authManager.token);
        }

        Connections {
            target: anixApi

            function onCommentVoteProcessed(section, commentId, vote, code) {
                if (section !== rating.section || commentId !== rating.comment.id || !rating.pending) return;

                rating.pending = false;
                rating.errorCode = code;
                if (code !== 0) return;

                const newVote = rating.voteValue === vote ? 0 : vote;
                rating.voteCount += newVote - rating.voteValue;
                rating.voteValue = newVote;
            }
        }

        AppToolButton { text: "−"; enabled: rating.canVote; highlighted: rating.voteValue < 0; onClicked: rating.vote(-1) }

        Label {
            text: (rating.voteCount > 0 ? "+" : "") + rating.voteCount
            color: rating.voteCount > 0 ? "#8ae69c" : rating.voteCount < 0 ? "#ffb4ab" : "#c8bbd3"
        }

        AppToolButton { text: "+"; enabled: rating.canVote; highlighted: rating.voteValue > 0; onClicked: rating.vote(1) }

        Label {
            visible: rating.errorCode !== 0
            text: rating.errorCode === 402 ? "Оценки ограничены (402)"
                : "Оценка не отправлена" + (rating.errorCode > 0 ? " · код " + rating.errorCode : "")
            color: "#ffb4ab"
        }
    }

    component CommentCard: Rectangle {
        id: card

        required property string section
        required property var comment
        readonly property var author: comment.profile || comment.creator || comment.author || {}
        readonly property bool deleted: !!comment.is_deleted || !!root.deletedComments[comment.id]
        readonly property var currentComment: root.editedComments[comment.id] || comment
        property bool compact: false
        property bool highlighted: false
        property bool revealed: false
        onCurrentCommentChanged: revealed = false
        property bool repliesLoading: false
        property bool repliesFailed: false
        property bool repliesExpanded: false
        property int repliesPage: 0
        property int repliesTotal: 0
        property int repliesPages: 0
        property var replies: []

        signal replyRequested(var commentId, var profile)

        implicitHeight: content.implicitHeight + 22
        radius: 14
        color: commentHitArea.pressed ? "#3a2a49" : highlighted ? "#2a2038" : "#1d1726"
        border.color: "#31253e"

        function loadReplies(number) {
            if (repliesLoading || comment.id <= 0) return;
            repliesLoading = true;
            repliesFailed = false;
            anixApi.fetchCommentReplies(section, comment.id, number, 2, authManager.token);
        }

        Connections {
            target: anixApi

            function onCommentRepliesLoaded(section, commentId, rows, loadedPage, total, totalPages, success) {
                if (section !== card.section || commentId !== card.comment.id) return;
                card.repliesLoading = false;
                card.repliesFailed = !success;
                if (!success) return;
                card.replies = loadedPage === 0 ? rows : card.replies.concat(rows);
                card.repliesPage = loadedPage;
                card.repliesTotal = total;
                card.repliesPages = totalPages;
            }
        }

        MouseArea {
            id: commentHitArea
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            enabled: !card.deleted && card.comment.id > 0
            cursorShape: Qt.PointingHandCursor
            onClicked: mouse => root.openCommentActions(card.comment, card.author, card.revealed, commentHitArea, mouse)
        }

        ColumnLayout {
            id: content
            anchors.fill: parent
            anchors.margins: 11
            spacing: 7

            RowLayout {
                Layout.fillWidth: true

                IdentityButton {
                    Layout.maximumWidth: card.width * 0.7
                    text: card.author.login || "Пользователь"
                    avatarSource: card.author.avatar || ""
                    badgeSource: card.author.badge_url || ""
                    enabled: card.author.id > 0
                    onClicked: window.openProfile(card.author.id)
                }

                Item { Layout.fillWidth: true }

                Label {
                    text: card.comment.timestamp ? Qt.formatDateTime(new Date(card.comment.timestamp * 1000), "d MMM · hh:mm") : ""
                    color: "#b6aabf"
                    font.pixelSize: 12
                }
            }

            Label {
                Layout.fillWidth: true
                visible: card.comment.posted_at_episode > 0
                text: "После серии " + card.comment.posted_at_episode
                color: "#cdbdff"
                font.pixelSize: 12
            }

            RoundButton {
                Layout.fillWidth: true
                visible: !!card.currentComment.is_spoiler && !card.deleted
                text: card.revealed ? "Скрыть спойлер" : "Спойлер · нажмите, чтобы прочитать"
                onClicked: card.revealed = !card.revealed
                background: Rectangle {
                    radius: height / 2
                    color: parent.hovered ? "#443556" : "#30243e"
                    border.color: "#574369"
                }
            }

            Label {
                Layout.fillWidth: true
                visible: card.deleted || !card.currentComment.is_spoiler || card.revealed
                text: card.deleted ? "Комментарий удалён" : (card.currentComment.message || "")
                wrapMode: Text.Wrap
                textFormat: Text.PlainText
                color: "#eee7f1"
            }

            RowLayout {
                Layout.fillWidth: true

                CommentVote {
                    visible: !card.deleted
                    section: card.section
                    comment: card.comment
                }

                AppToolButton {
                    text: "Ответить"
                    visible: !card.deleted
                    enabled: authManager.isLoggedIn || card.compact
                    onClicked: card.replyRequested(card.comment.id, card.author)
                }

                Item { Layout.fillWidth: true }

                AppToolButton {
                    visible: (card.comment.reply_count || 0) > 0
                    text: card.repliesExpanded ? "Скрыть ответы" : "Ответы · " + card.comment.reply_count
                    onClicked: {
                        card.repliesExpanded = !card.repliesExpanded;
                        if (card.repliesExpanded && card.replies.length === 0) card.loadReplies(0);
                    }
                }
            }

            Label { visible: card.repliesExpanded && card.repliesLoading; text: "Загрузка ответов…"; color: "#c8bbd3" }
            Label { visible: card.repliesExpanded && card.repliesFailed; text: "Не удалось загрузить ответы"; color: "#ffb4ab" }

            Repeater {
                model: card.repliesExpanded ? card.replies : []

                delegate: Rectangle {
                    id: replyCard
                    required property var modelData
                    readonly property var author: modelData.profile || modelData.creator || modelData.author || {}
                    readonly property bool deleted: !!modelData.is_deleted || !!root.deletedComments[modelData.id]
                    readonly property var currentComment: root.editedComments[modelData.id] || modelData
                    property bool revealed: false
                    onCurrentCommentChanged: revealed = false
                    Layout.fillWidth: true
                    implicitHeight: replyContent.implicitHeight + 16
                    radius: 10
                    color: replyHitArea.pressed ? "#3a2a49" : "#251d2f"

                    MouseArea {
                        id: replyHitArea
                        anchors.fill: parent
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        enabled: !replyCard.deleted && replyCard.modelData.id > 0
                        cursorShape: Qt.PointingHandCursor
                        onClicked: mouse => root.openCommentActions(replyCard.modelData, replyCard.author, replyCard.revealed, replyHitArea, mouse)
                    }

                    ColumnLayout {
                        id: replyContent
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 4

                        IdentityButton {
                            Layout.alignment: Qt.AlignLeft
                            Layout.maximumWidth: Math.max(0, replyCard.width - 16)
                            text: replyCard.author.login || "Пользователь"
                            avatarSource: replyCard.author.avatar || ""
                            badgeSource: replyCard.author.badge_url || ""
                            enabled: replyCard.author.id > 0
                            onClicked: window.openProfile(replyCard.author.id)
                        }

                        RoundButton {
                            Layout.fillWidth: true
                            visible: !!replyCard.currentComment.is_spoiler && !replyCard.deleted
                            text: replyCard.revealed ? "Скрыть спойлер" : "Показать спойлер"
                            onClicked: replyCard.revealed = !replyCard.revealed
                            background: Rectangle {
                                radius: height / 2
                                color: parent.hovered ? "#443556" : "#30243e"
                                border.color: "#574369"
                            }
                        }

                        Label {
                            Layout.fillWidth: true
                            visible: replyCard.deleted || !replyCard.currentComment.is_spoiler || replyCard.revealed
                            text: replyCard.deleted ? "Комментарий удалён" : replyCard.currentComment.message || ""
                            wrapMode: Text.Wrap
                            textFormat: Text.PlainText
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            visible: !replyCard.deleted

                            CommentVote { section: card.section; comment: replyCard.modelData }
                            Item { Layout.fillWidth: true }
                            AppToolButton {
                                text: "Ответить"
                                enabled: authManager.isLoggedIn || card.compact
                                onClicked: card.replyRequested(card.comment.id, replyCard.author)
                            }
                        }
                    }
                }
            }

            Button {
                visible: card.repliesExpanded && card.repliesPage < card.repliesPages
                text: "Ещё ответы"
                onClicked: card.loadReplies(card.repliesPage + 1)
            }
        }
    }
}
