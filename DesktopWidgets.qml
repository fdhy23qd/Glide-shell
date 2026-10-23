import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Mpris

// Виджеты рабочего стола (Prefs.widgets): часы, дата, погода, музыка, система, свой текст — поверх обоев
// (слой Bottom: над картинкой Glide и сценой webpaper, под окнами). По окну на монитор; виджет — на «главном»
// (screen "") или на названном мониторе. Ввод ловят только виджеты с кнопками (музыка) — остальное сквозное.
Scope {
    id: dw
    required property var panel
    readonly property var list: Prefs.widgets
    readonly property bool any: list.length > 0

    // ---- свои виджеты: ~/.config/glide-shell/widgets/<id>/{widget.json, widget.qml} (tools/glide-widgets.py) ----
    property var customs: []
    function rescan() { scanner.running = false; scanner.running = true }
    function custom(id) { return customs.find(x => x.id === id) || null }
    Process {
        id: scanner
        running: true
        command: ["python3", "-I", Quickshell.shellDir + "/tools/glide-widgets.py"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { dw.customs = JSON.parse(text) } catch (e) { dw.customs = [] }
                // один раз: свои виджеты API 1, что стояли до v1.1, остаются одобренными
                Permissions.migrateLegacy("widgets", dw.customs.map(w => ({ owner: "widget-" + w.id, m: w })))
            }
        }
    }

    // ---- правка рабочего стола: виджеты над окнами, тянуть мышью (IPC panel editDesktop, «Виджеты» в настройках) ----
    property bool editing: false
    function setWidget(id, patch) {
        Prefs.set("widgets", Prefs.widgets.map(w => w.id === id ? Object.assign({}, w, patch) : w))
    }
    function removeWidget(id) { Prefs.set("widgets", Prefs.widgets.filter(w => w.id !== id)) }
    function openSettings(id) {   // правая кнопка по виджету: настройки с ним раскрытым
        editing = false
        panel.widgetToOpen = id
        panel.settingsPage = "widgets"
        panel.settingsOpen = true
        if (!panel.shown) panel.open()
    }

    // общие часы виджетов: раз в минуту на её границе, с секундами — раз в секунду
    readonly property bool needSeconds: list.some(w => w.type === "clock" && w.seconds)
    property date now: new Date()
    Timer {
        id: ticker
        running: dw.any
        repeat: true
        interval: 1000
        triggeredOnStart: true
        onTriggered: {
            dw.now = new Date()
            interval = dw.needSeconds ? 1000 : 60000 - dw.now.getSeconds() * 1000 - dw.now.getMilliseconds() + 20
        }
    }
    function tick() { now = new Date(); ticker.interval = 1000; ticker.restart() }   // после сна (shell.qml)

    // процессор и память — только пока есть виджет «Система» (один процесс, раз в 2 с)
    // процессор и память — виджету «Система» и своим, кто попросил ("stats": true в widget.json)
    readonly property bool needStats: list.some(w => w.type === "system" || (w.type === "custom" && !!(custom(w.custom) || {}).stats))
    property real cpu: 0
    property real mem: 0
    property real memUsedGb: 0
    property real memTotalGb: 0
    property var cpuPrev: null
    property var statBuf: []
    Process {
        running: dw.needStats
        command: ["setpriv", "--pdeathsig", "TERM", "sh", "-c",
                  "while :; do head -1 /proc/stat; grep -E '^(MemTotal|MemAvailable):' /proc/meminfo; echo .; sleep 2; done"]
        stdout: SplitParser {
            onRead: (line) => {
                if (line !== ".") { dw.statBuf.push(line); return }
                var lines = dw.statBuf; dw.statBuf = []
                var c = lines[0].trim().split(/\s+/).slice(1).map(Number)
                var idle = c[3] + (c[4] || 0), total = c.reduce((a, b) => a + b, 0)
                if (dw.cpuPrev && total > dw.cpuPrev.total) dw.cpu = 100 * (1 - (idle - dw.cpuPrev.idle) / (total - dw.cpuPrev.total))
                dw.cpuPrev = { total: total, idle: idle }
                var mt = 0, ma = 0
                for (var l of lines) {
                    var m = l.match(/^(\w+):\s+(\d+)/)
                    if (m && m[1] === "MemTotal") mt = +m[2]
                    else if (m && m[1] === "MemAvailable") ma = +m[2]
                }
                if (mt) { dw.mem = 100 * (1 - ma / mt); dw.memTotalGb = mt / 1048576; dw.memUsedGb = (mt - ma) / 1048576 }
            }
        }
    }

    // музыка: играющий плеер, иначе последний из острова
    readonly property var player: {
        var ps = Mpris.players.values
        for (var p of ps) if (p.isPlaying) return p
        var last = panel ? panel.musicPlayer : null
        return last && ps.indexOf(last) >= 0 ? last : null
    }

    Variants {
        model: dw.any ? Quickshell.screens : []
        PanelWindow {
            id: win
            required property var modelData
            screen: modelData
            readonly property bool isMain: modelData === dw.panel.panelScreen
            readonly property var mine: dw.list.filter(w => w.screen ? w.screen === modelData.name : win.isMain)
            visible: mine.length > 0
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            // в правке — над окнами и с клавиатурой (Esc), иначе — под окнами и без неё
            WlrLayershell.layer: dw.editing ? WlrLayer.Overlay : WlrLayer.Bottom
            WlrLayershell.namespace: "glide-widgets"
            WlrLayershell.keyboardFocus: dw.editing && win.isMain ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            color: "transparent"
            // ввод — только там, где виджеты с кнопками (рамка вокруг них); остальное пропускает щелчки
            mask: Region { item: dw.editing ? fullBox : hitBox }
            Item { id: fullBox; anchors.fill: parent }

            // ---- правка: затемнение, сетка, подсказка и «Готово» ----
            Rectangle {
                anchors.fill: parent
                visible: dw.editing
                color: Qt.rgba(0, 0, 0, 0.45)
                focus: dw.editing
                Keys.onEscapePressed: dw.editing = false
                Keys.onReturnPressed: dw.editing = false
                MouseArea { anchors.fill: parent; onClicked: parent.forceActiveFocus() }
                Canvas {   // сетка 8 px (каждая 8-я линия ярче), рисуется один раз
                    anchors.fill: parent
                    onPaint: {
                        var c = getContext("2d"); c.reset()
                        for (var x = 0, i = 0; x < width; x += 8, i++) {
                            c.fillStyle = i % 8 === 0 ? "rgba(255,255,255,0.10)" : "rgba(255,255,255,0.035)"
                            c.fillRect(x, 0, 1, height)
                        }
                        for (var y = 0, j = 0; y < height; y += 8, j++) {
                            c.fillStyle = j % 8 === 0 ? "rgba(255,255,255,0.10)" : "rgba(255,255,255,0.035)"
                            c.fillRect(0, y, width, 1)
                        }
                        c.fillStyle = "rgba(123,97,255,0.35)"   // центр экрана
                        c.fillRect(Math.round(width / 2), 0, 1, height); c.fillRect(0, Math.round(height / 2), width, 1)
                    }
                }
                Rectangle {
                    visible: win.isMain
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: parent.top; anchors.topMargin: 14
                    width: barRow.implicitWidth + 16; height: 44; radius: 22
                    color: Theme.surface; border.color: Theme.outline
                    Row {
                        id: barRow
                        anchors.centerIn: parent
                        spacing: 12
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            leftPadding: 8
                            text: Tr.t("Тяни виджеты мышью · колесо — размер · правая кнопка — настройки")
                            color: Theme.textSecondary; font.pixelSize: Theme.fs(13)
                        }
                        Rectangle {
                            width: doneText.implicitWidth + 28; height: 32; radius: 16
                            color: doneMa.pressed ? Theme.accentPressed : doneMa.containsMouse ? Theme.accentLight : Theme.accent
                            scale: doneMa.pressed ? 0.95 : 1
                            Behavior on color { ColorAnimation { duration: Prefs.ms(120) } }
                            Behavior on scale { NumberAnimation { duration: Prefs.ms(140); easing.type: Easing.OutBack } }
                            Text { id: doneText; anchors.centerIn: parent; text: Tr.t("Готово"); color: Theme.accentText
                                   font.pixelSize: Theme.fs(13); font.weight: Font.DemiBold }
                            MouseArea { id: doneMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                        onClicked: dw.editing = false }
                        }
                    }
                }
            }
            Item {
                id: hitBox
                readonly property var boxes: { var b = [], ch = holder.children
                    for (var i = 0; i < ch.length; i++) if (ch[i].interactive && ch[i].visible) b.push(ch[i])
                    return b }
                x: boxes.length ? holder.x + Math.min.apply(null, boxes.map(c => c.x)) : 0
                y: boxes.length ? holder.y + Math.min.apply(null, boxes.map(c => c.y)) : 0
                width: boxes.length ? holder.x + Math.max.apply(null, boxes.map(c => c.x + c.width)) - x : 0
                height: boxes.length ? holder.y + Math.max.apply(null, boxes.map(c => c.y + c.height)) - y : 0
            }

            // поля: сверху — бар, снизу — немного над доком
            Item {
                id: holder
                anchors.fill: parent
                anchors.topMargin: (dw.panel.barOn ? dw.panel.barHeight : 0) + 24
                anchors.bottomMargin: 32
                anchors.leftMargin: 32
                anchors.rightMargin: 32
                Repeater {
                    model: win.mine
                    delegate: DeskWidget {
                        required property var modelData
                        cfg: modelData
                        hub: dw
                        editing: dw.editing
                    }
                }
            }
        }
    }
}
