import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import qs

// Диспетчер задач: графики ЦП и памяти, список процессов с поиском и сортировкой,
// завершение процесса. Данные (tm.py) читаются только пока панель открыта.
ColumnLayout {
    id: tm
    property var api
    property string pluginDir: ""        // папка плагина — ставит ядро (PluginSection)
    readonly property color accent: api && api.accent ? api.accent : Theme.accent
    readonly property color accentText: api && api.accentText ? api.accentText : "#ffffff"
    spacing: 10

    property var d: null                 // последний замер
    property var cpuHist: []             // 60 замеров = 2 минуты
    property var memHist: []
    property string sortBy: "cpu"        // cpu | mem | name
    property bool onlyMine: true
    property string query: ""
    property int selected: -1            // PID выбранного процесса
    property int armedKill: -1           // PID, для которого «Убить» ждёт второго нажатия

    function gb(kib) { return (kib / 1048576).toFixed(1) }
    function mb(m) { return m >= 1024 ? (m / 1024).toFixed(1) + Tr.t(" ГБ") : Math.round(m) + Tr.t(" МБ") }
    function push(arr, v) { var a = arr.concat([v]); return a.length > 60 ? a.slice(a.length - 60) : a }

    Process {
        running: !!tm.api && tm.api.shown && tm.pluginDir !== ""
        command: ["python3", "-I", tm.pluginDir + "/tm.py", "2"]
        stdout: SplitParser {
            onRead: (line) => {
                try { var x = JSON.parse(line) } catch (e) { return }
                tm.d = x
                tm.cpuHist = tm.push(tm.cpuHist, x.cpu / 100)
                tm.memHist = tm.push(tm.memHist, x.mem[1] / x.mem[0])
            }
        }
    }

    readonly property var rows: {
        if (!d) return []
        var q = query.trim().toLowerCase()
        var r = d.procs.filter(p => (!onlyMine || p[4]) && (!q || p[1].toLowerCase().indexOf(q) >= 0 || String(p[0]) === q))
        if (sortBy === "cpu") r.sort((a, b) => b[2] - a[2] || b[3] - a[3])
        else if (sortBy === "mem") r.sort((a, b) => b[3] - a[3])
        else r.sort((a, b) => a[1].localeCompare(b[1]))
        return r.slice(0, 40)
    }

    function kill(pid, sig) {
        api.run(["kill", "-" + sig, String(pid)], "")
        if (api.flash) api.flash("✓", (sig === "KILL" ? Tr.t("Убит ") : Tr.t("Завершён ")) + Tr.t("процесс ") + pid)
        selected = -1; armedKill = -1
    }

    // ---- карточка с графиком ----
    component GraphCard: Rectangle {
        id: graph
        property string title
        property string value
        property string sub
        property var hist: []
        property color tint: Theme.accent
        Layout.fillWidth: true
        Layout.preferredWidth: 1
        implicitHeight: 96
        radius: Theme.r(16)
        color: Theme.surface
        border.color: Theme.outline
        clip: true
        Canvas {   // заливка под линией за последние 2 минуты
            id: cv
            anchors.fill: parent
            anchors.topMargin: 36
            property var h: graph.hist
            onHChanged: requestPaint()
            onPaint: {
                var c = getContext("2d"); c.reset()
                var n = h.length; if (n < 2) return
                var step = width / 59, x0 = width - (n - 1) * step
                c.beginPath(); c.moveTo(x0, height)
                for (var i = 0; i < n; i++) c.lineTo(x0 + i * step, height - 2 - (height - 4) * Math.min(1, h[i]))
                c.lineTo(width, height); c.closePath()
                c.fillStyle = Qt.rgba(graph.tint.r, graph.tint.g, graph.tint.b, 0.22); c.fill()
                c.beginPath()
                for (i = 0; i < n; i++) {
                    var y = height - 2 - (height - 4) * Math.min(1, h[i])
                    if (i === 0) c.moveTo(x0, y); else c.lineTo(x0 + i * step, y)
                }
                c.lineWidth = 2; c.strokeStyle = graph.tint; c.stroke()
            }
        }
        Column {
            x: 12; y: 10
            spacing: 1
            Row {
                spacing: 8
                Text { text: graph.title; color: Theme.textSecondary; font.pixelSize: Theme.fs(11); font.bold: true; anchors.baseline: big.baseline }
                Text { id: big; text: graph.value; color: Theme.text; font.pixelSize: Theme.fs(16); font.bold: true; font.features: ({ "tnum": 1 }) }
            }
            Text { text: graph.sub; color: Theme.textMuted; font.pixelSize: Theme.fs(10); visible: text !== "" }
        }
    }

    component Seg: Rectangle {   // кнопка-сегмент сортировки
        id: sg
        property string text
        property bool on
        signal clicked()
        property color accent: Theme.accent
        property color accentText: "#ffffff"
        width: sgT.implicitWidth + 20; height: 28; radius: Theme.r(14)
        color: on ? (sgm.containsMouse ? Qt.lighter(accent, 1.12) : accent)
                  : (sgm.pressed ? Theme.surfaceHigh : sgm.containsMouse ? Theme.surfaceHigher : Theme.surface)
        border.color: on ? accent : Theme.outline
        scale: sgm.pressed ? 0.94 : 1
        Behavior on color { ColorAnimation { duration: Prefs.ms(150) } }
        Behavior on scale { NumberAnimation { duration: Prefs.ms(140); easing.type: Easing.OutBack } }
        Text { id: sgT; anchors.centerIn: parent; text: sg.text; color: sg.on ? sg.accentText : Theme.textVariant; font.pixelSize: Theme.fs(12) }
        MouseArea { id: sgm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: sg.clicked() }
    }

    // ---- графики ----
    RowLayout {
        Layout.fillWidth: true
        spacing: 8
        GraphCard {
            title: Tr.t("ПРОЦЕССОР")
            value: tm.d ? Math.round(tm.d.cpu) + "%" : "…"
            sub: tm.d ? tm.d.ncpu + Tr.t(" ядра") : ""
            hist: tm.cpuHist
            tint: tm.d && tm.d.cpu > 85 ? Theme.error : tm.accent
        }
        GraphCard {
            title: Tr.t("ПАМЯТЬ")
            value: tm.d ? tm.gb(tm.d.mem[1]) + " / " + tm.gb(tm.d.mem[0]) + Tr.t(" ГБ") : "…"
            sub: tm.d && tm.d.swap[0] > 0 ? Tr.t("подкачка ") + tm.gb(tm.d.swap[1]) + " / " + tm.gb(tm.d.swap[0]) + Tr.t(" ГБ") : ""
            hist: tm.memHist
            tint: tm.d && tm.d.mem[1] / tm.d.mem[0] > 0.9 ? Theme.error : "#2bb3e6"
        }
    }

    // ---- поиск и сортировка ----
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: 36
        radius: Theme.r(18)
        color: Theme.surface
        border.width: search.activeFocus ? 2 : 1
        border.color: search.activeFocus ? tm.accent : searchHover.hovered ? Theme.outlineHover : Theme.outline
        Behavior on border.color { ColorAnimation { duration: Prefs.ms(150) } }
        HoverHandler { id: searchHover; cursorShape: Qt.IBeamCursor }
        Text {
            x: 14; anchors.verticalCenter: parent.verticalCenter
            visible: search.text === ""
            text: Tr.t("Найти процесс или PID")
            color: Theme.textMuted
        }
        TextInput {
            id: search
            anchors.fill: parent; anchors.leftMargin: 14; anchors.rightMargin: 14
            verticalAlignment: TextInput.AlignVCenter
            color: Theme.text
            clip: true
            onTextChanged: tm.query = text
        }
    }
    Flow {
        Layout.fillWidth: true
        spacing: 6
        Seg { text: Tr.t("ЦП"); on: tm.sortBy === "cpu"; accent: tm.accent; accentText: tm.accentText; onClicked: tm.sortBy = "cpu" }
        Seg { text: Tr.t("Память"); on: tm.sortBy === "mem"; accent: tm.accent; accentText: tm.accentText; onClicked: tm.sortBy = "mem" }
        Seg { text: Tr.t("Имя"); on: tm.sortBy === "name"; accent: tm.accent; accentText: tm.accentText; onClicked: tm.sortBy = "name" }
        Seg { text: tm.onlyMine ? Tr.t("Только мои") : Tr.t("Все процессы"); on: false; onClicked: tm.onlyMine = !tm.onlyMine }
    }

    // ---- список ----
    RowLayout {
        Layout.fillWidth: true
        Layout.leftMargin: 10; Layout.rightMargin: 10
        Text { text: Tr.t("Процесс"); color: Theme.textMuted; font.pixelSize: Theme.fs(11); Layout.fillWidth: true }
        Text { text: Tr.t("ЦП"); color: Theme.textMuted; font.pixelSize: Theme.fs(11); Layout.preferredWidth: 52; horizontalAlignment: Text.AlignRight }
        Text { text: Tr.t("Память"); color: Theme.textMuted; font.pixelSize: Theme.fs(11); Layout.preferredWidth: 64; horizontalAlignment: Text.AlignRight }
    }
    EmptyState {
        visible: !!tm.d && tm.rows.length === 0
        Layout.fillWidth: true
        compact: true
        glyph: 0xF0349
        text: Tr.t("Ничего не найдено")
    }
    Text {
        visible: !tm.d
        text: Tr.t("Собираю данные…")
        color: Theme.textMuted
        Layout.leftMargin: 10
    }
    ColumnLayout {   // строки плотнее, чем остальные блоки
        Layout.fillWidth: true
        spacing: 2
    Repeater {
        model: tm.rows
        delegate: Rectangle {
            id: row
            required property var modelData
            readonly property bool sel: tm.selected === modelData[0]
            Layout.fillWidth: true
            implicitHeight: sel ? 72 : 32
            radius: Theme.r(12)
            color: rm.pressed ? Theme.surfaceHigher : sel ? Theme.surfaceHigh : (rm.containsMouse ? Theme.surface : "transparent")
            Behavior on color { ColorAnimation { duration: Prefs.ms(120) } }
            clip: true
            Behavior on implicitHeight { NumberAnimation { duration: Prefs.ms(180); easing.type: Easing.OutCubic } }
            Rectangle {   // тонкая линия загрузки ЦП внизу строки
                visible: row.modelData[2] >= 0.5
                x: 10; y: 28; height: 2; radius: Theme.r(1)
                width: (parent.width - 20) * Math.min(1, row.modelData[2] / 100)
                color: tm.accent
                opacity: 0.7
            }
            MouseArea {
                id: rm
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: { tm.selected = row.sel ? -1 : row.modelData[0]; tm.armedKill = -1 }
            }
            RowLayout {
                x: 10; width: parent.width - 20; height: 32
                spacing: 6
                Text {
                    Layout.fillWidth: true
                    text: row.modelData[1] + "  "
                    color: Theme.text; font.pixelSize: Theme.fs(12)
                    elide: Text.ElideRight
                    Text {   // PID — приглушённо после имени
                        x: Math.min(parent.implicitWidth, parent.width)
                        anchors.baseline: parent.baseline
                        text: row.modelData[0]
                        color: Theme.textMuted; font.pixelSize: Theme.fs(10)
                        visible: parent.implicitWidth + implicitWidth < parent.width
                    }
                }
                Text {
                    Layout.preferredWidth: 52; horizontalAlignment: Text.AlignRight
                    text: row.modelData[2].toFixed(1) + "%"
                    color: row.modelData[2] > 50 ? Theme.error : row.modelData[2] > 10 ? Theme.warning : Theme.textVariant
                    font.pixelSize: Theme.fs(12); font.features: ({ "tnum": 1 })
                }
                Text {
                    Layout.preferredWidth: 64; horizontalAlignment: Text.AlignRight
                    text: tm.mb(row.modelData[3])
                    color: Theme.textVariant; font.pixelSize: Theme.fs(12); font.features: ({ "tnum": 1 })
                }
            }
            Row {   // действия выбранного процесса
                visible: row.sel
                x: 10; y: 36
                spacing: 6
                Seg { text: Tr.t("Завершить"); on: false; onClicked: tm.kill(row.modelData[0], "TERM") }
                Seg {
                    text: tm.armedKill === row.modelData[0] ? Tr.t("Точно убить?") : Tr.t("Убить")
                    on: tm.armedKill === row.modelData[0]
                    accent: Theme.error
                    onClicked: {
                        if (tm.armedKill === row.modelData[0]) tm.kill(row.modelData[0], "KILL")
                        else { tm.armedKill = row.modelData[0]; disarm.restart() }
                    }
                }
                Seg { text: Tr.t("Копировать PID"); on: false; onClicked: tm.api.copy(String(row.modelData[0])) }
            }
        }
    }
    }
    Timer { id: disarm; interval: 3000; onTriggered: tm.armedKill = -1 }
}
