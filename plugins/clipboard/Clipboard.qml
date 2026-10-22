import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs

// Буфер обмена: поиск, «Закреплённые» и «История». Картинки — миниатюрами; щелчок или Enter — скопировать,
// при наведении — закрепить/открепить и удалить. Данные — clip.py json (история и clipboard-pins.json).
ColumnLayout {
    id: cb
    property var api
    property string pluginDir
    readonly property bool shown: api ? api.shown : false
    property var rows: []
    property string filter: ""
    property int sel: 0
    property bool confirmClear: false
    spacing: 8
    readonly property string py: pluginDir + "/clip.py"
    readonly property var shownRows: {
        var f = filter.toLowerCase().trim()
        return f ? rows.filter(r => r.text !== undefined ? r.text.toLowerCase().indexOf(f) >= 0 : (Tr.t("картинка") + " image").indexOf(f) >= 0) : rows
    }
    readonly property int pinnedCount: shownRows.filter(r => r.pinned).length

    function reload() { rd.running = false; rd.running = true }
    function act(args) { api.run(["python3", "-I", py].concat(args), ""); after.restart() }
    function copy(r) { api.run(["python3", "-I", py, "copy", r.id], ""); if (api) api.flash(String.fromCodePoint(0xF018F), Tr.t("Скопировано"), Theme.success); api.close() }
    Timer { id: after; interval: 250; onTriggered: cb.reload() }
    onShownChanged: if (shown) { filter = ""; search.text = ""; sel = 0; confirmClear = false; reload(); search.forceActiveFocus() }
    Component.onCompleted: { reload(); search.forceActiveFocus() }
    Process {
        id: rd
        command: ["python3", "-I", cb.py, "json"]
        stdout: StdioCollector { onStreamFinished: { try { cb.rows = JSON.parse(text) } catch (e) { cb.rows = [] } } }
    }
    FileView {   // новая запись в истории, пока панель открыта
        path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/glide-shell/clipboard.json"
        watchChanges: cb.shown
        printErrors: false
        onFileChanged: cb.reload()
    }

    // поиск
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: 36; radius: Theme.r(18)
        color: Theme.surface
        border.width: search.activeFocus ? 2 : 1
        border.color: search.activeFocus ? Theme.accent : sh.hovered ? Theme.outlineHover : Theme.outline
        Behavior on border.color { ColorAnimation { duration: Prefs.ms(140) } }
        HoverHandler { id: sh; cursorShape: Qt.IBeamCursor }
        TextInput {
            id: search
            anchors.fill: parent; anchors.leftMargin: 14; anchors.rightMargin: 14
            verticalAlignment: TextInput.AlignVCenter
            color: Theme.text; font.pixelSize: Theme.fs(13); clip: true
            onTextChanged: { cb.filter = text; cb.sel = 0 }
            Keys.onDownPressed: cb.sel = Math.min(cb.shownRows.length - 1, cb.sel + 1)
            Keys.onUpPressed: cb.sel = Math.max(0, cb.sel - 1)
            Keys.onReturnPressed: if (cb.shownRows.length) cb.copy(cb.shownRows[cb.sel])
            Text { visible: !search.text; anchors.verticalCenter: parent.verticalCenter
                   text: Tr.t("Поиск в буфере…"); color: Theme.textMuted; font.pixelSize: Theme.fs(13) }
        }
    }

    EmptyState {
        visible: cb.rows.length === 0
        Layout.fillWidth: true
        glyph: 0xF014C
        text: Tr.t("История пуста")
        hint: Tr.t("Скопированное появится здесь; важное можно закрепить")
    }

    Repeater {
        model: cb.shownRows.slice(0, 40)
        delegate: ColumnLayout {
            id: rw
            required property var modelData
            required property int index
            readonly property var r: modelData
            Layout.fillWidth: true
            spacing: 6
            Text {   // заголовки разделов
                visible: (rw.index === 0 && rw.r.pinned) || (rw.index === cb.pinnedCount && !rw.r.pinned && cb.pinnedCount > 0)
                text: rw.r.pinned ? Tr.t("ЗАКРЕПЛЁННЫЕ") : Tr.t("ИСТОРИЯ")
                color: Theme.textSecondary; font.pixelSize: Theme.fs(11); font.bold: true
                Layout.topMargin: rw.index === 0 ? 0 : 6
            }
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: rw.r.img ? 64 : Math.max(40, body.implicitHeight + 18)
                radius: Theme.r(14)
                color: ma.pressed ? Theme.surfacePressed : (rowHover.hovered || rw.index === cb.sel) ? Theme.surfaceHigh : Theme.surface
                border.color: rw.index === cb.sel ? Theme.accent : rw.r.pinned ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.4) : Theme.outline
                scale: ma.pressed ? 0.985 : 1
                Behavior on color { ColorAnimation { duration: Prefs.ms(120) } }
                Behavior on scale { NumberAnimation { duration: Prefs.ms(140); easing.type: Easing.OutBack } }
                MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onEntered: cb.sel = rw.index; onClicked: cb.copy(rw.r) }
                HoverHandler { id: rowHover }   // наведение на строку — и когда курсор над её кнопками
                Image {
                    visible: !!rw.r.img
                    x: 10; anchors.verticalCenter: parent.verticalCenter
                    width: 72; height: 48
                    source: rw.r.img ? "file://" + rw.r.img : ""
                    fillMode: Image.PreserveAspectCrop
                    sourceSize.width: 144; sourceSize.height: 96
                    asynchronous: true
                }
                Text {
                    id: body
                    x: rw.r.img ? 92 : 14
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - x - (rowHover.hovered || rw.r.pinned ? 76 : 14)
                    text: rw.r.img ? Tr.t("Картинка") + (rw.r.w ? "  " + rw.r.w + "×" + rw.r.h : "") : rw.r.text.replace(/\s*\n\s*/g, " ⏎ ")
                    color: rw.r.img ? Theme.textSecondary : Theme.text
                    font.pixelSize: Theme.fs(13)
                    wrapMode: Text.WrapAnywhere; maximumLineCount: 2; elide: Text.ElideRight
                    textFormat: Text.PlainText
                }
                Row {   // закрепить и удалить — при наведении (у закреплённых булавка видна всегда)
                    anchors.right: parent.right; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter
                    spacing: 2
                    IconBtn { visible: rowHover.hovered || rw.r.pinned; glyph: rw.r.pinned ? 0xF0403 : 0xF0931
                              on: rw.r.pinned; onClicked: cb.act([rw.r.pinned ? "unpin" : "pin", rw.r.id]) }
                    IconBtn { visible: rowHover.hovered; glyph: 0xF0156; onClicked: cb.act(["del", rw.r.id]) }
                }
            }
        }
    }

    Rectangle {   // очистить историю (закреплённые остаются) — со второго нажатия
        visible: cb.rows.some(r => !r.pinned)
        Layout.fillWidth: true
        implicitHeight: 34; radius: Theme.r(17)
        color: cb.confirmClear ? (clm.containsMouse ? Theme.errorHover : Theme.errorContainer)
                               : clm.pressed ? Theme.surfacePressed : clm.containsMouse ? Theme.surfaceHigher : Theme.surfaceHigh
        Behavior on color { ColorAnimation { duration: Prefs.ms(140) } }
        Text { anchors.centerIn: parent; font.pixelSize: Theme.fs(12)
               text: cb.confirmClear ? Tr.t("Ещё раз — очистить (закреплённые останутся)") : Tr.t("Очистить историю")
               color: cb.confirmClear ? Theme.errorText : Theme.text }
        MouseArea { id: clm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                    onClicked: { if (cb.confirmClear) { cb.confirmClear = false; cb.act(["clear"]) } else { cb.confirmClear = true; clrReset.restart() } } }
        Timer { id: clrReset; interval: 3000; onTriggered: cb.confirmClear = false }
    }

    component IconBtn: Rectangle {
        id: ib
        property int glyph
        property bool on: false
        readonly property bool hovered: ibm.containsMouse
        signal clicked()
        width: 30; height: 30; radius: 15
        color: ibm.pressed ? Theme.surfacePressed : ibm.containsMouse ? Theme.surfaceHigher : "transparent"
        scale: ibm.pressed ? 0.88 : 1
        Behavior on color { ColorAnimation { duration: Prefs.ms(120) } }
        Behavior on scale { NumberAnimation { duration: Prefs.ms(140); easing.type: Easing.OutBack } }
        Text { anchors.centerIn: parent; text: String.fromCodePoint(ib.glyph)
               color: ib.on ? Theme.accent : Theme.textSecondary; font.family: Prefs.iconFont; font.pixelSize: Theme.fs(15) }
        MouseArea { id: ibm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: ib.clicked() }
    }
}
