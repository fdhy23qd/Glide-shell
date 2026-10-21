import QtQuick

// Пустое место в разделе («Уведомлений нет», «Ничего не найдено»): значок в круге, подпись и подсказка.
// Проявляется и чуть всплывает каждый раз, когда становится видимым.
Item {
    id: es
    property int glyph: 0xF0219
    property string text: ""
    property string hint: ""
    property bool compact: false      // в строку — для узких мест (подпись справа от значка)

    implicitWidth: 240
    implicitHeight: (compact ? row.implicitHeight : col.implicitHeight) + (compact ? 8 : 20)

    onVisibleChanged: if (visible) appear.restart()
    Component.onCompleted: if (visible) appear.restart()
    ParallelAnimation {
        id: appear
        NumberAnimation { target: body; property: "opacity"; from: 0; to: 1; duration: Prefs.ms(220) }
        NumberAnimation { target: body; property: "y"; from: es.compact ? 4 : 8; to: es.compact ? 4 : 10; duration: Prefs.ms(260); easing.type: Easing.OutCubic }
    }

    Item {
        id: body
        width: es.width
        y: es.compact ? 4 : 10
        height: es.compact ? row.implicitHeight : col.implicitHeight

        Column {
            id: col
            visible: !es.compact
            width: parent.width
            spacing: 8
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 44; height: 44; radius: 22
                color: Theme.surface
                border.color: Theme.outline
                Text {
                    anchors.centerIn: parent
                    text: String.fromCodePoint(es.glyph)
                    color: Theme.textMuted
                    font.family: Prefs.iconFont; font.pixelSize: Theme.fs(20)
                }
            }
            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: es.text
                color: Theme.textSecondary
                font.pixelSize: Theme.fs(13)
                wrapMode: Text.WordWrap
            }
            Text {
                visible: es.hint !== ""
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: es.hint
                color: Theme.textMuted
                font.pixelSize: Theme.fs(11)
                wrapMode: Text.WordWrap
            }
        }
        Row {
            id: row
            visible: es.compact
            x: 4
            spacing: 10
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: String.fromCodePoint(es.glyph)
                color: Theme.textMuted
                font.family: Prefs.iconFont; font.pixelSize: Theme.fs(16)
            }
            Column {
                anchors.verticalCenter: parent.verticalCenter
                width: es.width - 40
                Text { width: parent.width; text: es.text; color: Theme.textSecondary; font.pixelSize: Theme.fs(12); wrapMode: Text.WordWrap }
                Text { visible: es.hint !== ""; width: parent.width; text: es.hint; color: Theme.textMuted; font.pixelSize: Theme.fs(11); wrapMode: Text.WordWrap }
            }
        }
    }
}
