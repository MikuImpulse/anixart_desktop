import QtQuick
import QtQuick.Controls

Item {
    id: root

    property Flickable surface
    property bool busy: false
    property real distance: 0
    property bool tracking: false
    signal requested()

    visible: distance > 10 || indicator.running
    z: 5

    onSurfaceChanged: {
        tracking = false;
        distance = 0;
        minimumTime.stop();
        if (surface) {
            surface.boundsBehavior = Flickable.DragOverBounds;
            surface.boundsMovement = Flickable.StopAtBounds;
            if (surface.acceptedButtons !== undefined) surface.acceptedButtons = Qt.LeftButton;
        }
    }

    Connections {
        target: root.surface

        function onDraggingChanged() {
            if (root.surface.dragging) {
                root.tracking = (root.surface.atYBeginning || root.surface.verticalOvershoot < 0) && !indicator.running;
            } else if (root.tracking) {
                root.tracking = false;
                if (root.distance >= 58) {
                    minimumTime.restart();
                    root.requested();
                }
                root.distance = 0;
            }
        }

        function onVerticalOvershootChanged() {
            if (root.tracking) root.distance = Math.max(0, -root.surface.verticalOvershoot);
        }
    }

    Timer { id: minimumTime; interval: 380 }

    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        y: indicator.running ? 16 : Math.max(-height, Math.min(24, root.distance - height))
        width: 44
        height: 44
        radius: 22
        color: "#282233"
        border.color: "#4f4362"
        border.width: 1

        BusyIndicator {
            id: indicator
            anchors.fill: parent
            anchors.margins: 6
            running: minimumTime.running || root.busy && root.pending
        }

        Label {
            anchors.centerIn: parent
            visible: !indicator.running
            text: root.distance >= 58 ? "↻" : "↓"
            font.pixelSize: 18
            font.bold: true
            color: "#cfbcff"
        }
    }

    property bool pending: false
    onBusyChanged: {
        if (!busy) pending = false;
    }
}
