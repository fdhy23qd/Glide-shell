import QtQuick
import qs

// Элемент бара: «󰙨 ✓7/✗2» — итог последней проверки; щелчок — открыть раздел.
Item {
    id: chip
    property var api
    readonly property var last: api ? api.storage.get("summary", null) : null
    readonly property bool want: !!api && api.settings.showBar
    // подсказка при наведении: заголовок, строки «имя … значение», подпись
    readonly property var tip: !api ? null : {
        title: "Проверка API",
        rows: [
            { name: "Пройдено", value: last ? String(last.ok) : "—", color: Theme.success },
            { name: "Не прошло", value: last ? String(last.fail) : "—", color: last && last.fail ? Theme.error : Theme.textSecondary },
            { name: "Выдано разрешений", value: api.permissions.granted.length + " из " + api.permissions.requested.length },
            { name: "Служба, тиков", value: String(api.storage.get("serviceTicks", 0)) }
        ],
        hint: "Щелчок — открыть раздел проверки"
    }
    implicitWidth: row.implicitWidth
    implicitHeight: 24
    Row {
        id: row
        anchors.verticalCenter: parent.verticalCenter
        spacing: 4
        Text { text: "󰙨"; color: Theme.accent; font.family: chip.api ? chip.api.iconFont : ""; font.pixelSize: Theme.fs(14) }
        Text {
            text: chip.last ? "✓" + chip.last.ok + " ✗" + chip.last.fail : "—"
            color: chip.last && chip.last.fail ? Theme.warning : Theme.textVariant
            font.pixelSize: Theme.fs(12)
        }
    }
    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: chip.api.openCategory("apitest") }
}
