import QtQuick
import Quickshell
import Quickshell.Io

// Глобальные клавиши плагинов (api.hotkey): привязка niri `spawn qs -c glide-shell ipc call panel hotkey "плагин/имя"`
// в glide-settings.kdl (tools/glide-niri.py bind — с niri validate и откатом). Ставит только человек — через вопрос
// (Confirms, имя плагина — из реестра); занятую клавишу не отнимаем. Список — из настроек niri (их правят и руками,
// и в «Устройства» → «Горячие клавиши»), поэтому перечитывается после каждой правки и при первом обращении.
QtObject {
    id: hk
    readonly property string tool: Quickshell.env("GLIDE_NIRI_TOOL") || Quickshell.shellDir + "/tools/glide-niri.py"
    readonly property var prefix: ["spawn", "qs", "-c", "glide-shell", "ipc", "call", "panel", "hotkey"]
    property var binds: []                // все клавиши niri: [{key, title, argv}]
    property bool loaded: false
    readonly property var mine: binds.filter(b => isOurs(b)).map(b => ({ key: b.key, id: b.argv[prefix.length], title: b.title }))
    signal pressed(string owner, string name)

    function isOurs(b) { return b.argv.length === prefix.length + 1 && prefix.every((x, i) => b.argv[i] === x) }
    function of(owner) {
        return mine.filter(x => x.id.indexOf(owner + "/") === 0).map(x => ({ name: x.id.slice(owner.length + 1), key: x.key, title: x.title }))
    }
    // Mod+Shift+W, Ctrl+Alt+F5, XF86AudioPlay; без модификатора — только F1…F24 и XF86…: иначе плагин занял бы букву
    function validKey(k) {
        var m = /^((?:(?:Mod|Super|Ctrl|Control|Alt|Shift|ISO_Level3_Shift|Mod5)\+)*)([A-Za-z0-9_]{1,40})$/.exec(String(k))
        return !!m && (m[1] !== "" || /^(F([1-9]|1[0-9]|2[0-4])|XF86\w+)$/.test(m[2]))
    }
    function validName(n) { return /^[A-Za-z0-9_.-]{1,40}$/.test(String(n)) }

    // ---- команды по одной (пишут файлы niri); у каждой — свой ответ ----
    property var cbs: []
    property JobQueue q: JobQueue {
        onFinished: (out) => {
            var cb = hk.cbs[0]
            hk.cbs = hk.cbs.slice(1)
            var r = null
            try { r = JSON.parse(out) } catch (e) {}
            try { if (cb) cb(r) } catch (e) { console.warn("glide-shell: api.hotkey: " + e) }
        }
    }
    function run(args, cb) { cbs = cbs.concat([cb || null]); q.add(["python3", "-I", tool].concat(args)) }
    property var waiting: []              // ждут первого чтения
    function reload(then) {
        if (then) waiting = waiting.concat([then])
        run(["read"], r => {
            if (r && Array.isArray(r.binds)) { hk.binds = r.binds.map(b => ({ key: String(b.key), title: String(b.title || ""), argv: (b.argv || []).map(String) })); hk.loaded = true }
            var w = hk.waiting; hk.waiting = []
            for (var f of w) f()
        })
    }
    function ready(f) { if (loaded) f(); else reload(f) }

    // cb(ok, причина): "" | bad | busy | denied | error: …
    function request(scope, owner, ownerName, name, key, title, cb) {
        var done = (ok, why) => { try { if (cb) cb(ok, why) } catch (e) { console.warn("glide-shell: api.hotkey: " + e) } }
        key = String(key || ""); title = String(title || "").slice(0, 60)
        if (!owner || !validName(name) || !validKey(key) || !Core.confirms) { Qt.callLater(() => done(false, "bad")); return false }
        ready(() => {
            var id = owner + "/" + name
            var same = mine.find(x => x.id === id)
            if (same && same.key.toLowerCase() === key.toLowerCase()) { done(true, ""); return }
            if (binds.some(b => b.key.toLowerCase() === key.toLowerCase())) { done(false, "busy"); return }
            var text = Tr.t("Поставить глобальную клавишу ") + key + (title ? " — «" + title + "»" : "")
                       + Tr.t("? Нажатие будет передаваться плагину. Убрать — «Устройства» → «Горячие клавиши».")
            // очередь вопросов занята — ask сам ответит «нет»
            Core.confirms.ask(scope, ownerName, text, { yes: Tr.t("Поставить"), no: Tr.t("Не надо") }, yes => {
                if (!yes) { done(false, "denied"); return }
                hk.run(["bind", JSON.stringify({ key: key, argv: hk.prefix.concat([id]), title: title, old: same ? same.key : "" })], r => {
                    hk.reload(() => done(!!(r && r.ok), r && r.ok ? "" : "error: " + (r && r.error || "?")))
                })
            })
        })
        return true
    }
    function remove(owner, name, cb) {
        var done = ok => { try { if (cb) cb(ok) } catch (e) { console.warn("glide-shell: api.hotkey: " + e) } }
        if (!owner || !validName(name)) { Qt.callLater(() => done(false)); return false }
        ready(() => {
            var x = mine.find(m => m.id === owner + "/" + name)
            if (!x) { done(false); return }
            hk.run(["bind", JSON.stringify({ delete: x.key })], r => hk.reload(() => done(!!(r && r.ok))))
        })
        return true
    }
    // IPC panel hotkey "плагин/имя" (её зовёт niri по клавише)
    function press(id) {
        var i = String(id).indexOf("/")
        if (i <= 0 || !validName(id.slice(i + 1))) return false
        pressed(id.slice(0, i), id.slice(i + 1))
        return true
    }
}
