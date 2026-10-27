import QtQuick
import QtQuick.Layouts
import qs
import "emoji.js" as E

// Смайлики: поиск по словам (ru/en) и сетка; щелчок — в буфер. В общем поиске — «:слово» (Search.qml).
ColumnLayout {
    id: em
    property var api
    readonly property bool shown: api ? api.shown : false
    property string filter: ""
    readonly property var list: filter.trim() ? E.find(filter) : E.LIST
    spacing: 8
    onShownChanged: if (shown) { filter = ""; field.text = "" }

    Rectangle {
        Layout.fillWidth: true
        implicitHeight: 36; radius: Theme.r(18)
        color: Theme.surface
        border.width: field.activeFocus ? 2 : 1
        border.color: field.activeFocus ? Theme.accent : fh.hovered ? Theme.outlineHover : Theme.outline
        Behavior on border.color { ColorAnimation { duration: Prefs.ms(150) } }
        HoverHandler { id: fh; cursorShape: Qt.IBeamCursor }
        TextInput {
            id: field
            anchors.fill: parent; anchors.leftMargin: 14; anchors.rightMargin: 14
            verticalAlignment: TextInput.AlignVCenter
            color: Theme.text; font.pixelSize: Theme.fs(13); clip: true
            onTextChanged: em.filter = text
            onAccepted: if (em.list.length) em.pick(em.list[0][0])
            Text { visible: !field.text; anchors.verticalCenter: parent.verticalCenter
                   text: Tr.t("Найти смайлик: огонь, сердце, спасибо…"); color: Theme.textMuted; font.pixelSize: Theme.fs(13) }
        }
    }
    function pick(s) {
        if (!api) return
        api.copy(s)
        api.flash(s, Tr.t("Скопировано"), Theme.success)
        api.close()
    }
    EmptyState {
        visible: em.list.length === 0
        Layout.fillWidth: true
        compact: true
        glyph: 0xF0349
        text: Tr.t("Ничего не найдено")
    }
    Flow {
        Layout.fillWidth: true
        spacing: 4
        Repeater {
            model: em.list.slice(0, 120)
            delegate: Rectangle {
                id: cell
                required property var modelData
                width: 40; height: 40; radius: Theme.r(10)
                color: cm.pressed ? Theme.surfacePressed : cm.containsMouse ? Theme.surfaceHigher : "transparent"
                scale: cm.pressed ? 0.9 : 1
                Behavior on color { ColorAnimation { duration: Prefs.ms(100) } }
                Behavior on scale { NumberAnimation { duration: Prefs.ms(120); easing.type: Easing.OutBack } }
                Text { anchors.centerIn: parent; text: cell.modelData[0]; font.pixelSize: Theme.fs(22) }
                MouseArea { id: cm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: em.pick(cell.modelData[0]) }
            }
        }
    }
}
