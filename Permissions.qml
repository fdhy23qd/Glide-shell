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

    readonly property var all: ["exec", "network", "clipboard", "notifications", "windows", "phone", "system", "messages", "island", "search"]
    readonly property var dangerous: ["exec", "system"]   // по сути полный доступ: выдаются с отдельным предупреждением
    readonly property var meta: ({
        exec:          { glyph: 0xF018D, title: Tr.t("Запуск программ"), hint: Tr.t("api.run, api.exec, а также daemon и команды кнопок. Полный доступ к системе от твоего имени.") },
        network:       { glyph: 0xF059F, title: Tr.t("Сеть"), hint: Tr.t("api.http — запросы в интернет") },
        clipboard:     { glyph: 0xF014C, title: Tr.t("Буфер обмена и выделение"), hint: Tr.t("api.contextText, api.copy") },
        notifications: { glyph: 0xF009A, title: Tr.t("Чужие уведомления"), hint: Tr.t("api.notifs и событие notification — что пишут другие программы") },
        windows:       { glyph: 0xF05B6, title: Tr.t("Окна"), hint: Tr.t("api.niri — список окон и управление ими") },
        phone:         { glyph: 0xF011C, title: Tr.t("Телефон"), hint: Tr.t("api.kdeconnect — устройства, их уведомления и команды") },
        system:        { glyph: 0xF0493, title: Tr.t("Настройки оболочки"), hint: Tr.t("api.setPref, api.setAwake, api.recorder — менять настройки, «не засыпать», запись экрана") },
        messages:      { glyph: 0xF0369, title: Tr.t("Сообщения другим плагинам"), hint: Tr.t("api.send и onMessage с другими плагинами (между своими частями — без разрешения)") },
        island:        { glyph: 0xF0266, title: Tr.t("Цвет острова"), hint: Tr.t("api.island.tint — окрашивать остров (камера, микрофон и демонстрация экрана всегда впереди)") },
        search:        { glyph: 0xF0349, title: Tr.t("Поиск"), hint: Tr.t("api.search — видеть, что ты набираешь в поиске панели, и добавлять туда свои результаты") }
    })
    function title(p) { return p === "*" ? Tr.t("все разрешения (плагин старого формата)") : meta[p] ? meta[p].title : p }

    // ---------- кто есть кто: объект api → настоящий id и замороженная копия манифеста ----------
    // Заполняет только код оболочки, создающий api (раздел плагина, бар, служба, виджет), до того как отдать его
    // плагину. Права ищутся по самому объекту: api.owner и api.manifest плагин может перезаписать, а этот реестр — нет
    // (повторная регистрация того же объекта под другим id отклоняется).
    property var registry: []
    function register(obj, owner, name, m) {
        var r = lookup(obj)
        if (r && r.owner !== owner) {
            console.warn("glide-shell: попытка выдать api «" + r.owner + "» за «" + owner + "» — отклонено")
            return
        }
        // тот же объект снова (плагин обновили — новый plugin.json): api и список permissions — свежие, иначе новое
        // разрешение не действовало бы до перезапуска; trusted — как при первой записи: переписью его не получить
        var spec = Object.freeze({ id: owner, api: apiOf(m), trusted: r ? r.spec.trusted : trusted(m),
                                   permissions: Object.freeze(((m && m.permissions) || []).filter(x => typeof x === "string")) })
        if (r && JSON.stringify(r.spec) === JSON.stringify(spec)) return
        var e = Object.freeze({ obj: obj, owner: owner, name: name || owner, spec: spec })
        registry = r ? registry.map(x => x.obj === obj ? e : x) : registry.concat([e])
    }
    function unregister(obj) { registry = registry.filter(r => r.obj !== obj) }
    function lookup(obj) { for (var r of registry) if (r.obj === obj) return r; return null }
    // для ApiScope: всё — по зарегистрированной записи; нет записи — нет и прав (даже у API 1)
    function allowed(obj, p) { var r = lookup(obj); return !!r && has(r.owner, r.spec, p) }

    // ---------- что выдано: owner → {api, granted: [...], denied: [...]} ----------
    property var grants: ({})
    // выдано «до перезапуска»: owner → [разрешения] — только в памяти, в файл не пишется (v2.8)
    property var session: ({})
    function setSession(owner, list) {
        var s = Object.assign({}, session)
        if (list.length) s[owner] = list; else delete s[owner]
        session = s
        grantsChanged()   // для ApiScope и служб плагинов это то же, что смена выданного
    }
    property bool ready: false
    property string written: ""        // что записали сами: другое содержимое файла — правка в обход
    property string replaced: ""       // содержимое до подмены из резервной копии (его загрузка может прийти позже)
    signal tampered()                  // shell.qml предупреждает вспышкой
    signal asked(string owner)         // плагин попросил разрешение — shell.qml открывает «Плагины»

    readonly property string path: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config")
                                   + "/glide-shell/permissions.json"
    // восстановление из резервной копии (glide-backup.py) кладёт разрешения сюда: на ходу файл вернулся бы как «правка
    // в обход», а при запуске оболочки его принимаем — так же, как сам permissions.json, правленный до запуска
    FileView { id: importFile; path: perms.path + ".import"; blockLoading: true; printErrors: false }
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
    // какие наборы уже установленного одобрены один раз при переходе на v1.1 (plugins, widgets) — см. migrateLegacy
    property var legacy: ({})
    function fromFile(raw) {
        if (!ready) {   // при старте файл принимается как есть: правили его, пока оболочка не работала — значит, человек
            var imp = ""
            try { imp = importFile.text() } catch (e) {}
            if (imp.trim()) {
                // written — до записи: событие «файл изменился» от неё самой не должно выглядеть правкой в обход
                try { JSON.parse(imp); replaced = raw; raw = imp; written = imp; file.setText(imp) } catch (e) { console.warn("glide-shell: permissions.json.import повреждён — пропущен") }
                Quickshell.execDetached(["rm", "-f", importFile.path])
            }
            try { var d = JSON.parse(raw) || {}; grants = d.plugins || {}; legacy = d.legacy || {} } catch (e) { grants = {}; legacy = {} }
            written = raw
            ready = true
            return
        }
        if (raw === written) return
        if (replaced !== "" && raw === replaced) { replaced = ""; return }   // запоздалая загрузка прежнего файла (до подмены из копии)
        console.warn("glide-shell: permissions.json изменён в обход настроек — изменение отменено")
        file.setText(written)
        tampered()
    }
    function save(g) {
        grants = g
        written = JSON.stringify({ version: 1, legacy: legacy, plugins: g }, null, 1) + "\n"
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
        if ((session[owner] || []).indexOf(p) >= 0) return true
        var e = entry(owner, m)
        // без записи — ничего, пока человек не выдаст: и у API 2, и у API 1 (иначе любой скачанный плагин с «"api": 1»
        // молча получал бы всё). Установленное до v1.1 одобрено один раз — migrateLegacy
        if (!e) return false
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
        e = e ? JSON.parse(JSON.stringify(e)) : { api: apiOf(m), granted: [], denied: [] }
        e.api = apiOf(m)
        e.granted = (e.granted || []).filter(x => x !== p)
        e.denied = (e.denied || []).filter(x => x !== p)
        if (on) e.granted.push(p); else e.denied.push(p)
        g[owner] = e
        save(g)
    }
    // один раз при переходе: сторонние плагины (или свои виджеты) API 1, стоявшие до v1.1, получают то, что имели
    // (всё) — их ставил сам человек. Всё, что появится потом, начинает без прав. items: [{owner, m}]
    function migrateLegacy(kind, items) {
        if (!ready || legacy[kind]) return
        var g = JSON.parse(JSON.stringify(grants))
        for (var it of items)
            if (!trusted(it.m) && apiOf(it.m) < 2 && !g[it.owner])
                g[it.owner] = { api: 1, granted: requested(it.m).slice(), denied: [] }
        var l = Object.assign({}, legacy); l[kind] = true; legacy = l
        save(g)
        console.log("glide-shell: разрешения — установленное до v1.1 (" + kind + ") одобрено: " + items.length)
    }
    // v1.3: обмен сообщениями с другими плагинами стал разрешением «messages». Плагины старого формата, одобренные
    // целиком (у них было всё, в том числе сообщения), получают его один раз — чтобы связка плагинов не сломалась
    readonly property var oldAll: ["exec", "network", "clipboard", "notifications", "windows", "phone", "system"]
    function migrateMessages() {
        if (!ready || legacy.messages) return
        var g = JSON.parse(JSON.stringify(grants)), n = 0
        for (var k in g) {
            var e = g[k]
            if ((Number(e.api) || 1) < 2 && oldAll.every(p => (e.granted || []).indexOf(p) >= 0) && e.granted.indexOf("messages") < 0) {
                e.granted.push("messages"); n++
            }
        }
        var l = Object.assign({}, legacy); l.messages = true; legacy = l
        save(g)
        if (n) console.log("glide-shell: разрешения — «messages» выдано плагинам старого формата: " + n)
    }
    // «Разрешить всё» (плагин старого формата просит всё) — тот же вопрос с паролем, perm = "*"
    function askAll(owner, name, m) {
        if (trusted(m)) return
        pam.abort(); error = ""
        pending = { owner: owner, name: name || owner, perm: "*", reason: "", manifest: m }
    }

    // забрать — без пароля (безопасное направление)
    function revoke(owner, m, p) {
        if (trusted(m)) return
        var s = session[owner] || []
        if (s.indexOf(p) >= 0) setSession(owner, s.filter(x => x !== p))
        var e = entry(owner, m)
        if (e && (e.granted || []).indexOf(p) >= 0) change(owner, m, p, false)
    }
    // забыть решения: плагин снова сможет спросить (API 1 — снова всё разрешено)
    function forget(owner) {
        if (session[owner]) setSession(owner, [])
        if (grants[owner]) { var g = JSON.parse(JSON.stringify(grants)); delete g[owner]; save(g) }
    }

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
    // once — «до перезапуска»: только в памяти
    function confirm(password, once) {
        if (!pending || pam.active) return
        pending = Object.assign({}, pending, { once: once === true })
        if (!Prefs.pluginLock) { grantPending(); return }   // защита плагинов снята — хватает нажатия
        if (!password) return
        pam.pw = password
        pam.start()
    }
    function grantPending() {
        var p = pending
        pending = null; error = ""
        if (p && p.once) {   // до перезапуска: в память, не в файл
            var add = p.perm === "*" ? requested(p.manifest) : [p.perm]
            setSession(p.owner, (session[p.owner] || []).filter(x => add.indexOf(x) < 0).concat(add))
        } else if (p && p.perm === "*") {   // всё объявленное разом
            var g = JSON.parse(JSON.stringify(grants))
            g[p.owner] = { api: apiOf(p.manifest), granted: requested(p.manifest).slice(), denied: [] }
            save(g)
        } else if (p) change(p.owner, p.manifest, p.perm, true)
    }
    function deny() {
        pam.abort()
        var p = pending
        pending = null; error = ""
        if (p && p.perm !== "*") change(p.owner, p.manifest, p.perm, false)   // «всё» — не разрешение, в отказы не пишем
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
