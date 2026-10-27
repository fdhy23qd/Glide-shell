pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Съёмные диски (tools/glide-drives.py: udisks2 по D-Bus): список, подключить / отключить / извлечь. Вставили новое —
// подключаем (Prefs.drivesAutomount) и показываем уведомление с кнопками «Открыть» и «Извлечь». То, что было
// вставлено до запуска оболочки, — без уведомлений. Помощник — после старта (Prefs.warm), пока Prefs.drives.
Singleton {
    id: dr
    readonly property bool enabled: Prefs.drives && Prefs.warm
    property var list: []                 // [{id, label, device, fs, size, mounted, mountPoint, drive, driveName, …}]
    readonly property var mounted: list.filter(d => d.mounted)
    property var known: ({})              // id → true: о чём уже знаем (новое — то, чего здесь нет)
    property bool seeded: false
    property var busy: ({})               // id → действие, пока идёт
    readonly property string tool: Quickshell.env("GLIDE_DRIVES_TOOL") || Quickshell.shellDir + "/tools/glide-drives.py"
    signal done(string id, string action, bool ok, string error)

    Process {
        id: watcher
        running: dr.enabled
        stdinEnabled: true   // закрытый stdin — помощнику пора выйти
        command: ["setpriv", "--pdeathsig", "TERM", "python3", "-I", dr.tool, "watch"]
        stdout: SplitParser { onRead: line => dr.update(line) }
        onExited: if (dr.enabled) again.restart()   // udisks перезапустился и т. п.
    }
    Timer { id: again; interval: 5000; onTriggered: if (dr.enabled) watcher.running = true }
    onEnabledChanged: if (!enabled) { list = []; known = {}; seeded = false }

    function update(line) {
        var l
        try { l = JSON.parse(line) } catch (e) { return }
        if (!Array.isArray(l)) return
        var fresh = seeded ? l.filter(d => !known[d.id]) : []
        var k = {}
        for (var d of l) k[d.id] = true
        known = k
        list = l
        seeded = true
        for (var n of fresh) arrived(n)
    }
    function arrived(d) {
        if (d.encrypted) { notify(d, Tr.t("Зашифрованный диск"), Tr.t("Открой его в файловом менеджере — понадобится пароль"), false); return }
        if (!d.mounted && Prefs.drivesAutomount) mount(d, true)
        else notify(d, d.mounted ? Tr.t("Подключено: ") + name(d) : Tr.t("Вставлен диск: ") + name(d), info(d), !d.mounted)
    }

    function name(d) { return d.label || d.driveName || d.device }
    function size(b) {
        var u = [Tr.t("Б"), Tr.t("КБ"), Tr.t("МБ"), Tr.t("ГБ"), Tr.t("ТБ")], i = 0
        while (b >= 1024 && i < u.length - 1) { b /= 1024; i++ }
        return (i ? b.toFixed(b < 10 ? 1 : 0) : b) + " " + u[i]
    }
    function info(d) { return [size(d.size), d.fs].filter(x => x).join(" · ") }

    // ---------- действия ----------
    property Component jobComp: Component {
        Process {
            id: job
            property string driveId
            property string action
            property var then: null
            stdout: StdioCollector { id: jout }
            onExited: {
                var r = {}
                try { r = JSON.parse(jout.text) } catch (e) { r = { ok: false, error: jout.text.trim() || Tr.t("не удалось") } }
                var b = Object.assign({}, dr.busy); delete b[driveId]; dr.busy = b
                dr.done(driveId, action, !!r.ok, r.error || "")
                if (then) then(r)
                destroy()
            }
        }
    }
    function run(d, action, then) {
        if (busy[d.id]) return
        var b = Object.assign({}, busy); b[d.id] = action; busy = b
        var j = jobComp.createObject(dr, { driveId: d.id, action: action, then: then || null,
                                           command: ["python3", "-I", tool, action, d.id] })
        j.running = true
    }
    function mount(d, announce) {
        run(d, "mount", r => {
            if (!r.ok) { flash("!", Tr.t("Не подключился: ") + r.error, Theme.error); return }
            if (announce) notify(Object.assign({}, d, { mounted: true, mountPoint: r.mountPoint }), Tr.t("Подключено: ") + name(d), info(d), false)
        })
    }
    function unmount(d) {
        run(d, "unmount", r => flash(r.ok ? "✓" : "!", r.ok ? Tr.t("Отключено: ") + name(d) : Tr.t("Не отключился: ") + r.error, r.ok ? Theme.success : Theme.error))
    }
    function eject(d) {
        run(d, "eject", r => flash(r.ok ? String.fromCodePoint(0xF01EA) : "!",
                                   r.ok ? Tr.t("Можно вынимать: ") + name(d) : Tr.t("Не извлёкся (занят?): ") + r.error, r.ok ? Theme.success : Theme.error))
    }
    function open(d) {
        if (!d.mountPoint) { mount(d, false); return }
        Quickshell.execDetached(["systemd-run", "--user", "--scope", "--collect", "--quiet", "xdg-open", d.mountPoint])
    }
    function flash(icon, text, color) { if (Core.root) Core.root.flash(icon, text, color) }

    // уведомление с кнопками: notify-send ждёт выбора и печатает его (open / eject / mount); не дольше 10 минут
    property Component askComp: Component {
        Process {
            id: ask
            property var drive
            stdout: StdioCollector {
                onStreamFinished: {
                    // свежая запись из списка — но список мог ещё не узнать, куда подключили (он обновляется отдельно)
                    var a = text.trim(), live = dr.list.find(x => x.id === ask.drive.id)
                    var d = live && (live.mountPoint || !ask.drive.mountPoint) ? live : ask.drive
                    if (a === "open") dr.open(d)
                    else if (a === "eject") dr.eject(d)
                    else if (a === "mount") dr.mount(d, false)
                }
            }
            property Timer limit: Timer { interval: 600000; running: ask.running; onTriggered: ask.signal(15) }
            onExited: destroy()
        }
    }
    function notify(d, title, body, canMount) {
        var acts = d.encrypted ? [] : canMount ? ["-A", "mount=" + Tr.t("Подключить")] : ["-A", "open=" + Tr.t("Открыть"), "-A", "eject=" + Tr.t("Извлечь")]
        var p = askComp.createObject(dr, { drive: d, command: ["notify-send", "-a", Tr.t("Диски"), "-i", "drive-removable-media",
                                                                title, body].concat(acts) })
        p.running = true
    }
}
