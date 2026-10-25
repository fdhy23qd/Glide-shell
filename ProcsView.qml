import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

// Вкладка «Процессы» в настройках: что запущено оболочкой и плагинами и сколько это стоит.
// Процессы службы — tools/glide-procs.py (раз в 3 с, пока вкладка открыта), плагины — по реестру Permissions
// (каждая живая часть — раздел, элемент бара, служба, виджет — со своими счётчиками api.usage).
ColumnLayout {
    id: pv
    property var panel
    spacing: 14

    property var data_: ({ procs: [], total: { cpu: 0, pss: 0 }, uptime: 0 })
    property bool restartArmed: false
    property string error: ""
    readonly property var mainProc: data_.procs.find(p => p.main) || null
    readonly property var helpers: data_.procs.filter(p => !p.main)

    function nf(c) { return String.fromCodePoint(c) }
    function mb(kb) { return kb >= 1024 ? Tr.num(kb / 1024, kb >= 102400 ? 0 : 1) + Tr.t(" МБ") : kb + Tr.t(" КБ") }
    function dur(s) {
        if (s < 60) return s + Tr.t(" с")
        if (s < 3600) return Math.floor(s / 60) + Tr.t(" мин")
        if (s < 86400) return Math.floor(s / 3600) + Tr.t(" ч ") + Math.floor(s % 3600 / 60) + Tr.t(" мин")
        return Math.floor(s / 86400) + Tr.t(" д ") + Math.floor(s % 86400 / 3600) + Tr.t(" ч")
    }

    readonly property string tool: Quickshell.shellDir + "/tools/glide-procs.py"
    Process {
        id: probe
        command: ["python3", "-I", pv.tool]
        stdout: StdioCollector {
            onStreamFinished: { try { pv.data_ = JSON.parse(text); pv.error = "" } catch (e) { pv.error = text.trim() || String(e) } }
        }
    }
    Timer { running: pv.visible; repeat: true; triggeredOnStart: true; interval: 3000; onTriggered: if (!probe.running) probe.running = true }
    Process { id: killer; onExited: probe.running = true }

    // плагины и виджеты: живые части из реестра, по владельцу
    property int regTick: 0
    Timer { running: pv.visible; repeat: true; interval: 3000; onTriggered: pv.regTick++ }
    readonly property var owners: {
        regTick
        var m = {}
        for (var r of Permissions.registry) {
            var o = m[r.owner] || (m[r.owner] = { owner: r.owner, name: r.name, parts: 0, timers: 0, exec: 0, http: 0, trusted: r.spec.trusted })
            o.parts++
            var u = r.obj && r.obj.usage
            if (u) { o.timers += u.timers; o.exec += u.exec; o.http += u.http }
        }
        for (var p of data_.procs) if (p.owner) {
            var x = m[p.owner] || (m[p.owner] = { owner: p.owner, name: p.owner, parts: 0, timers: 0, exec: 0, http: 0, trusted: false })
            x.procs = (x.procs || 0) + 1; x.cpu = (x.cpu || 0) + p.cpu; x.pss = (x.pss || 0) + p.pss
        }
        return Object.values(m).sort((a, b) => (a.trusted - b.trusted) || String(a.name).localeCompare(String(b.name)))
    }

    // ---- оболочка ----
    SettingsView.Header { text: Tr.t("ОБОЛОЧКА") }
    Text {
        Layout.fillWidth: true
        text: pv.mainProc
            ? Tr.t("Работает ") + pv.dur(pv.data_.uptime) + "  ·  " + Tr.t("ЦП ") + Tr.num(pv.mainProc.cpu, 1) + "%  ·  "
              + Tr.t("память ") + pv.mb(pv.mainProc.pss) + "\n" + Tr.t("Вместе с помощниками: ЦП ") + Tr.num(pv.data_.total.cpu, 1)
              + "%, " + Tr.t("память ") + pv.mb(pv.data_.total.pss)
            : pv.error ? pv.error : Tr.t("Считаю…")
        color: pv.error ? Theme.error : Theme.text; font.pixelSize: Theme.fs(13)
        wrapMode: Text.WordWrap
    }
    Text {
        Layout.fillWidth: true
        text: Tr.t("ЦП — доля одного ядра, память — PSS (общие библиотеки поделены между процессами). Обновляется раз в 3 секунды, пока открыта эта вкладка.")
        color: Theme.textMuted; font.pixelSize: Theme.fs(11); wrapMode: Text.WordWrap
    }
    Flow {
        Layout.fillWidth: true
        spacing: 8
        SettingsView.ActionBtn {
            glyph: pv.nf(0xF0453)
            text: pv.restartArmed ? Tr.t("Точно перезапустить?") : Tr.t("Перезапустить оболочку")
            onClicked: {
                if (!pv.restartArmed) { pv.restartArmed = true; disarm.restart(); return }
                // служба: KillMode=process — команда переживёт оболочку; бар и панель вернутся через пару секунд
                Quickshell.execDetached(["systemctl", "--user", "restart", "glide-shell.service"])
            }
            Timer { id: disarm; interval: 4000; onTriggered: pv.restartArmed = false }
        }
        SettingsView.ActionBtn {
            glyph: pv.nf(0xF018D)
            text: Tr.t("Журнал")
            onClicked: Quickshell.execDetached(["systemd-run", "--user", "--scope", "--collect", "--quiet",
                                                Quickshell.env("TERMINAL") || "alacritty", "-e", "journalctl", "--user", "-u", "glide-shell", "-f", "-n", "200"])
        }
    }

    // ---- помощники ----
    SettingsView.Header { text: Tr.t("ПОМОЩНИКИ ОБОЛОЧКИ") + "  ·  " + pv.helpers.length }
    Repeater {
        model: pv.helpers
        delegate: Rectangle {
            id: row
            required property var modelData
            readonly property var p: modelData
            Layout.fillWidth: true
            implicitHeight: rowCol.implicitHeight + 14
            radius: Theme.radiusSm
            color: p.orphan ? Qt.rgba(Theme.error.r, Theme.error.g, Theme.error.b, 0.1) : Theme.surface
            border.color: p.orphan ? Theme.error : "transparent"
            RowLayout {
                anchors.fill: parent; anchors.margins: 7; anchors.leftMargin: 10
                spacing: 8
                ColumnLayout {
                    id: rowCol
                    Layout.fillWidth: true
                    spacing: 1
                    Text {
                        Layout.fillWidth: true
                        text: Tr.t(row.p.name) + (row.p.orphan ? "  ·  " + Tr.t("сирота: остался от прежнего запуска") : "")
                        color: row.p.orphan ? Theme.error : Theme.text; font.pixelSize: Theme.fs(12); font.bold: true
                        elide: Text.ElideRight
                    }
                    Text {
                        Layout.fillWidth: true
                        text: row.p.cmd
                        color: Theme.textMuted; font.pixelSize: Theme.fs(10); font.family: "monospace"
                        elide: Text.ElideRight
                    }
                }
                Text {
                    text: Tr.num(row.p.cpu, 1) + "%  ·  " + pv.mb(row.p.pss) + "\n" + pv.dur(row.p.age) + "  ·  PID " + row.p.pid
                    horizontalAlignment: Text.AlignRight
                    color: Theme.textSecondary; font.pixelSize: Theme.fs(11)
                }
                SettingsView.SmallBtn {
                    visible: row.p.orphan
                    glyph: "✕"
                    onClicked: { killer.command = ["python3", "-I", pv.tool, "kill", String(row.p.pid)]; killer.running = true }
                }
            }
        }
    }

    // ---- плагины и виджеты ----
    SettingsView.Header { text: Tr.t("ПЛАГИНЫ И ВИДЖЕТЫ") }
    Text {
        Layout.fillWidth: true
        text: Tr.t("Живые части (раздел, элемент бара, служба, виджет), их таймеры, запуски программ и запросы в сеть с момента создания части. Свои процессы плагина (daemon) — с нагрузкой.")
        color: Theme.textMuted; font.pixelSize: Theme.fs(11); wrapMode: Text.WordWrap
    }
    Repeater {
        model: pv.owners
        delegate: RowLayout {
            id: orow
            required property var modelData
            readonly property var o: modelData
            Layout.fillWidth: true
            spacing: 8
            Text {
                Layout.fillWidth: true
                text: orow.o.name + (orow.o.trusted ? "" : "  ·  " + Tr.t("сторонний"))
                color: Theme.text; font.pixelSize: Theme.fs(12)
                elide: Text.ElideRight
            }
            Text {
                text: [orow.o.parts ? Tr.t("частей ") + orow.o.parts : "",
                       orow.o.timers ? Tr.t("таймеров ") + orow.o.timers : "",
                       orow.o.exec ? Tr.t("программ ") + orow.o.exec : "",
                       orow.o.http ? Tr.t("запросов ") + orow.o.http : "",
                       orow.o.procs ? Tr.t("процессов ") + orow.o.procs + " (" + Tr.num(orow.o.cpu, 1) + "%, " + pv.mb(orow.o.pss) + ")" : ""]
                      .filter(x => x).join("  ·  ")
                color: Theme.textSecondary; font.pixelSize: Theme.fs(11)
            }
        }
    }
}
