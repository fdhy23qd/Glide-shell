import QtQuick
import QtQuick.Layouts
import qs

// Раздел панели: сколько стаканов воды выпито сегодня (пример плагина из docs/API.md)
ColumnLayout {
    id: root
    property var api                     // приходит чуть позже создания — до этого null
    spacing: 12

    readonly property int goal: api ? api.settings.goal : 8
    // api.today меняется в полночь (и после сна) — счёт за вчера сам перестанет считаться
    readonly property int count: api && api.storage.get("day", "") === api.today ? api.storage.get("count", 0) : 0

    function add(n) {
        var c = Math.max(0, count + n)
        api.storage.set("day", api.today)
        api.storage.set("count", c)
        if (n > 0 && c === goal) api.flash("󰖌", "Норма воды выполнена!", Theme.success)
    }

    Text {
        text: root.count + " / " + root.goal + " стаканов"
        color: Theme.text
        font.pixelSize: Theme.fs(18)
    }
    Rectangle {   // прогресс
        Layout.fillWidth: true
        implicitHeight: 8
        radius: Theme.r(4)
        color: Theme.surface
        Rectangle {
            width: parent.width * Math.min(1, root.count / root.goal)
            height: parent.height
            radius: parent.radius
            color: Theme.accent
            Behavior on width { NumberAnimation { duration: Prefs.ms(200) } }
        }
    }
    RowLayout {
        spacing: 8
        Repeater {
            model: [{ t: "−1", d: -1 }, { t: "+1 стакан", d: 1 }]
            delegate: Rectangle {
                id: btn
                required property var modelData
                readonly property bool main: modelData.d > 0
                implicitWidth: label.implicitWidth + 24
                implicitHeight: 32
                radius: Theme.r(16)
                // состояния: наведение — светлее, нажатие — темнее и чуть меньше
                color: main ? (ma.pressed ? Theme.accentPressed : ma.containsMouse ? Theme.accentLight : Theme.accent)
                            : (ma.pressed ? Theme.surfacePressed : ma.containsMouse ? Theme.surfaceHigher : Theme.surfaceHigh)
                scale: ma.pressed ? 0.95 : 1
                Behavior on color { ColorAnimation { duration: Prefs.ms(120) } }
                Behavior on scale { NumberAnimation { duration: Prefs.ms(140); easing.type: Easing.OutBack } }
                Text {
                    id: label
                    anchors.centerIn: parent
                    text: btn.modelData.t
                    color: btn.main ? Theme.accentText : Theme.text
                    font.pixelSize: Theme.fs(13)
                }
                MouseArea {
                    id: ma
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.add(btn.modelData.d)
                }
            }
        }
    }
}
