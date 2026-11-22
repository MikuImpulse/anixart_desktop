import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Dialogs as Dialogs
import QtQuick.Layouts
import QtCore
import Anixart 1.0

Window {
    id: root

    flags: Qt.Window | Qt.FramelessWindowHint
    color: "#17131c"
    Material.theme: Material.Dark
    Material.accent: "#cfbcff"
    title: mediaTitle || "Изображения"

    property var images: []
    property int index: 0
    property string mediaTitle: ""
    property string mediaSubtitle: ""
    property real zoom: 1
    property real panX: 0
    property real panY: 0
    property point dragStart
    property bool saving: false
    property string saveMessage: ""
    readonly property url mediaSource: visible ? (images[index]?.url || "") : ""

    function resetTransform() {
        zoom = 1;
        panX = 0;
        panY = 0;
    }

    function zoomBy(factor) {
        zoom = Math.min(6, Math.max(1, zoom * factor));
        if (zoom === 1) resetTransform();
    }

    function showMedia(url, title, subtitle) {
        showImages([{url: url}], 0, title || "", subtitle || "");
    }

    function showImages(items, initialIndex, title, subtitle) {
        if (!items || !items.length) return;
        images = items;
        index = Math.max(0, Math.min(initialIndex, items.length - 1));
        mediaTitle = title;
        mediaSubtitle = subtitle;
        if (!saving) saveMessage = "";
        resetTransform();
        if (transientParent) screen = transientParent.screen;
        showFullScreen();
        requestActivate();
    }

    function step(offset) {
        const next = index + offset;
        if (next < 0 || next >= images.length) return;
        index = next;
        resetTransform();
        if (!saving) saveMessage = "";
    }

    function chooseDestination() {
        const source = mediaSource.toString();
        const name = mediaTitle.replace(/[\\/:*?"<>|]/g, "_").trim() || "Изображение";
        const suffix = /\.([a-z0-9]{1,8})(?:[?#]|$)/i.exec(source);
        const folder = saveDialog.currentFolder.toString().replace(/\/$/, "");
        saveDialog.selectedFile = folder + "/" + encodeURIComponent(name + (images.length > 1 ? " " + (index + 1) : "")
            + (suffix ? "." + suffix[1] : ""));
        saveDialog.open();
    }

    WheelHandler {
        target: null
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        acceptedModifiers: Qt.ControlModifier
        onWheel: event => {
            const delta = event.angleDelta.y || event.pixelDelta.y * 3;
            if (!delta) return;

            root.zoomBy(Math.pow(1.2, delta / 120));
            event.accepted = true;
        }
    }

    Item {
        id: viewport
        anchors.fill: parent
        anchors.topMargin: 54
        anchors.bottomMargin: 62
        clip: true

        Image {
            id: image
            objectName: "mediaViewerImage"
            width: Math.min(implicitWidth || viewport.width, viewport.width - 26)
            height: Math.min(implicitHeight || viewport.height, viewport.height - 26)
            anchors.centerIn: parent
            anchors.horizontalCenterOffset: root.panX
            anchors.verticalCenterOffset: root.panY
            source: root.mediaSource
            scale: root.zoom
            fillMode: Image.PreserveAspectFit
            mipmap: true
            asynchronous: true
        }

        BusyIndicator {
            anchors.centerIn: parent
            running: image.status === Image.Loading
        }

        Label {
            anchors.centerIn: parent
            visible: image.status === Image.Error
            text: "Не удалось загрузить изображение"
        }

        DragHandler {
            target: null
            enabled: root.zoom > 1
            cursorShape: active ? Qt.ClosedHandCursor : Qt.OpenHandCursor

            onActiveChanged: {
                if (active) root.dragStart = Qt.point(root.panX, root.panY);
            }

            onActiveTranslationChanged: {
                if (!active) return;
                root.panX = Math.max(-image.width * root.zoom / 2, Math.min(image.width * root.zoom / 2,
                    root.dragStart.x + activeTranslation.x));
                root.panY = Math.max(-image.height * root.zoom / 2, Math.min(image.height * root.zoom / 2,
                    root.dragStart.y + activeTranslation.y));
            }
        }

        TapHandler {
            onDoubleTapped: {
                if (root.zoom > 1) root.resetTransform();
                else root.zoomBy(2);
            }
        }

        ViewerButton {
            anchors.left: parent.left
            anchors.leftMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            visible: root.images.length > 1
            enabled: root.index > 0
            asset: "back"
            description: "Предыдущее изображение"
            onClicked: root.step(-1)
        }

        ViewerButton {
            anchors.right: parent.right
            anchors.rightMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            visible: root.images.length > 1
            enabled: root.index + 1 < root.images.length
            asset: "back"
            rotation: 180
            description: "Следующее изображение"
            onClicked: root.step(1)
        }
    }

    RowLayout {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: 12

        Label {
            text: (root.index + 1) + " / " + root.images.length
            visible: root.images.length > 1
        }

        Item { Layout.fillWidth: true }

        ViewerButton {
            asset: "close"
            description: "Закрыть"
            onClicked: root.close()
        }
    }

    RowLayout {
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: 12

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 1
            Label {
                Layout.fillWidth: true
                text: root.mediaTitle
                elide: Text.ElideRight
            }
            Label {
                Layout.fillWidth: true
                text: root.saveMessage || root.mediaSubtitle
                color: "#c2b3cd"
                elide: Text.ElideRight
            }
        }

        AppToolButton {
            text: Math.round(root.zoom * 100) + "%"
            ToolTip.text: "Сбросить масштаб"
            ToolTip.visible: hovered
            onClicked: root.resetTransform()
        }

        ViewerButton {
            asset: "download"
            description: "Сохранить изображение"
            enabled: !root.saving && image.status === Image.Ready
            onClicked: root.chooseDestination()
        }
    }

    Shortcut { sequence: "Escape"; enabled: !saveDialog.visible; onActivated: root.close() }
    Shortcut { sequence: "Left"; enabled: !saveDialog.visible; onActivated: root.step(-1) }
    Shortcut { sequence: "Right"; enabled: !saveDialog.visible; onActivated: root.step(1) }

    CircleImage {
        id: imageSaver
        visible: false
        onOriginalSaved: error => {
            root.saving = false;
            root.saveMessage = error || "Изображение сохранено";
        }
    }

    Dialogs.FileDialog {
        id: saveDialog
        title: "Сохранить изображение"
        acceptLabel: "Сохранить"
        rejectLabel: "Отмена"
        fileMode: Dialogs.FileDialog.SaveFile
        currentFolder: StandardPaths.writableLocation(StandardPaths.DownloadLocation)
        onAccepted: {
            root.saving = true;
            root.saveMessage = "";
            imageSaver.saveOriginal(root.mediaSource, selectedFile);
            root.requestActivate();
        }
        onRejected: root.requestActivate()
    }

    component ViewerButton: ToolButton {
        id: button
        property string asset
        property string description
        implicitWidth: 38
        implicitHeight: 38
        icon.source: "qrc:/assets/icons/" + asset + ".svg"
        icon.color: "#ede1f5"
        icon.width: 17
        icon.height: 17
        Accessible.name: description
        ToolTip.text: description
        ToolTip.visible: hovered
        background: Rectangle {
            radius: 9
            color: button.hovered || button.activeFocus ? "#40314c" : "transparent"
        }
    }
}
