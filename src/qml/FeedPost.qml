import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Anixart 1.0

Rectangle {
    id: root

    required property var article
    property bool expanded: false
    readonly property var blocks: article.payload?.blocks || article.repost_article?.payload?.blocks || []
    readonly property var images: collectImages()
    readonly property var author: article.author || article.repost_article?.author || {}
    readonly property var channel: article.channel || article.repost_article?.channel || {}
    property bool isSubscribed: channel.is_subscribed ?? false

    function collectImages() {
        const result = [];
        for (const block of blocks) {
            const items = block.data?.items || [];
            for (const item of items) {
                if (item?.url && /^https?:\/\//i.test(item.url)) result.push(item);
            }
        }
        return result;
    }

    function plain(text) {
        return String(text || "").replace(/<br\s*\/?\s*>/gi, "\n").replace(/<[^>]*>/g, "")
            .replace(/&nbsp;/g, " ").replace(/&quot;/g, '"').replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&amp;/g, "&");
    }

    function formatDate(ts) {
        if (!ts) return "";
        const d = new Date(ts * 1000);
        const months = ["янв.", "февр.", "марта", "апр.", "мая", "июня", "июля", "авг.", "сент.", "окт.", "нояб.", "дек."];
        const day = d.getDate();
        const mon = months[d.getMonth()] || "";
        const hours = ("0" + d.getHours()).slice(-2);
        const mins = ("0" + d.getMinutes()).slice(-2);
        return day + " " + mon + " в " + hours + ":" + mins;
    }

    implicitHeight: body.implicitHeight + 28
    radius: 16
    border.color: "#30263c"
    border.width: 1
    color: "#16131c"

    ColumnLayout {
        id: body
        anchors.fill: parent
        anchors.margins: 14
        spacing: 12

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            IdentityButton {
                Layout.maximumWidth: root.width * 0.7
                avatarSize: 36
                text: root.channel.title || root.author.login || "Запись"
                subtitle: root.formatDate(root.article.creation_date)
                avatarSource: root.channel.avatar || root.author.avatar || ""
                enabled: root.channel.id > 0 || root.author.id > 0
                onClicked: {
                    if (root.channel.id) window.openChannel(root.channel.id);
                    else window.openProfile(root.author.id);
                }
            }

            Item { Layout.fillWidth: true }

            Rectangle {
                visible: !!root.channel.id
                implicitHeight: 32
                implicitWidth: subText.implicitWidth + 24
                radius: 16
                color: root.isSubscribed ? "#3b3446" : "#2a2732"
                border.color: "#3f394a"
                border.width: 1

                Text {
                    id: subText
                    anchors.centerIn: parent
                    text: root.isSubscribed ? "Подписка" : "Подписаться"
                    font.pixelSize: 12
                    font.weight: Font.Medium
                    color: root.isSubscribed ? "#e6e1e5" : "#cfbcff"
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.isSubscribed = !root.isSubscribed;
                        if (authManager.isLoggedIn) {
                            anixApi.toggleSubscription(root.channel.id, authManager.token);
                        }
                    }
                }
            }

            Rectangle {
                implicitWidth: 32
                implicitHeight: 32
                radius: 16
                color: moreMouse.containsMouse ? "#2e2938" : "transparent"

                Text {
                    anchors.centerIn: parent
                    text: "⋮"
                    font.pixelSize: 18
                    font.bold: true
                    color: "#cac4d0"
                }

                MouseArea {
                    id: moreMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: postMenu.open()
                }

                Menu {
                    id: postMenu
                    popupType: Popup.Item
                    y: 34
                    MenuItem {
                        text: "Оценили"
                        enabled: root.article.id > 0
                        onTriggered: window.openVoters("article", root.article.id)
                    }
                    MenuItem { text: "↰ Репостнули" }
                    MenuItem { text: "⍗ Поделиться" }
                    MenuItem {
                        text: "📋 Скопировать ссылку"
                        onTriggered: {
                            if (root.article.id) {
                            }
                        }
                    }
                    MenuItem { text: "👁 Скрыть запись" }
                    MenuItem {
                        text: "Пожаловаться"
                        Material.foreground: "#ff897d"
                        enabled: root.article.id > 0 && !root.article.is_deleted
                        onTriggered: window.openReport("article", root.article.id,
                            "Запись • " + (root.channel.title || root.author.login || "№ " + root.article.id))
                    }
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 6

            Repeater {
                model: root.blocks

                delegate: ColumnLayout {
                    id: blockDelegate
                    required property var modelData
                    required property int index
                    readonly property string kind: modelData.type || modelData.name || ""
                    Layout.fillWidth: true
                    visible: blockText.text.length > 0 && (root.expanded || index < 4)

                    Text {
                        id: blockText
                        Layout.fillWidth: true
                        text: kind === "list" ? (modelData.data?.items || []).map(item => "• " + root.plain(item.content || item)).join("\n")
                            : root.plain(modelData.data?.text)
                        textFormat: Text.PlainText
                        wrapMode: Text.Wrap
                        maximumLineCount: root.expanded ? undefined : 4
                        elide: root.expanded ? Text.ElideNone : Text.ElideRight
                        color: kind === "header" ? "#ffffff" : "#eee6f4"
                        font.pixelSize: kind === "header" ? 16 : 14
                        font.bold: kind === "header"
                        lineHeight: 1.35
                    }
                }
            }

            Text {
                visible: !root.expanded && root.blocks.length > 0
                text: "Показать ещё"
                font.pixelSize: 13
                font.bold: true
                color: "#cfbcff"
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: window.openArticle(root.article)
                }
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: {
                if (root.images.length === 0) return 0;
                if (root.images.length === 1) return Math.min(360, Math.round(width * 0.58));
                if (root.images.length === 2) return Math.min(260, Math.round(width * 0.48));
                return 280;
            }
            visible: root.images.length > 0
            clip: true

            Rectangle {
                anchors.fill: parent
                visible: root.images.length === 1
                radius: 12
                color: "#211c2a"
                clip: true

                Image {
                    anchors.fill: parent
                    source: root.images.length > 0 ? root.images[0].url : ""
                    fillMode: Image.PreserveAspectCrop
                    mipmap: true
                    asynchronous: true
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: window.openFeedGallery(root.images, 0)
                }
            }

            Row {
                anchors.fill: parent
                visible: root.images.length === 2
                spacing: 6

                Repeater {
                    model: root.images.slice(0, 2)
                    delegate: Rectangle {
                        required property var modelData
                        required property int index
                        width: (parent.width - 6) / 2
                        height: parent.height
                        radius: 12
                        color: "#211c2a"
                        clip: true

                        Image {
                            anchors.fill: parent
                            source: modelData.url
                            fillMode: Image.PreserveAspectCrop
                            mipmap: true
                            asynchronous: true
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: window.openFeedGallery(root.images, index)
                        }
                    }
                }
            }

            Row {
                anchors.fill: parent
                visible: root.images.length >= 3
                spacing: 6

                Rectangle {
                    width: (parent.width - 6) / 2
                    height: parent.height
                    radius: 12
                    color: "#211c2a"
                    clip: true

                    Image {
                        anchors.fill: parent
                        source: root.images.length > 0 ? root.images[0].url : ""
                        fillMode: Image.PreserveAspectCrop
                        mipmap: true
                        asynchronous: true
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: window.openFeedGallery(root.images, 0)
                    }
                }

                Column {
                    width: (parent.width - 6) / 2
                    height: parent.height
                    spacing: 6

                    Rectangle {
                        width: parent.width
                        height: (parent.height - 6) / 2
                        radius: 12
                        color: "#211c2a"
                        clip: true

                        Image {
                            anchors.fill: parent
                            source: root.images.length > 1 ? root.images[1].url : ""
                            fillMode: Image.PreserveAspectCrop
                            mipmap: true
                            asynchronous: true
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: window.openFeedGallery(root.images, 1)
                        }
                    }

                    Rectangle {
                        width: parent.width
                        height: (parent.height - 6) / 2
                        radius: 12
                        color: "#211c2a"
                        clip: true

                        Image {
                            anchors.fill: parent
                            source: root.images.length > 2 ? root.images[2].url : ""
                            fillMode: Image.PreserveAspectCrop
                            mipmap: true
                            asynchronous: true
                        }

                        Rectangle {
                            anchors.fill: parent
                            visible: root.images.length > 3
                            color: "#75000000"

                            Text {
                                anchors.centerIn: parent
                                text: "+" + (root.images.length - 2)
                                font.pixelSize: 26
                                font.bold: true
                                color: "#ffffff"
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: window.openFeedGallery(root.images, 2)
                        }
                    }
                }
            }
        }

        Text {
            Layout.fillWidth: true
            visible: !!(root.author.login && root.channel.title && root.author.login !== root.channel.title)
            text: "Автор: " + (root.author.login || "")
            font.pixelSize: 12
            color: "#938f99"
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Rectangle {
                implicitHeight: 32
                implicitWidth: commentRow.implicitWidth + 24
                radius: 16
                color: commentMouse.containsMouse ? "#2e2938" : "#211f26"

                Row {
                    id: commentRow
                    anchors.centerIn: parent
                    spacing: 6
                    Text { text: "💬"; font.pixelSize: 12; anchors.verticalCenter: parent.verticalCenter }
                    Text {
                        text: String(root.article.comment_count ?? (root.article.comments_count ?? 0))
                        font.pixelSize: 13
                        font.bold: true
                        color: "#cac4d0"
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                MouseArea {
                    id: commentMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: window.openArticle(root.article)
                }
            }

            Rectangle {
                implicitHeight: 32
                implicitWidth: repostRow.implicitWidth + 24
                radius: 16
                color: repostMouse.containsMouse ? "#2e2938" : "#211f26"

                Row {
                    id: repostRow
                    anchors.centerIn: parent
                    spacing: 6
                    Text { text: "↰"; font.pixelSize: 14; font.bold: true; color: "#cac4d0"; anchors.verticalCenter: parent.verticalCenter }
                    Text {
                        text: String(root.article.repost_count ?? 0)
                        font.pixelSize: 13
                        font.bold: true
                        color: "#cac4d0"
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                MouseArea {
                    id: repostMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                }
            }

            Item { Layout.fillWidth: true }

            RowLayout {
                id: rating
                Layout.alignment: Qt.AlignVCenter
                property int voteValue: root.article.vote === 2 ? 1 : root.article.vote === 1 ? -1 : (root.article.my_vote ?? 0)
                property int voteCount: root.article.vote_count ?? root.article.votes ?? 0
                property bool pending: false
                property int errorCode: 0
                readonly property bool canVote: !pending && root.article.id > 0 && !root.article.is_deleted

                function vote(value) {
                    if (!canVote) return;
                    if (!authManager.isLoggedIn) {
                        openAuthDialog();
                        return;
                    }

                    errorCode = 0;
                    pending = true;
                    anixApi.sendArticleVote(root.article.id, value, authManager.token);
                }

                Connections {
                    target: anixApi

                    function onArticleVoteProcessed(articleId, vote, code) {
                        if (articleId !== root.article.id || !rating.pending) return;

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
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: commentPreviewRow.implicitHeight + 12
            visible: !!(root.article.top_comment || (root.article.comments_preview && root.article.comments_preview.length > 0))
            radius: 8
            color: "#181520"

            RowLayout {
                id: commentPreviewRow
                anchors.fill: parent
                anchors.margins: 8
                spacing: 8

                CircleImage {
                    Layout.preferredWidth: 22
                    Layout.preferredHeight: 22
                    source: root.article.top_comment?.author?.avatar || root.article.comments_preview?.[0]?.author?.avatar || ""
                }

                Text {
                    Layout.fillWidth: true
                    text: root.plain(root.article.top_comment?.message || root.article.comments_preview?.[0]?.message || "")
                    font.pixelSize: 13
                    color: "#e6e1e5"
                    elide: Text.ElideRight
                    maximumLineCount: 1
                }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: window.openArticle(root.article)
            }
        }
    }
}
