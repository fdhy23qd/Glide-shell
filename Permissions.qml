pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pam

// Разрешения плагинов и своих виджетов (API 2, docs/API.md, раздел 3б). Менять их может только человек:
// выдать — в «Настройки» → «Плагины» и паролем от входа (когда включена защита плагинов), забрать — без пароля.
// Плагин может только попросить (api.permissions.request): откроются настройки с вопросом.
// Файл ~/.config/glide-shell/permissions.json; правку в обход настроек, пока оболочка работает, она отменяет
// (tampered). То же правило выдачи — в tools/qp-discover.py (поле granted для D-Bus ListPlugins).
Singleton {
    id: perms

    readonly property var all: ["exec", "network", "clipboard", "notifications", "windows", "phone", "system"]
    readonly property var dangerous: ["exec", "system"]   // по сути полный доступ: выдаются с отдельным предупреждением
    readonly property var meta: ({
        exec:          { glyph: 0xF018D, title: Tr.t("Запуск программ"), hint: Tr.t("api.run, api.exec, а также daemon и команды кнопок. Полный доступ к системе от твоего имени.") },
        network:       { glyph: 0xF059F, title: Tr.t("Сеть"), hint: Tr.t("api.http — запросы в интернет") },
        clipboard:     { glyph: 0xF014C, title: Tr.t("Буфер обмена и выделение"), hint: Tr.t("api.contextText, api.copy") },
        notifications: { glyph: 0xF009A, title: Tr.t("Чужие уведомления"), hint: Tr.t("api.notifs и событие notification — что пишут другие программы") },
        windows:       { glyph: 0xF05B6, title: Tr.t("Окна"), hint: Tr.t("api.niri — список окон и управление ими") },
        phone:         { glyph: 0xF011C, title: Tr.t("Телефон"), hint: Tr.t("api.kdeconnect — устройства, их уведомления и команды") },
        system:        { glyph: 0xF0493, title: Tr.t("Настройки оболочки"), hint: Tr.t("api.setPref, api.setAwake, api.recorder — менять настройки, «не засыпать», запись экрана") }
    })
    function title(p) { return meta[p] ? meta[p].title : p }

    // ---------- кто есть кто: объект api → настоящий id и замороженная копия манифеста ----------
    // Заполняет только код оболочки, создающий api (раздел плагина, бар, служба, виджет), до того как отдать его
    // плагину. Права ищутся по самому объекту: api.owner и api.manifest плагин может перезаписать, а этот реестр — нет
    // (повторная регистрация того же объекта под другим id отклоняется).
    property var registry: []
    function register(obj, owner, name, m) {
        var r = lookup(obj)
        if (r) {
            if (r.owner !== owner) console.warn("glide-shell: попытка выдать api «" + r.owner + "» за «" + owner + "» — отклонено")
            return
        }
        var spec = Object.freeze({ id: owner, api: apiOf(m), trusted: trusted(m),
                                   permissions: Object.freeze(((m && m.permissions) || []).filter(x => typeof x === "string")) })
        registry = registry.concat([Object.freeze({ obj: obj, owner: owner, name: name || owner, spec: spec })])
    }
    function unregister(obj) { registry = registry.filter(r => r.obj !== obj) }
    function lookup(obj) { for (var r of registry) if (r.obj === obj) return r; return null }
    // для ApiScope: всё — по зарегистрированной записи; нет записи — нет и прав (даже у API 1)
    function allowed(obj, p) { var r = lookup(obj); return !!r && has(r.owner, r.spec, p) }

    // ---------- что выдано: owner → {api, granted: [...], denied: [...]} ----------
    property var grants: ({})
    property bool ready: false
    property string written: ""        // что записали сами: другое содержимое файла — правка в обход
    signal tampered()                  // shell.qml предупреждает вспышкой
    signal asked(string owner)         // плагин попросил разрешение — shell.qml открывает «Плагины»

    readonly property string path: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config")
                                   + "/glide-shell/permissions.json"
    FileView {
        id: file
        path: perms.path
        blockLoading: true
        printErrors: false
        atomicWrites: true
        watchChanges: true
        onFileChanged: reload()
        onLoaded: perms.fromFile(text())
        onLoadFailed: perms.fromFile("")
    }
    Component.onCompleted: if (!ready) { var t = ""; try { t = file.text() } catch (e) {} fromFile(t) }
    function fromFile(raw) {
        if (!ready) {   // при старте файл принимается как есть: правили его, пока оболочка не работала — значит, человек
            try { grants = (JSON.parse(raw) || {}).plugins || {} } catch (e) { grants = {} }
            written = raw
            ready = true
            return
        }
        if (raw === written) return
        console.warn("glide-shell: permissions.json изменён в обход настроек — изменение отменено")
        file.setText(written)
        tampered()
    }
    function save(g) {
        grants = g
        written = JSON.stringify({ version: 1, plugins: g }, null, 1) + "\n"
        file.setText(written)
    }

    // ---------- правило (то же в qp-discover.py) ----------
    function apiOf(m) { var v = Number(m && m.api); return v >= 1 ? Math.floor(v) : 1 }
    // встроенный плагин (из папки самой оболочки): поле trusted ставит qp-discover, значение из plugin.json он затирает;
    // у виджетов его нет (glide-widgets.py переносит только свои поля)
    function trusted(m) { return !!m && m.trusted === true }
    function requested(m) { return apiOf(m) < 2 ? all : all.filter(p => (m.permissions || []).indexOf(p) >= 0) }
    function entry(owner, m) {
        var e = grants[owner]
        if (!e || (Number(e.api) || 1) < 2 && apiOf(m) >= 2) return null   // запись от прежней версии (API 1) не в счёт
        return e
    }
    function has(owner, m, p) {
        if (trusted(m)) return true
        if (requested(m).indexOf(p) < 0) return false
        var e = entry(owner, m)
        if (!e) return apiOf(m) < 2   // API 1 без записи — всё, как раньше; API 2 — ничего, пока человек не выдаст
        return (e.granted || []).indexOf(p) >= 0
    }
    // "granted" | "denied" (отказал человек — плагин больше не спрашивает) | "ask" (не решено)
    function state(owner, m, p) {
        if (has(owner, m, p)) return "granted"
        var e = entry(owner, m)
        return e && (e.denied || []).indexOf(p) >= 0 ? "denied" : "ask"
    }
    function grantedList(owner, m) { return requested(m).filter(p => has(owner, m, p)) }
    function change(owner, m, p, on) {
        var g = JSON.parse(JSON.stringify(grants)), e = entry(owner, m)
        e = e ? JSON.parse(JSON.stringify(e)) : { api: apiOf(m), granted: apiOf(m) < 2 ? requested(m).slice() : [], denied: [] }
        e.api = apiOf(m)
        e.granted = (e.granted || []).filter(x => x !== p)
        e.denied = (e.denied || []).filter(x => x !== p)
        if (on) e.granted.push(p); else e.denied.push(p)
        g[owner] = e
        save(g)
    }
    // забрать — без пароля (безопасное направление)
    function revoke(owner, m, p) { if (!trusted(m) && has(owner, m, p)) change(owner, m, p, false) }
    // забыть решения: плагин снова сможет спросить (API 1 — снова всё разрешено)
    function forget(owner) { if (grants[owner]) { var g = JSON.parse(JSON.stringify(grants)); delete g[owner]; save(g) } }

    // ---------- выдать — только через вопрос человеку ----------
    // pending: {owner, name, perm, reason, manifest} — карточка в «Плагинах»; confirm(пароль) выдаёт, deny() — отказ
    property var pending: null
    property string error: ""
    readonly property bool checking: pam.active
    property var askedOnce: ({})       // плагин спрашивает о каждом разрешении не чаще раза за сеанс
    function ask(owner, name, m, p, reason) {
        if (trusted(m) || has(owner, m, p) || requested(m).indexOf(p) < 0) return
        pam.abort()
        error = ""
        pending = { owner: owner, name: name || owner, perm: p, reason: String(reason || ""), manifest: m }
    }
    // из api.permissions.request: только то, что объявлено в манифесте, не отказанное и раз за сеанс
    function request(owner, name, m, p, reason) {
        if (has(owner, m, p)) return true
        if (requested(m).indexOf(p) < 0) {
            console.warn("glide-shell: " + owner + ": разрешение «" + p + "» не объявлено в permissions")
            return false
        }
        var key = owner + "/" + p
        if (state(owner, m, p) === "denied" || askedOnce[key] || pending) return false
        var a = Object.assign({}, askedOnce); a[key] = true; askedOnce = a
        ask(owner, name, m, p, reason)
        if (pending) pending = Object.assign({ fromPlugin: true }, pending)   // вопрос — вверху «Плагинов», а не под плагином
        asked(owner)
        return false
    }
    function confirm(password) {
        if (!pending || pam.active) return
        if (!Prefs.pluginLock) { grantPending(); return }   // защита плагинов снята — хватает нажатия
        if (!password) return
        pam.pw = password
        pam.start()
    }
    function grantPending() {
        var p = pending
        pending = null; error = ""
        if (p) change(p.owner, p.manifest, p.perm, true)
    }
    function deny() {
        pam.abort()
        var p = pending
        pending = null; error = ""
        if (p) change(p.owner, p.manifest, p.perm, false)
    }
    function cancel() { pam.abort(); pending = null; error = "" }
    PamContext {
        id: pam
        property string pw: ""
        config: "login"
        configDirectory: "/etc/pam.d"
        onResponseRequiredChanged: if (responseRequired) respond(pw)
        onCompleted: result => {
            pw = ""
            if (result === PamResult.Success) perms.grantPending()
            else perms.error = result === PamResult.MaxTries ? Tr.t("Слишком много попыток") : Tr.t("Неверный пароль")
        }
        onError: err => { pw = ""; perms.error = Tr.t("Ошибка проверки пароля") }
    }
}
