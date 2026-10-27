import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs

// Календарь: месяц сеткой (неделя с понедельника, слева номера недель ISO), сегодня — акцентом,
// выходные — мягко красным. ‹ › и колесо листают месяцы, «Сегодня» возвращает к текущему.
// Праздники и переносы РФ (tools/glide-holidays.py, Prefs.holidays): нерабочие дни красным, рабочие субботы —
// обычным цветом, точка — праздник; внизу — день под курсором или ближайший праздник.
ColumnLayout {
    id: cal
    property var api
    readonly property color accent: api && api.accent ? api.accent : Theme.accent
    readonly property color accentText: api && api.accentText ? api.accentText : Theme.accentText
    readonly property string iconFont: api && api.iconFont ? api.iconFont : Prefs.iconFont
    readonly property bool shown: api ? api.shown : false
    spacing: 6

    property date today: new Date()
    property int year: today.getFullYear()
    property int month: today.getMonth()
    readonly property bool isCurrent: year === today.getFullYear() && month === today.getMonth()
    property int dir: 0   // направление последнего перелистывания — для анимации

    function goToday() { today = new Date(); dir = 0; year = today.getFullYear(); month = today.getMonth() }
    function shift(n) {
        dir = n
        var m = month + n
        year += Math.floor(m / 12)
        month = (m % 12 + 12) % 12
        flip.restart()
    }
    onShownChanged: if (shown) goToday()

    // ---- праздники: {год: {"MM-DD": {t, name}}} ----
    property var hol: ({})
    property int holYear: 0
    function loadHol(y) {
        if (!Prefs.holidays || hol[y] !== undefined || holProc.running) return
        holYear = y
        holProc.running = true
    }
    Process {
        id: holProc
        command: ["python3", "-I", Quickshell.shellDir + "/tools/glide-holidays.py", String(cal.holYear)]
        stdout: StdioCollector {
            onStreamFinished: {
                var h = Object.assign({}, cal.hol)
                try { h[cal.holYear] = JSON.parse(text).days } catch (e) { h[cal.holYear] = {} }
                cal.hol = h
                cal.loadHol(cal.year)            // пока качали, могли перелистнуть на другой год
                cal.loadHol(cal.today.getFullYear())
                cal.loadHol(cal.today.getFullYear() + 1)   // для «ближайшего» в конце года
            }
        }
    }
    onYearChanged: loadHol(year)
    Component.onCompleted: loadHol(year)
    function pad(n) { return (n < 10 ? "0" : "") + n }
    function holOf(d) {
        if (!Prefs.holidays) return null
        var y = hol[d.getFullYear()]
        return y ? y[pad(d.getMonth() + 1) + "-" + pad(d.getDate())] || null : null
    }
    function describe(d, h) {
        var t = h.name ? Tr.t(h.name) : h.t === "off" ? Tr.t("Выходной (перенос)") : h.t === "work" ? Tr.t("Рабочий день (перенос)")
              : h.t === "short" ? Tr.t("Сокращённый день") : ""
        return Tr.locale.toString(d, "d MMMM") + " — " + t
    }
    // ближайший праздник с названием (сегодня и дальше, до конца следующего года)
    readonly property string nextHol: {
        if (!Prefs.holidays) return ""
        var t = today, y0 = t.getFullYear()
        for (var y = y0; y <= y0 + 1; y++) {
            var days = hol[y]
            if (!days) continue
            var keys = Object.keys(days).sort()
            for (var k of keys) {
                if (!days[k].name) continue
                var d = new Date(y, +k.slice(0, 2) - 1, +k.slice(3))
                if (d < new Date(t.getFullYear(), t.getMonth(), t.getDate())) continue
                // каникулы подряд — одной строкой: пропустить, если вчера тоже был праздник
                var prev = new Date(d.getFullYear(), d.getMonth(), d.getDate() - 1), ph = holOf(prev)
                if (ph && ph.name && d > t && prev >= new Date(t.getFullYear(), t.getMonth(), t.getDate())) continue
                var n = Math.round((d - new Date(t.getFullYear(), t.getMonth(), t.getDate())) / 86400000)
                return describe(d, days[k]) + (n === 0 ? Tr.t(" · сегодня") : n === 1 ? Tr.t(" · завтра") : Tr.t(" · через ") + n + Tr.t(" дн."))
            }
        }
        return ""
    }
    property string hoverText: ""

    readonly property var monthNames: [Tr.t("Январь"), Tr.t("Февраль"), Tr.t("Март"), Tr.t("Апрель"), Tr.t("Май"), Tr.t("Июнь"), Tr.t("Июль"),
                                       Tr.t("Август"), Tr.t("Сентябрь"), Tr.t("Октябрь"), Tr.t("Ноябрь"), Tr.t("Декабрь")]
    function nf(code) { return String.fromCodePoint(code) }
    function isoWeek(d) {
        var t = new Date(Date.UTC(d.getFullYear(), d.getMonth(), d.getDate()))
        var day = t.getUTCDay() || 7
        t.setUTCDate(t.getUTCDate() + 4 - day)
        var y0 = new Date(Date.UTC(t.getUTCFullYear(), 0, 1))
        return Math.ceil(((t - y0) / 86400000 + 1) / 7)
    }
    // 6 недель по 7 дней, начиная с понедельника той недели, где 1-е число
    readonly property var weeks: {
        var first = new Date(year, month, 1)
        var start = new Date(year, month, 1 - (first.getDay() + 6) % 7)
        var out = []
        for (var w = 0; w < 6; w++) {
            var days = []
            for (var i = 0; i < 7; i++) {
                var d = new Date(start.getFullYear(), start.getMonth(), start.getDate() + w * 7 + i)
                var h = holOf(d)
                days.push({ n: d.getDate(), cur: d.getMonth() === month,
                            weekend: h && h.t === "off" ? true : h && h.t === "work" ? false : i >= 5,
                            name: !!(h && h.name), info: h ? describe(d, h) : "",
                            today: d.toDateString() === today.toDateString() })
            }
            out.push({ week: isoWeek(new Date(start.getFullYear(), start.getMonth(), start.getDate() + w * 7)), days: days })
        }
        return out
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 4
        Text {
            Layout.fillWidth: true
            text: cal.monthNames[cal.month] + " " + cal.year
            color: Theme.text; font.pixelSize: Theme.fs(16); font.bold: true
        }
        Rectangle {   // «Сегодня» — когда ушли с текущего месяца
            Behavior on color { ColorAnimation { duration: Prefs.ms(140) } }
            visible: !cal.isCurrent
            implicitWidth: todayText.implicitWidth + 20; implicitHeight: 28; radius: Theme.r(14)
            color: todayMouse.pressed ? Theme.surfacePressed : todayMouse.containsMouse ? Theme.surfaceHigher : Theme.surfaceHigh
            scale: todayMouse.pressed ? 0.94 : 1
            Behavior on scale { NumberAnimation { duration: Prefs.ms(140); easing.type: Easing.OutBack } }
            Text { id: todayText; anchors.centerIn: parent; text: Tr.t("Сегодня"); color: Theme.text; font.pixelSize: Theme.fs(12) }
            MouseArea { id: todayMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: cal.goToday() }
        }
        NavBtn { glyph: cal.nf(0xF0141); iconFont: cal.iconFont; onClicked: cal.shift(-1) }
        NavBtn { glyph: cal.nf(0xF0142); iconFont: cal.iconFont; onClicked: cal.shift(1) }
    }

    Item {
        id: gridBox
        Layout.fillWidth: true
        implicitHeight: grid.implicitHeight
        readonly property real cell: (width - 28) / 7

        Column {
            id: grid
            width: parent.width
            spacing: 2
            transform: Translate { id: slide }

            Row {   // дни недели
                Item { width: 28; height: 22 }
                Repeater {
                    model: [Tr.t("Пн"), Tr.t("Вт"), Tr.t("Ср"), Tr.t("Чт"), Tr.t("Пт"), Tr.t("Сб"), Tr.t("Вс")]
                    delegate: Text {
                        required property string modelData
                        required property int index
                        width: gridBox.cell; height: 22
                        horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                        text: modelData
                        color: index >= 5 ? Theme.errorSoft : Theme.textMuted; font.pixelSize: Theme.fs(11); font.bold: true
                    }
                }
            }
            Repeater {
                model: cal.weeks
                delegate: Row {
                    id: weekRow
                    required property var modelData
                    Text {   // номер недели
                        width: 28; height: 34
                        verticalAlignment: Text.AlignVCenter
                        text: weekRow.modelData.week
                        color: Theme.textFaint; font.pixelSize: Theme.fs(10)
                    }
                    Repeater {
                        model: weekRow.modelData.days
                        delegate: Item {
                            id: dayCell
                            required property var modelData
                            width: gridBox.cell; height: 34
                            Rectangle {
                                anchors.centerIn: parent
                                width: 30; height: 30; radius: Theme.r(15)
                                color: dayCell.modelData.today ? cal.accent : "transparent"
                            }
                            Text {
                                anchors.centerIn: parent
                                text: dayCell.modelData.n
                                font.pixelSize: Theme.fs(13)
                                font.bold: dayCell.modelData.today
                                color: dayCell.modelData.today ? cal.accentText
                                     : !dayCell.modelData.cur ? Theme.textFaint
                                     : dayCell.modelData.weekend ? Theme.errorSoft : Theme.text
                            }
                            Rectangle {   // праздник — точка под числом
                                visible: dayCell.modelData.name && dayCell.modelData.cur
                                anchors.horizontalCenter: parent.horizontalCenter
                                y: parent.height / 2 + 9
                                width: 4; height: 4; radius: 2
                                color: dayCell.modelData.today ? cal.accentText : Theme.errorSoft
                            }
                            HoverHandler {
                                enabled: dayCell.modelData.info !== ""
                                onHoveredChanged: cal.hoverText = hovered ? dayCell.modelData.info : (cal.hoverText === dayCell.modelData.info ? "" : cal.hoverText)
                            }
                        }
                    }
                }
            }
        }

        WheelHandler {   // колесо — листать месяцы; тачпад шлёт много мелких событий — копим до одного деления (120)
            property real acc: 0
            onWheel: (e) => {
                if (e.angleDelta.y === 0) return
                if (acc !== 0 && (acc > 0) !== (e.angleDelta.y > 0)) acc = 0   // сменили направление
                acc += e.angleDelta.y
                if (Math.abs(acc) < 120) return
                cal.shift(acc > 0 ? -1 : 1)
                acc = 0
            }
        }
    }

    Text {   // день под курсором или ближайший праздник
        Layout.fillWidth: true
        visible: text !== ""
        text: cal.hoverText || cal.nextHol
        color: cal.hoverText ? Theme.text : Theme.textSecondary
        font.pixelSize: Theme.fs(12)
        elide: Text.ElideRight
        leftPadding: 4
    }

    // перелистывание: сетка въезжает со стороны листания
    ParallelAnimation {
        id: flip
        NumberAnimation { target: slide; property: "x"; from: 24 * cal.dir; to: 0; duration: Prefs.ms(220); easing.type: Easing.OutCubic }
        NumberAnimation { target: grid; property: "opacity"; from: 0.3; to: 1; duration: Prefs.ms(200) }
    }

    component NavBtn: Rectangle {
        id: nb
        property string glyph
        property string iconFont
        signal clicked()
        implicitWidth: 28; implicitHeight: 28; radius: Theme.r(14)
        color: nbMouse.pressed ? Theme.surfacePressed : nbMouse.containsMouse ? Theme.surfaceHigher : "transparent"
        scale: nbMouse.pressed ? 0.88 : 1
        Behavior on scale { NumberAnimation { duration: Prefs.ms(140); easing.type: Easing.OutBack } }
        Text { anchors.centerIn: parent; text: nb.glyph; color: Theme.textVariant; font.family: nb.iconFont; font.pixelSize: Theme.fs(18) }
        MouseArea { id: nbMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: nb.clicked() }
    }
}
