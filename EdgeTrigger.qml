import QtQuick
import Quickshell
import Quickshell.Wayland

// Зона вызова у правого края (вид «рейка у края», без бара): видимая полоска-таблетка; наведение растит её
// и через короткую паузу открывает панель. Состояние — в shell.qml (root).
PanelWindow {
    id: edge
    required property var root
    screen: root.panelScreen
    visible: !root.island && Prefs.edgeTrigger && !root.panelVisible
    anchors.right: true
    implicitWidth: 10
    implicitHeight: 240
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    WlrLayershell.namespace: "glide-edge"
    color: "transparent"

    onVisibleChanged: if (visible) pillIn.restart()

    Rectangle {   // почти прозрачная подложка: без неё пустые пиксели не ловят наведение
        anchors.fill: parent
        color: "#01000000"
    }

    Item {   // контейнер для появления, чтобы не трогать opacity самой полоски
        id: pillBox
        anchors.fill: parent
        visible: Prefs.edgePill
        NumberAnimation on opacity {   // плавно появляется снова после закрытия панели
            id: pillIn
            from: 0; to: 1; duration: Prefs.ms(400); easing.type: Easing.OutCubic
        }

        Rectangle {
            id: pill
            readonly property bool hot: edgeHover.hovered
            anchors.right: parent.right
            anchors.rightMargin: 2
            anchors.verticalCenter: parent.verticalCenter
            width: hot ? 6 : 3
            height: hot ? 120 : 56
            radius: width / 2
            color: hot ? Prefs.accent : Theme.textSecondary
            opacity: hot ? 0.95 : 0.35
            Behavior on width { NumberAnimation { duration: Prefs.ms(160); easing.type: Easing.OutCubic } }
            Behavior on height { NumberAnimation { duration: Prefs.ms(200); easing.type: Easing.OutBack } }
            Behavior on color { ColorAnimation { duration: Prefs.ms(160) } }
            Behavior on opacity { NumberAnimation { duration: Prefs.ms(160) } }
        }
    }

    HoverHandler {
        id: edgeHover
        onHoveredChanged: hovered ? edgeDelay.restart() : edgeDelay.stop()
    }
    Timer { id: edgeDelay; interval: Math.max(1, Prefs.hoverDelay); onTriggered: root.open() }
}
