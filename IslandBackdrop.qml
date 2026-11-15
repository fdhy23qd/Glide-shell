import QtQuick
import Quickshell.Widgets

// Фон острова картинкой от плагина (api.island.backdrop, разрешение «island»; Core.islandBackdrop).
// Режим screen — «окно» в картинку размером с экран: видна та её часть, что под фигурой, поэтому, когда
// остров растёт под уведомление или музыку, он просто открывает больше той же картинки, ничего не растягивается.
// Режим fill — картинка целиком по размеру фигуры. Поверх — затемнение dim (текст должен читаться) и, если у
// острова один цвет (камера, микрофон, экран, плагин), — его лёгкий оттенок; несколько цветов рисует IslandTint
// выше. Кладётся первым ребёнком фигуры, внутри её обводки (1 px), со скруглением фигуры (ClippingRectangle).
// Новая картинка (плагин перечитывает файл, меняя ?запрос) показывается, только когда загрузилась: две Image по
// очереди — остров не мигает. (Две Image расписаны явно: inline-компонент не видит id файла.)
Item {
    id: bd
    property var spec: Core.islandBackdrop
    property real radius: 0
    property real screenX: 0          // где левый верхний угол фигуры на экране
    property real screenY: 0
    property real screenW: 0
    property real screenH: 0
    property color tint: "transparent"
    readonly property bool fill: !!spec && spec.mode === "fill"
    readonly property string want: spec ? spec.src : ""
    property int front: -1            // 0 — a, 1 — b, -1 — ещё ничего не загружено
    readonly property bool on: !!spec && front >= 0
    anchors.fill: parent
    anchors.margins: 1
    opacity: on ? 1 : 0
    visible: opacity > 0
    Behavior on opacity { NumberAnimation { duration: Prefs.ms(300) } }

    onWantChanged: load()
    Component.onCompleted: load()          // фон мог быть задан раньше, чем создан остров
    function load() {
        if (!want) { front = -1; a.source = ""; b.source = ""; return }
        var back = front === 0 ? b : a
        if (back.source.toString() === want) { if (back.status === Image.Ready) front = back === a ? 0 : 1; return }
        back.source = want
    }

    ClippingRectangle {   // скругление фигуры — обрезкой (маска MultiEffect здесь давала пустоту)
        id: content
        anchors.fill: parent
        radius: Math.max(0, bd.radius - 1)
        color: "transparent"
        Image {
            id: a
            visible: bd.front === 0
            asynchronous: true
            cache: false
            fillMode: Image.PreserveAspectCrop
            x: bd.fill ? 0 : -(bd.screenX + 1)
            y: bd.fill ? 0 : -(bd.screenY + 1)
            width: bd.fill ? bd.width : bd.screenW
            height: bd.fill ? bd.height : bd.screenH
            onStatusChanged: if (status === Image.Ready && source.toString() === bd.want) bd.front = 0
        }
        Image {
            id: b
            visible: bd.front === 1
            asynchronous: true
            cache: false
            fillMode: Image.PreserveAspectCrop
            x: bd.fill ? 0 : -(bd.screenX + 1)
            y: bd.fill ? 0 : -(bd.screenY + 1)
            width: bd.fill ? bd.width : bd.screenW
            height: bd.fill ? bd.height : bd.screenH
            onStatusChanged: if (status === Image.Ready && source.toString() === bd.want) bd.front = 1
        }
        Rectangle { anchors.fill: parent; color: Qt.rgba(0, 0, 0, bd.spec ? bd.spec.dim : 0) }
        Rectangle {
            anchors.fill: parent
            color: Qt.rgba(bd.tint.r, bd.tint.g, bd.tint.b, bd.tint.a > 0 ? 0.22 : 0)
            Behavior on color { ColorAnimation { duration: Prefs.ms(400) } }
        }
    }
}
