import QtQuick
import qs

// Элемент бара: «󰙨 ✓7/✗2» — итог последней проверки; щелчок — открыть раздел.
Item {
    id: chip
    property var api
    readonly property var last: api ? api.storage.get("summary", null) : null
    readonly property bool want: !!api && api.settings.showBar
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
