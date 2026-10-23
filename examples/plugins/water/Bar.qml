import QtQuick
import qs

// Элемент бара: «󰖌 3/8»; щелчок — открыть раздел плагина
Item {
    id: chip
    property var api
    readonly property bool want: !!api && api.settings.showBar
    // подсказка при наведении (строка или {title, rows, hint})
    readonly property var tip: api ? { title: "Вода сегодня", rows: [{ name: "Выпито", value: count + " из " + api.settings.goal }],
                                       hint: "Щелчок — открыть раздел" } : null
    readonly property int count: api && api.storage.get("day", "") === api.today ? api.storage.get("count", 0) : 0

    implicitWidth: row.implicitWidth
    implicitHeight: 24
    Row {
        id: row
        anchors.verticalCenter: parent.verticalCenter
        spacing: 4
        Text { text: "󰖌"; color: Theme.accent; font.family: chip.api ? chip.api.iconFont : ""; font.pixelSize: Theme.fs(14) }
        Text { text: chip.count + "/" + (chip.api ? chip.api.settings.goal : 8); color: Theme.textVariant; font.pixelSize: Theme.fs(12) }
    }
    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: chip.api.openCategory("quick")
    }
}
