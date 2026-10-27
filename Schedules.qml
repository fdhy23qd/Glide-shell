import QtQuick
import Quickshell
import Quickshell.Io

// Напоминания плагинов (api.schedule): переживают перезапуск оболочки — файл schedules.json (0600). Срок прошёл —
// сигнал due(owner, id, data, late) частям плагина; если ни одной живой нет (служба ещё не запустилась), запись ждёт.
// late — сработало позже срока больше чем на минуту (оболочка не работала, сон). Проверка — по ближайшему сроку,
// но не реже раза в минуту: таймеры Qt во сне стоят. Одноразовые: сработало — удалено.
QtObject {
    id: sch
    property string file: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/glide-shell/schedules.json"
    property var list: []                 // [{owner, id, at (мс с 1970), data}]
    property bool loaded: false
    readonly property int perOwner: 50
    signal due(string owner, string id, var data, bool late)

    property FileView view: FileView {
        path: sch.file
        printErrors: false
        onLoaded: { try { var l = JSON.parse(text()); sch.list = Array.isArray(l) ? l : [] } catch (e) { sch.list = [] } sch.loaded = true; sch.check() }
        onLoadFailed: { sch.loaded = true; sch.check() }
    }
    property Process saver: Process {
        property string sending: ""
        command: ["sh", "-c", 'umask 077; mkdir -p "${1%/*}"; cat > "$1.tmp" && mv "$1.tmp" "$1"', "sh", sch.file]
        stdinEnabled: true
        onStarted: { write(sending); stdinEnabled = false }
        onExited: { stdinEnabled = true; if (sch.dirty) sch.save() }
    }
    property bool dirty: false
    function save() {
        if (saver.running) { dirty = true; return }
        dirty = false
        saver.sending = JSON.stringify(list)
        saver.running = true
    }

    function when(w) {   // число (мс с 1970), Date или строка ISO → мс; иначе NaN
        if (w instanceof Date) return w.getTime()
        if (typeof w === "number") return w
        if (typeof w === "string") return Date.parse(w)
        return NaN
    }
    function set(owner, id, w, data) {
        var at = when(w)
        id = String(id || "")
        if (!owner || !id || id.length > 100 || !isFinite(at)) return false
        var copy = data === undefined ? null : JSON.parse(JSON.stringify(data))
        if (JSON.stringify(copy).length > 4096) return false
        var rest = list.filter(x => !(x.owner === owner && x.id === id))
        if (rest.filter(x => x.owner === owner).length >= perOwner) return false
        list = rest.concat([{ owner: owner, id: id, at: at, data: copy }])
        save()
        Qt.callLater(check)
        return true
    }
    function cancel(owner, id) {
        var n = list.length
        list = list.filter(x => !(x.owner === owner && x.id === String(id)))
        if (list.length !== n) save()
        return list.length !== n
    }
    function of(owner) { return list.filter(x => x.owner === owner).map(x => ({ id: x.id, at: x.at, data: x.data })) }

    // кому можно отдать: у владельца есть живая часть (зарегистрированный api)
    function alive(owner) { return Permissions.registry.some(r => r.owner === owner) }
    function check() {
        if (!loaded) return
        var now = Date.now(), fire = list.filter(x => x.at <= now && alive(x.owner))
        if (fire.length) {
            list = list.filter(x => fire.indexOf(x) < 0)
            save()
            for (var x of fire) due(x.owner, x.id, x.data, now - x.at > 60000)
        }
        var next = list.filter(x => alive(x.owner)).reduce((m, x) => Math.min(m, x.at), Infinity)
        tick.interval = Math.max(500, Math.min(60000, next - Date.now()))
        tick.restart()
    }
    property Timer tick: Timer { running: false; repeat: false; onTriggered: sch.check() }
    property Connections registry: Connections {   // появилась часть плагина — может, ей что-то ждёт
        target: Permissions
        function onRegistryChanged() { Qt.callLater(sch.check) }
    }
}
