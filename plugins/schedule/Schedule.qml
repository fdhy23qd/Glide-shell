import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs

// Расписание пар (tools/glide-schedule.py: campus.syktsu.ru, кэш 3 ч). Неделя по дням, сегодня выбрано
// сразу; идущая пара — акцентом с «до …», следующая — «через …». Группа и подгруппа — в Prefs.
ColumnLayout {
    id: sc
    property var api
    readonly property bool shown: api ? api.shown : false
    readonly property string group: Prefs.scheduleGroup
    readonly property int subgroup: Prefs.scheduleSubgroup
    property string which: "now"          // now | next
    property var sched: null           // не «data»: так называется список детей любого Item
    property bool loading: false
    property int day: -1                  // выбранный день (индекс в sched.days)
    property date now: new Date()
    property bool editing: false
    spacing: 10

    function nf(code) { return String.fromCodePoint(code) }
    function load(force) {
        if (!group || proc.running) return
        loading = true
        proc.command = ["python3", "-I", Quickshell.shellDir + "/tools/glide-schedule.py", group, which].concat(force ? ["--force"] : [])
        proc.running = true
    }
    onShownChanged: if (shown) { now = new Date(); load(false) }
    onGroupChanged: { sched = null; day = -1; load(false) }
    onWhichChanged: { day = -1; load(false) }
    Component.onCompleted: load(false)

    Process {
        id: proc
        stdout: StdioCollector {
            onStreamFinished: {
                sc.loading = false
                try { sc.sched = JSON.parse(text) } catch (e) { sc.sched = { error: Tr.t("не удалось разобрать ответ") } }
                if (sc.day < 0 && sc.sched && sc.sched.days) {
                    var t = sc.sched.days.findIndex(d => d.today)
                    sc.day = t >= 0 ? t : 0
                }
            }
        }
    }
    Timer { running: sc.shown; interval: 30000; repeat: true; onTriggered: sc.now = new Date() }   // «идёт / через …»

    readonly property var days: sched && sched.days ? sched.days : []
    readonly property var lessons: {
        var d = days[day]
        if (!d) return []
        return d.lessons.filter(l => !sc.subgroup || !l.subgroup || l.subgroup === sc.subgroup)
    }
    // минуты от полуночи и статус пары относительно «сейчас» (только для сегодняшнего дня)
    function mins(t) { var p = t.split(":"); return +p[0] * 60 + +p[1] }
    function status(l) {
        var d = days[day]
        if (!d || !d.today) return ""
        var n = now.getHours() * 60 + now.getMinutes(), a = mins(l.start), b = mins(l.end)
        if (n >= a && n < b) return "now"
        if (n < a) {
            var first = lessons.find(x => mins(x.start) > n)
            return first === l ? "next" : ""
        }
        return "past"
    }
    function untilStart(t) {   // не «left»: имя занято у Item
        var m = mins(t) - (now.getHours() * 60 + now.getMinutes())
        return m >= 60 ? Math.floor(m / 60) + Tr.t(" ч ") + (m % 60) + Tr.t(" мин") : m + Tr.t(" мин")
    }

    // ---- группа, неделя, эта / следующая ----
    RowLayout {
        Layout.fillWidth: true
        spacing: 8
        Rectangle {   // группа: клик — сменить
            implicitWidth: grpRow.implicitWidth + 20; implicitHeight: 30; radius: Theme.r(15)
            color: grpMouse.pressed ? Theme.surfacePressed : grpMouse.containsMouse ? Theme.surfaceHigher : Theme.surfaceHigh
            scale: grpMouse.pressed ? 0.95 : 1
            Behavior on color { ColorAnimation { duration: Prefs.ms(120) } }
            Behavior on scale { NumberAnimation { duration: Prefs.ms(140); easing.type: Easing.OutBack } }
            visible: !sc.editing
            Row {
                id: grpRow
                anchors.centerIn: parent
                spacing: 6
                Text { anchors.verticalCenter: parent.verticalCenter; text: sc.nf(0xF0474); color: Theme.accent; font.family: Prefs.iconFont; font.pixelSize: Theme.fs(14) }
                Text { anchors.verticalCenter: parent.verticalCenter; text: sc.group || Tr.t("Указать группу"); color: Theme.text; font.pixelSize: Theme.fs(12); font.bold: true }
            }
            MouseArea { id: grpMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: { sc.editing = true; grpIn.text = sc.group; grpIn.forceActiveFocus() } }
        }
        Rectangle {
            visible: sc.editing
            Layout.fillWidth: true
            implicitHeight: 30; radius: Theme.r(15)
            color: Theme.surface
            border.color: Theme.accent
            border.width: grpIn.activeFocus ? 2 : 1   // поле появляется уже в фокусе
            HoverHandler { cursorShape: Qt.IBeamCursor }
            TextInput {
                id: grpIn
                anchors.left: parent.left; anchors.right: parent.right
                anchors.leftMargin: 12; anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                color: Theme.text; font.pixelSize: Theme.fs(12)
                Keys.onReturnPressed: { if (sc.api) sc.api.setPref("scheduleGroup", text.trim()); sc.editing = false }
                Keys.onEnterPressed: { if (sc.api) sc.api.setPref("scheduleGroup", text.trim()); sc.editing = false }
                Keys.onEscapePressed: (e) => { sc.editing = false; e.accepted = true }
                Text { anchors.verticalCenter: parent.verticalCenter; visible: !grpIn.text; text: Tr.t("Номер группы, например 211-ИВТ → Enter"); color: Theme.textMuted; font.pixelSize: Theme.fs(12) }
            }
        }
        Text {
            visible: !sc.editing
            Layout.fillWidth: true
            text: sc.sched && sc.sched.week ? sc.sched.week.replace(/\s*\(.*\)/, "") : ""
            color: Theme.textSecondary; font.pixelSize: Theme.fs(11)
            elide: Text.ElideRight
        }
        Row {   // эта / следующая неделя
            visible: !sc.editing && !!sc.group
            spacing: 4
            Repeater {
                model: [{ v: "now", l: Tr.t("Эта") }, { v: "next", l: Tr.t("След.") }]
                delegate: Rectangle {
                    required property var modelData
                    readonly property bool on: sc.which === modelData.v
                    width: wl.implicitWidth + 18; height: 26; radius: Theme.r(13)
                    color: on ? (wm.containsMouse ? Theme.accentLight : Theme.accent) : wm.pressed ? Theme.surfacePressed : wm.containsMouse ? Theme.surfaceHigher : Theme.surfaceHigh
                    scale: wm.pressed ? 0.93 : 1
                    Behavior on color { ColorAnimation { duration: Prefs.ms(120) } }
                    Behavior on scale { NumberAnimation { duration: Prefs.ms(140); easing.type: Easing.OutBack } }
                    Text { id: wl; anchors.centerIn: parent; text: modelData.l; color: parent.on ? Theme.accentText : Theme.text; font.pixelSize: Theme.fs(11) }
                    MouseArea { id: wm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: sc.which = modelData.v }
                }
            }
        }
    }

    Text {   // ошибка, пусто или загрузка
        visible: !sc.group || (sc.sched && sc.sched.error) || (sc.loading && !sc.sched)
        Layout.fillWidth: true
        text: !sc.group ? Tr.t("Укажи номер группы — расписание возьмётся с campus.syktsu.ru")
            : !sc.sched ? Tr.t("Загружаю расписание…") : Tr.t("Не удалось загрузить: ") + (sc.sched.error || "")
        color: Theme.textSecondary; font.pixelSize: Theme.fs(12)
        wrapMode: Text.WordWrap
    }

    // ---- дни недели ----
    Row {
        visible: sc.days.length > 0
        Layout.fillWidth: true
        spacing: 4
        Repeater {
            model: sc.days
            delegate: Rectangle {
                id: dc
                Behavior on border.color { ColorAnimation { duration: Prefs.ms(140) } }
                required property var modelData
                required property int index
                readonly property bool on: sc.day === index
                readonly property int count: modelData.lessons.filter(l => !sc.subgroup || !l.subgroup || l.subgroup === sc.subgroup).length
                width: (parent.width - 4 * (sc.days.length - 1)) / Math.max(1, sc.days.length)
                height: 44; radius: Theme.radiusSm
                color: on ? (dm.containsMouse ? Theme.accentLight : Theme.accent) : dm.pressed ? Theme.surfacePressed : dm.containsMouse ? Theme.surfaceHigher : Theme.surfaceHigh
                scale: dm.pressed ? 0.94 : 1
                Behavior on color { ColorAnimation { duration: Prefs.ms(120) } }
                Behavior on scale { NumberAnimation { duration: Prefs.ms(140); easing.type: Easing.OutBack } }
                border.color: modelData.today && !on ? Theme.accent : "transparent"
                Column {
                    anchors.centerIn: parent
                    Text {
                        Behavior on color { ColorAnimation { duration: Prefs.ms(140) } }
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: dc.modelData.name.slice(0, 2)
                        color: dc.on ? Theme.accentText : Theme.text; font.pixelSize: Theme.fs(12); font.bold: true
                    }
                    Text {
                        Behavior on color { ColorAnimation { duration: Prefs.ms(140) } }
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: dc.modelData.date.slice(0, 5)
                        color: dc.on ? Theme.accentText : dc.count ? Theme.textSecondary : Theme.textFaint
                        font.pixelSize: Theme.fs(10)
                    }
                }
                MouseArea { id: dm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: sc.day = dc.index }
            }
        }
    }

    Text {
        visible: sc.days.length > 0 && sc.lessons.length === 0
        Layout.fillWidth: true
        Layout.topMargin: 8; Layout.bottomMargin: 8
        horizontalAlignment: Text.AlignHCenter
        text: Tr.t("Пар нет")
        color: Theme.textMuted; font.pixelSize: Theme.fs(13)
    }

    // ---- пары выбранного дня ----
    Repeater {
        model: sc.lessons
        delegate: Rectangle {
            id: lc
            required property var modelData
            readonly property string st: sc.status(modelData)
            Layout.fillWidth: true
            implicitHeight: info.implicitHeight + 20
            radius: Theme.radiusMd
            color: st === "now" ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.16) : Theme.surface
            border.color: st === "now" ? Theme.accent : st === "next" ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.45) : Theme.outline
            opacity: st === "past" ? 0.5 : 1
            Column {   // номер и время
                x: 12; y: 10
                width: 52
                Text { text: lc.modelData.n + Tr.t(" пара"); color: Theme.textMuted; font.pixelSize: Theme.fs(10) }
                Text { text: lc.modelData.start; color: Theme.text; font.pixelSize: Theme.fs(14); font.bold: true; font.features: ({ "tnum": 1 }) }
                Text { text: lc.modelData.end; color: Theme.textSecondary; font.pixelSize: Theme.fs(11); font.features: ({ "tnum": 1 }) }
            }
            Column {
                id: info
                x: 72; y: 10
                width: parent.width - 72 - 12
                spacing: 2
                Text {
                    visible: lc.st === "now" || lc.st === "next"
                    text: lc.st === "now" ? Tr.t("идёт · до ") + lc.modelData.end : Tr.t("следующая · через ") + sc.untilStart(lc.modelData.start)
                    color: Theme.accent; font.pixelSize: Theme.fs(11); font.bold: true
                }
                Text {
                    width: parent.width
                    text: lc.modelData.title
                    color: Theme.text; font.pixelSize: Theme.fs(13); font.bold: true
                    wrapMode: Text.WordWrap
                }
                Text {
                    width: parent.width
                    text: [lc.modelData.kind, lc.modelData.room ? Tr.t("ауд. ") + lc.modelData.room : "",
                           lc.modelData.subgroup ? Tr.t("подгр. ") + lc.modelData.subgroup : ""].filter(x => x).join(" · ")
                    color: Theme.textVariant; font.pixelSize: Theme.fs(12)
                    wrapMode: Text.WordWrap
                }
                Text {
                    width: parent.width
                    visible: text !== ""
                    text: lc.modelData.teacher
                    color: Theme.textSecondary; font.pixelSize: Theme.fs(11)
                    elide: Text.ElideRight
                }
            }
        }
    }

    // ---- подгруппа и обновление ----
    RowLayout {
        visible: sc.days.length > 0
        Layout.fillWidth: true
        spacing: 6
        Text { text: Tr.t("Подгруппа"); color: Theme.textSecondary; font.pixelSize: Theme.fs(11) }
        Repeater {
            model: [{ v: 0, l: Tr.t("все") }, { v: 1, l: "1" }, { v: 2, l: "2" }]
            delegate: Rectangle {
                Behavior on border.color { ColorAnimation { duration: Prefs.ms(140) } }
                required property var modelData
                readonly property bool on: sc.subgroup === modelData.v
                implicitWidth: sl.implicitWidth + 18; implicitHeight: 24; radius: Theme.r(12)
                color: on ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, sm.containsMouse ? 0.32 : 0.22)
                          : sm.pressed ? Theme.surfacePressed : sm.containsMouse ? Theme.surfaceHigher : Theme.surfaceHigh
                scale: sm.pressed ? 0.92 : 1
                Behavior on color { ColorAnimation { duration: Prefs.ms(120) } }
                Behavior on scale { NumberAnimation { duration: Prefs.ms(140); easing.type: Easing.OutBack } }
                border.color: on ? Theme.accent : "transparent"
                Text { id: sl; anchors.centerIn: parent; text: modelData.l; color: Theme.text; font.pixelSize: Theme.fs(11) }
                MouseArea { id: sm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: if (sc.api) sc.api.setPref("scheduleSubgroup", modelData.v) }
            }
        }
        Item { Layout.fillWidth: true }
        Text {
            text: sc.loading ? Tr.t("обновляю…") : sc.sched && sc.sched.stale ? Tr.t("нет сети, старое") : sc.sched && sc.sched.updated ? Tr.t("сайт: ") + sc.sched.updated.slice(0, 16) : ""
            color: Theme.textMuted; font.pixelSize: Theme.fs(10)
        }
        Rectangle {   // обновить с сайта
            Behavior on color { ColorAnimation { duration: Prefs.ms(140) } }
            implicitWidth: 26; implicitHeight: 26; radius: Theme.r(13)
            // пока идёт загрузка — недоступна
            enabled: !sc.loading
            opacity: enabled ? 1 : Theme.disabledOpacity
            color: rm.pressed ? Theme.surfacePressed : rm.containsMouse ? Theme.surfaceHigher : "transparent"
            scale: rm.pressed ? 0.88 : 1
            Behavior on scale { NumberAnimation { duration: Prefs.ms(140); easing.type: Easing.OutBack } }
            Text { anchors.centerIn: parent; text: sc.nf(0xF0450); color: Theme.textVariant; font.family: Prefs.iconFont; font.pixelSize: Theme.fs(14) }
            MouseArea { id: rm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: sc.load(true) }
        }
    }
}
