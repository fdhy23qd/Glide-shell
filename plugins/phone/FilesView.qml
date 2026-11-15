import QtQuick
import QtQuick.Layouts
import Quickshell
import qs

// Файлы телефона через Glide Link (как SFTP у KDE Connect): хранилища → папки → файл. Щелчок по файлу — скачать
// в «Загрузки» и открыть; «Загрузить сюда» — файлы ПК в эту папку; корзина — удалить (файл или пустую папку).
ColumnLayout {
    id: fv
    property var device: null
    property var api: null
    signal back()
    spacing: 8

    property var trail: []            // [{name, path}] — путь от хранилища
    readonly property string path: trail.length ? trail[trail.length - 1].path : ""
    property var entries: []
    property bool loading: false
    property string error: ""
    property string busy: ""           // имя файла, который сейчас скачивается
    Component.onCompleted: load()

    function nf(code) { return String.fromCodePoint(code) }
    function size(n) {
        if (n < 1024) return n + Tr.t(" Б")
        if (n < 1048576) return (n / 1024).toFixed(0) + Tr.t(" КБ")
        if (n < 1073741824) return (n / 1048576).toFixed(1) + Tr.t(" МБ")
        return (n / 1073741824).toFixed(1) + Tr.t(" ГБ")
    }
    function load() {
        if (!device) return
        loading = true
        Phones.request({ cmd: "files-list", device: device.id, path: path }, r => {
            loading = false
            if (!r.ok) { error = r.error || Tr.t("Телефон не ответил"); entries = []; return }
            error = r.error === "no_permission" ? Tr.t("Разреши доступ к файлам: Glide Link на телефоне → «Файлы телефона»")
                  : r.error ? r.error : ""
            entries = r.entries || []
        })
    }
    function open(e) {
        if (e.dir) { trail = trail.concat([{ name: e.name, path: e.path }]); entries = []; load(); return }
        if (busy) return
        busy = e.name
        Phones.request({ cmd: "files-get", device: device.id, path: e.path, timeout: 600 }, r => {
            busy = ""
            if (r.ok && r.path) Quickshell.execDetached(["xdg-open", r.path])
            else error = Tr.t("Не скачалось: ") + (r.error || "")
        })
    }
    function up() {
        if (!trail.length) { back(); return }
        trail = trail.slice(0, -1)
        entries = []
        load()
    }
    function remove(e) {
        var go = () => Phones.request({ cmd: "files-delete", device: device.id, path: e.path }, r => {
            if (!r.ok) error = Tr.t("Не удалено: ") + (r.error || "")
            load()
        })
        if (api) api.confirm(Tr.t("Удалить «") + e.name + Tr.t("» с телефона?"), { yes: Tr.t("Удалить") }, ok => { if (ok) go() })
    }

    // ---- шапка ----
    RowLayout {
        Layout.fillWidth: true
        spacing: 8
        Btn { glyph: fv.nf(0xF004D); onClicked: fv.up() }
        Text {
            Layout.fillWidth: true
            text: fv.trail.length ? fv.trail.map(t => t.name).join(" / ") : Tr.t("Файлы телефона")
            color: Theme.text; font.pixelSize: Theme.fs(14); font.bold: true
            elide: Text.ElideLeft
        }
        Btn { glyph: fv.nf(0xF0450); onClicked: fv.load() }
        Btn {
            visible: fv.path !== ""
            glyph: fv.nf(0xF0552); label: Tr.t("Загрузить сюда")
            onClicked: { Phones.act(fv.device, "upload", fv.path); if (fv.api) fv.api.flash("󰄜", Tr.t("Выбери файлы — они уйдут в эту папку телефона")) }
        }
    }
    Text {
        visible: !!fv.error
        Layout.fillWidth: true
        text: fv.error
        color: Theme.error; font.pixelSize: Theme.fs(12)
        wrapMode: Text.Wrap
    }
    Text {
        visible: fv.loading || !!fv.busy
        text: fv.busy ? Tr.t("Скачиваю «") + fv.busy + "»…" : Tr.t("Спрашиваю телефон…")
        color: Theme.textMuted; font.pixelSize: Theme.fs(12)
    }

    Repeater {
        model: fv.entries
        delegate: Rectangle {
            id: row
            required property var modelData
            Layout.fillWidth: true
            implicitHeight: 44
            radius: Theme.radiusMd
            color: rm.containsMouse ? Theme.surfaceHigher : Theme.surfaceHigh
            Behavior on color { ColorAnimation { duration: Prefs.ms(120) } }
            Text {
                x: 12; anchors.verticalCenter: parent.verticalCenter
                text: fv.nf(row.modelData.dir ? (fv.path === "" ? 0xF02CA : 0xF024B) : 0xF0214)
                color: row.modelData.dir ? Theme.accent : Theme.textVariant
                font.family: Prefs.iconFont; font.pixelSize: Theme.fs(18)
            }
            Text {
                x: 42; anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 42 - 120
                text: row.modelData.name
                color: Theme.text; font.pixelSize: Theme.fs(13)
                elide: Text.ElideMiddle
            }
            Text {
                anchors.right: del.left; anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                visible: !row.modelData.dir
                text: fv.size(row.modelData.size || 0)
                color: Theme.textMuted; font.pixelSize: Theme.fs(11)
            }
            MouseArea { id: rm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: fv.open(row.modelData) }
            Text {   // удалить (не для хранилищ)
                id: del
                anchors.right: parent.right; anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                visible: fv.path !== ""
                text: fv.nf(0xF0A7A)
                color: dm.containsMouse ? Theme.error : Theme.textMuted
                font.family: Prefs.iconFont; font.pixelSize: Theme.fs(16)
                MouseArea { id: dm; anchors.fill: parent; anchors.margins: -6; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: fv.remove(row.modelData) }
            }
        }
    }
    Text {
        visible: !fv.loading && !fv.error && fv.entries.length === 0
        text: Tr.t("Пусто")
        color: Theme.textMuted; font.pixelSize: Theme.fs(12)
    }

    component Btn: Rectangle {
        id: b
        property string glyph
        property string label: ""
        signal clicked()
        implicitWidth: label ? row2.implicitWidth + 20 : 34
        implicitHeight: 34
        radius: Theme.radiusMd
        color: bm.pressed ? Theme.surfacePressed : bm.containsMouse ? Theme.surfaceHigher : Theme.surfaceHigh
        Behavior on color { ColorAnimation { duration: Prefs.ms(120) } }
        Row {
            id: row2
            anchors.centerIn: parent
            spacing: 6
            Text { anchors.verticalCenter: parent.verticalCenter; text: b.glyph; color: Theme.accent; font.family: Prefs.iconFont; font.pixelSize: Theme.fs(16) }
            Text { visible: !!b.label; anchors.verticalCenter: parent.verticalCenter; text: b.label; color: Theme.text; font.pixelSize: Theme.fs(12) }
        }
        MouseArea { id: bm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: b.clicked() }
    }
}
