import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import Quickshell.Services.UPower

// API для QML-плагинов и своих виджетов, версия 2 (описание — docs/API.md). Свой объект у каждого плагина и
// виджета: хранилище, настройки и уведомления — от его имени. Всё из версии 1 — как было; новое в версии 2 —
// разрешения (Permissions.qml): что их требует, без разрешения ничего не делает и пишет об этом в журнал.
QtObject {
    id: api

    property string owner: ""               // id плагина или «widget-<id>»
    property string ownerName: owner        // имя — в уведомлениях
    property var manifest: ({})             // plugin.json / widget.json (поле settings — схема настроек)
    readonly property int shellApi: 2       // какую версию API знает оболочка
    // кто я на самом деле — из реестра Permissions (его заполняет код оболочки); owner и manifest выше — только для показа
    readonly property var reg: Permissions.registry.length >= 0 ? Permissions.lookup(api) : null
    readonly property var spec: reg ? reg.spec : ({ api: 1, permissions: [], trusted: false })
    readonly property string me: reg ? reg.owner : ""          // настоящий id — для хранилища, файлов, настроек, сообщений
    readonly property string meName: reg ? reg.name : ""
    readonly property int version: Math.min(shellApi, spec.api)   // какую объявил плагин (поле api)
    readonly property string dir: manifest.dir || ""

    // ---------- разрешения (API 2): выдаёт только человек, плагин может лишь попросить ----------
    function can(p) { return Permissions.allowed(api, p) }
    property var warned: ({})
    function denied(p, what) {   // одно предупреждение на разрешение — не засорять журнал из привязок
        if (!warned[p]) {
            var w = Object.assign({}, warned); w[p] = true; warned = w
            console.warn("glide-shell: " + owner + ": " + what + " — нет разрешения «" + p + "» (docs/API.md, раздел 3б)")
        }
        return false
    }
    function need(p, what) { return can(p) || denied(p, what) }
    readonly property QtObject permissions: QtObject {
        readonly property var requested: api.reg ? Permissions.requested(api.spec) : []                 // объявлено в plugin.json
        readonly property var granted: api.reg ? Permissions.grantedList(api.reg.owner, api.spec) : []   // выдано человеком
        function has(p) { return api.can(p) }
        // спросить человека: откроются «Настройки» → «Плагины» с вопросом. true — уже выдано. Раз за сеанс,
        // только объявленное в permissions и не отказанное. Ответ — в onPermissionsUpdated.
        function request(p, reason) { return api.reg ? Permissions.request(api.reg.owner, api.reg.name, api.spec, p, reason) : false }
        function state(p) { return api.reg ? Permissions.state(api.reg.owner, api.spec, p) : "denied" }   // granted | denied | ask
    }
    signal permissionsUpdated()          // человек выдал или забрал разрешение
    property Connections permsConn: Connections {
        target: Permissions
        function onGrantsChanged() {
            if (api.tinted && !api.can("island")) api.island.clear()
            if (!api.can("clipboard") && Core.clipwatch) Core.clipwatch.listen(api, false)   // забрали — не слушать
            api.permissionsUpdated()
        }
    }

    // ---------- прежнее (плагины) ----------
    readonly property bool shown: Core.root.shown
    readonly property string contextText: can("clipboard") ? Core.root.contextText : ""   // выделение или буфер в момент вызова
    // переданный текст (выделение) — только тому, кому его передали: иначе любой плагин читал бы его без «clipboard»
    readonly property var handoff: me && Core.root.handoff && Core.root.handoff.to === me ? Core.root.handoff : null
    readonly property color accent: Prefs.accent
    readonly property color accentText: Theme.accentText
    readonly property var appCounts: Core.root.appCounts
    // только настоящее приложение из .desktop: по id; переданный объект с полем command запустил бы что угодно мимо «exec»
    function launchApp(entry) {
        var id = String(entry && typeof entry === "object" ? entry.id || "" : entry || "").replace(/\.desktop$/, "")
        var e = id ? DesktopEntries.byId(id) || DesktopEntries.applications.values.find(x => x.id === id) : null
        if (e) Core.root.launchApp(e)
        else console.warn("glide-shell: " + owner + ": launchApp — нет приложения «" + id + "»")
    }
    readonly property bool awake: Core.root.awake
    readonly property var powerTimer: Core.root.powerTimer
    property var now: Core.root.now                               // у виджета — дата (DeskWidget задаёт свою)
    readonly property var notifs: can("notifications") ? Notifs : null
    readonly property var weather: Weather
    readonly property var recorder: can("system") ? Recorder : null
    readonly property var kdeconnect: can("phone") ? KdeConnect : null
    readonly property var theme: Theme
    readonly property string iconFont: Prefs.iconFont
    // защиту плагинов паролем плагин снять не может (иначе выключил бы её сам себе)
    function setPref(key, value) { if (key !== "pluginLock" && need("system", "setPref")) Prefs.set(key, value) }
    function setAwake(on) { if (need("system", "setAwake")) Core.root.setAwake(on) }
    function run(argv, text) { if (need("exec", "run")) { usage.exec++; Core.root.runRaw(argv, text || "", dir) } }
    function close() { Core.root.close() }
    function openCategory(id) { Core.root.openCategory(id) }
    function openSettings() { Core.root.showSettings("plugins") }
    function copy(text) { if (need("clipboard", "copy")) Core.root.runRaw(["sh", "-c", 'printf %s "$QP_TEXT" | wl-copy'], text, "") }
    function flash(icon, text, color) { Core.root.flash(icon, text, color) }
    // без «exec» — только веб и почта: file://, свои схемы приложений и т. п. открывают программы
    function openUrl(url) { if (/^(https?:|mailto:)/i.test(String(url)) || need("exec", "openUrl " + String(url).split(":")[0])) Qt.openUrlExternally(url) }
    function takeHandoff(id) { return me ? Core.root.api.takeHandoff(me) : null }   // id — для совместимости: забрать можно только своё

    // ---------- прежнее (виджеты) — задаёт DeskWidget ----------
    property real k: 1
    property color tint: Theme.text
    property color sub: Theme.textSecondary
    property real cpu: 0
    property real mem: 0

    // ---------- дата: обновляется на границе минуты и после сна (таймеры Qt во сне стоят) ----------
    property date date: new Date()
    readonly property string today: Qt.formatDate(date, "yyyy-MM-dd")   // смена дня — привязки к today пересчитаются
    property Timer minuteTick: Timer {
        running: true; repeat: true
        interval: 60050 - Date.now() % 60000
        onTriggered: { api.date = new Date(); interval = 60050 - Date.now() % 60000 }
    }
    property Connections resumeConn: Connections {
        target: LockScreen
        function onResumed() { api.date = new Date() }
    }

    // ---------- система ----------
    readonly property var niri: can("windows") ? niriApi : null               // windows, workspaces, focused…, action(…)
    // не сам Niri: его action() выполняет и spawn — с одним разрешением «windows» плагин запускал бы что угодно
    readonly property var niriBlocked: ["spawn", "spawn-sh", "quit", "load-config-file"]
    property QtObject niriApi: QtObject {
        readonly property var workspaces: Niri.workspaces
        readonly property var windows: Niri.windows
        readonly property var focusedWindow: Niri.focusedWindow
        readonly property string focusedOutput: Niri.focusedOutput
        readonly property var layouts: Niri.layouts
        readonly property int layoutIdx: Niri.layoutIdx
        function iconFor(appId) { return Niri.iconFor(appId) }
        function titleFor(w) { return Niri.titleFor(w) }
        function focusWindow(id) { if (api.can("windows")) Niri.focusWindow(id) }
        function closeWindow(id) { if (api.can("windows")) Niri.closeWindow(id) }
        // первым — имя действия (ключи до него не пропускаем: так не спрятать spawn); запуск программ — только с «exec»
        function action(args) {
            var a = Array.isArray(args) ? args.map(String) : []
            if (!a.length || a[0].indexOf("-") === 0 || !api.can("windows")) return false
            if (api.niriBlocked.indexOf(a[0]) >= 0 && !api.need("exec", "niri " + a[0])) return false
            Niri.action(a)
            return true
        }
    }
    // события окон (разрешение «windows»): окно — копия {id, title, app_id, workspace_id, is_focused, is_floating…}
    signal windowOpened(var window)
    signal windowChanged(var window)        // сменились заголовок или приложение
    signal windowClosed(var window)
    signal windowFocused(var window)        // null — фокуса нет ни у одного окна
    property Connections niriConn: Connections {
        target: Niri
        function onWindowOpened(w) { if (api.can("windows")) api.windowOpened(w) }
        function onWindowChanged(w) { if (api.can("windows")) api.windowChanged(w) }
        function onWindowClosed(w) { if (api.can("windows")) api.windowClosed(w) }
        function onWindowFocused(w) { if (api.can("windows")) api.windowFocused(w) }
    }
    readonly property var players: Mpris.players.values                     // все плееры MPRIS
    readonly property var player: Core.root.musicPlayer || players[0] || null  // тот, что сейчас играл последним
    readonly property var battery: {                                        // {present, percent, charging}
        var d = UPower.displayDevice
        return { present: !!d && d.isLaptopBattery, percent: d ? Math.round(d.percentage * 100) : 0,
                 charging: !!d && d.state === UPowerDeviceState.Charging }
    }
    readonly property real volume: Core.root.sink && Core.root.sink.audio ? Core.root.sink.audio.volume : 0
    readonly property bool muted: Core.root.sink && Core.root.sink.audio ? Core.root.sink.audio.muted : false
    function setVolume(v) { if (Core.root.sink && Core.root.sink.audio) Core.root.sink.audio.volume = Math.max(0, Math.min(1.5, v)) }
    function setMuted(on) { if (Core.root.sink && Core.root.sink.audio) Core.root.sink.audio.muted = on }
    readonly property bool dnd: Notifs.quiet

    // ---------- запуск с результатом: api.exec(argv, {stdin, timeout, env}, (code, out, err) => …) ----------
    // argv — без shell (кавычки и переносы в аргументах передаются как есть). Возвращает задачу с cancel() и running.
    // code: код выхода; -1 — не запустилась, прервана cancel() или по timeout (по умолчанию 60 с). Обратный вызов — один раз.
    property Component execComp: Component {
        Process {
            id: job
            property var cb: null
            property string input: ""
            property int timeoutMs: 60000
            property bool aborted: false
            property bool finished: false
            property bool outDone: false
            property bool errDone: false
            property var exitCode: null
            stdinEnabled: input !== ""
            stdout: StdioCollector { id: jout; onStreamFinished: { job.outDone = true; job.tryFinish() } }
            stderr: StdioCollector { id: jerr; onStreamFinished: { job.errDone = true; job.tryFinish() } }
            onStarted: if (input !== "") { write(input); stdinEnabled = false }   // записали — закрыть stdin
            onExited: (code) => { job.exitCode = job.aborted ? -1 : code; job.tryFinish() }
            function tryFinish() {
                if (finished || exitCode === null || !outDone || !errDone) return
                finished = true
                // программа не нашлась: под setpriv это код 127 и его сообщение — для плагина тоже -1, как «не запустилась»
                var code = exitCode === 127 && /^setpriv: /m.test(jerr.text) ? -1 : exitCode
                // кто упал — в журнал: без имени не понять, какой плагин (часто — ответ пришёл, а его раздел уже закрыт)
                try { if (cb) cb(code, jout.text, jerr.text) } catch (e) { console.warn("glide-shell: " + api.owner + ": api.exec: " + e) }
                destroy()
            }
            function cancel() { if (running) { aborted = true; signal(15) } }
            property Timer limit: Timer { interval: job.timeoutMs; running: job.running && job.timeoutMs > 0; onTriggered: job.cancel() }
            property Timer startCheck: Timer {
                interval: 200
                // не запустилась (нет программы): не идёт и кода выхода нет
                onTriggered: if (!job.running && job.exitCode === null) { job.exitCode = -1; job.outDone = job.errDone = true; job.tryFinish() }
            }
        }
    }
    function exec(argv, opts, cb) {
        if (typeof opts === "function") { cb = opts; opts = {} }
        if (!need("exec", "exec")) {   // без разрешения — как «не запустилась», ответ тоже асинхронный
            var fn = cb
            if (fn) Qt.callLater(() => { try { fn(-1, "", "glide-shell: no permission: exec") } catch (e) { console.warn("glide-shell: " + api.owner + ": api.exec: " + e) } })
            return { running: false, cancel: function () {} }
        }
        usage.exec++
        return spawn(argv, opts, cb)
    }
    function spawn(argv, opts, cb) {   // внутреннее: exec без проверки (api.files)
        opts = opts || {}
        var env = Object.assign({ QP_DIR: manifest.dir || "" }, opts.env || {})
        // setpriv --pdeathsig: упала оболочка — программа не остаётся сиротой (выключили плагин — её убивает сам Process)
        var j = execComp.createObject(api, { command: ["setpriv", "--pdeathsig", "TERM"].concat(argv), environment: env, cb: cb || null, input: opts.stdin || "",
                                             timeoutMs: opts.timeout === undefined ? 60000 : opts.timeout })
        j.running = true
        j.startCheck.start()
        return j
    }

    // ---------- уведомление от имени плагина ----------
    function notify(title, body, icon) {
        Quickshell.execDetached(["notify-send", "-a", meName || "Glide Shell", "-i", icon || "dialog-information",
                                 String(title || ""), String(body || "")])
    }

    // ---------- «живые активности» в острове (Activities.qml): id — свой, внутри плагина ----------
    // props: {title, subtitle, icon, progress (0…1, меньше 0 — без процента), color, actionLabel, onClick, onAction}
    readonly property QtObject activity: QtObject {
        function start(id, props) { return api.me ? Activities.start(api.me + "/" + id, Object.assign({}, props || {}, { owner: api.me })) : "" }
        function update(id, props) { return api.me ? Activities.update(api.me + "/" + id, Object.assign({}, props || {}, { owner: api.me })) : "" }
        function end(id) { if (api.me) Activities.end(api.me + "/" + id) }
    }

    // ---------- вопрос человеку: confirm(текст, {yes, no}, cb(bool)) — окно рисует оболочка, имя плагина — из реестра ----------
    // Разрешений не нужно (решает человек). Один вопрос за раз от этой части плагина; лишний — сразу false.
    function confirm(text, opts, cb) {
        if (typeof opts === "function") { cb = opts; opts = {} }
        if (!me || !Core.confirms) { if (cb) Qt.callLater(() => cb(false)); return false }
        return Core.confirms.ask(api, meName, text, opts, cb)
    }

    // ---------- смена буфера (разрешение «clipboard»): clipboard.listen(true) → сигнал clipboardUpdated(text) ----------
    // Слушатель wl-paste работает, только пока хоть одна часть слушает; пароли менеджеров паролей не приходят.
    signal clipboardUpdated(string text)
    readonly property QtObject clipboard: QtObject {
        function listen(on) {
            if (!api.me || !Core.clipwatch) return false
            if (on !== false && !api.need("clipboard", "clipboard.listen")) return false
            Core.clipwatch.listen(api, on !== false)
            return true
        }
    }

    // ---------- выбор файла человеком (tools/glide-pick.py: портал FileChooser или zenity) — без разрешения «exec» ----------
    // pickFile({title, multiple, directory, filters: [{name, patterns}], read}, cb(paths | null, texts | null));
    // saveFile(имя, текст, {title}, cb(path | null)) — пишет туда, куда выбрал человек. Окно одно на часть плагина.
    property bool picking: false
    readonly property string pickTool: Quickshell.env("GLIDE_PICK_TOOL") || Quickshell.shellDir + "/tools/glide-pick.py"
    function pickFile(opts, cb) {
        if (typeof opts === "function") { cb = opts; opts = {} }
        if (!me || picking) { if (cb) Qt.callLater(() => cb(null, null)); return false }
        picking = true
        spawn(["python3", "-I", pickTool, "open", JSON.stringify(opts || {})], { timeout: 0 }, (code, out) => {
            api.picking = false
            var r = {}
            try { r = JSON.parse(out) } catch (e) {}
            if (r.error) console.warn("glide-shell: " + api.owner + ": pickFile: " + r.error)
            try { if (cb) cb(r.ok ? r.paths : null, r.ok && r.texts ? r.texts : null) } catch (e) { console.warn("glide-shell: " + api.owner + ": pickFile: " + e) }
        })
        return true
    }
    function saveFile(name, text, opts, cb) {
        if (typeof opts === "function") { cb = opts; opts = {} }
        if (!me || picking) { if (cb) Qt.callLater(() => cb(null)); return false }
        picking = true
        spawn(["python3", "-I", pickTool, "save", JSON.stringify(Object.assign({}, opts || {}, { name: String(name || ""), hasText: String(text === undefined ? "" : text) !== "" }))],
              { timeout: 0, stdin: String(text === undefined ? "" : text) }, (code, out) => {
            api.picking = false
            var r = {}
            try { r = JSON.parse(out) } catch (e) {}
            if (r.error) console.warn("glide-shell: " + api.owner + ": saveFile: " + r.error)
            try { if (cb) cb(r.ok ? r.paths[0] : null) } catch (e) { console.warn("glide-shell: " + api.owner + ": saveFile: " + e) }
        })
        return true
    }

    // ---------- напоминания: переживают перезапуск оболочки (Schedules.qml) ----------
    // schedule.at(id, когда — мс/Date/ISO, data) / after(id, мс, data) → bool; cancel(id); list() → [{id, at, data}].
    // Срок — сигнал scheduled(id, data, late) всем живым частям плагина (ловить — в службе). late — опоздало больше минуты.
    signal scheduled(string id, var data, bool late)
    readonly property QtObject schedule: QtObject {
        function at(id, when, data) { return !!api.me && !!Core.schedules && Core.schedules.set(api.me, id, when, data) }
        function after(id, ms, data) { return at(id, Date.now() + Math.max(0, Number(ms) || 0), data) }
        function cancel(id) { return !!api.me && !!Core.schedules && Core.schedules.cancel(api.me, id) }
        function list() { return api.me && Core.schedules ? Core.schedules.of(api.me) : [] }
    }
    property Connections schedConn: Connections {
        target: Core.schedules
        ignoreUnknownSignals: true
        function onDue(owner, id, data, late) { if (owner === api.me) api.scheduled(id, data, late) }
    }

    // ---------- поиск (разрешение «search»): свои результаты в общем поиске панели ----------
    // provide((query, done) => …): вернуть массив сразу или позже вызвать done(массив); устаревшие ответы отбрасываются.
    // Результат: {id, title, sub, glyph (код Nerd Font или символ), icon (значок темы), copy (текст в буфер),
    // url (http/https/mailto), top (над приложениями)}. Выбрали результат без copy/url — сигнал searchActivated(id).
    signal searchActivated(string id)
    readonly property QtObject search: QtObject {
        function provide(fn) {
            if (typeof fn !== "function" || !api.me || !api.need("search", "search.provide")) return false
            Core.setSearch(api, api.me, fn)
            return true
        }
        function stop() { Core.setSearch(api, api.me, null) }
    }

    // ---------- цвет острова (разрешение «island»): камера, микрофон и демонстрация экрана всегда впереди ----------
    // цвет живёт, пока жива часть плагина, которая его задала: надолго — из службы (service)
    property bool tinted: false
    readonly property QtObject island: QtObject {
        readonly property var colors: Core.islandTints
        function tint(c) {
            if (!api.me || !api.need("island", "api.island.tint")) return false
            var ok = Core.setTint(api.me, c)
            api.tinted = ok
            return ok
        }
        function clear() { if (api.me && api.tinted) { Core.setTint(api.me, ""); api.tinted = false } }
    }

    // ---------- хранилище: свой JSON в ~/.local/state/glide-shell/plugin-<id>.json ----------
    property var stored: ({})
    readonly property string storeFile: me ? (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state")
                                                + "/glide-shell/plugin-" + me.replace(/[^\w.-]/g, "_") + ".json" : ""
    readonly property QtObject storage: QtObject {
        readonly property var all: api.stored
        function get(key, def) { return api.stored[key] !== undefined ? api.stored[key] : def }
        function set(key, value) { var c = Object.assign({}, api.stored); c[key] = value; api.stored = c; api.saveLater.restart() }
        function remove(key) { var c = Object.assign({}, api.stored); delete c[key]; api.stored = c; api.saveLater.restart() }
        function keys() { return Object.keys(api.stored) }
        function clear() { api.stored = {}; api.saveLater.restart() }
    }
    property FileView storeView: FileView {
        path: api.storeFile
        printErrors: false
        blockLoading: true
        atomicWrites: true
        watchChanges: true                  // раздел плагина и его элемент бара — разные объекты, файл один
        onFileChanged: reload()
        onLoaded: {
            try { api.stored = JSON.parse(text()) || {} } catch (e) {
                // повреждён: начать с пустого, но прежний файл сохранить рядом (.broken) — первая запись его бы затёрла
                if (text().trim()) Quickshell.execDetached(["cp", "-f", api.storeFile, api.storeFile + ".broken"])
                api.stored = {}
            }
        }
    }
    property Timer saveLater: Timer { interval: 300; onTriggered: api.storeView.setText(JSON.stringify(api.stored)) }

    // ---------- настройки из манифеста («settings»: [{key, type, label, default, options}]) ----------
    // значения — в config.json (panel.pluginSettings[id]): попадают в резервную копию; меняются во вкладке «Плагины»
    readonly property var settings: {
        var saved = (Prefs.pluginSettings || {})[me] || {}, out = {}
        for (var s of (manifest.settings || [])) {
            var v = saved[s.key] !== undefined ? saved[s.key] : s["default"]
            if (s.type === "number") {   // число: в пределах min/max (если заданы), не число — default
                v = Number(v)
                if (!isFinite(v)) v = Number(s["default"]) || 0
                if (s.min !== undefined) v = Math.max(s.min, v)
                if (s.max !== undefined) v = Math.min(s.max, v)
            }
            out[s.key] = v
        }
        return out
    }
    function setSetting(key, value) { if (me) Prefs.setPluginSetting(me, key, value) }

    // ---------- события ----------
    signal opened()                    // панель открылась
    signal closed()                    // … закрылась
    signal themeUpdated()              // акцент, тон или светлая/тёмная тема (не themeChanged: так зовётся смена свойства theme)
    signal notification(var entry)     // пришло уведомление: {appName, summary, body, urgency, time}
    property Connections shellConn: Connections {
        target: Core.root
        function onShownChanged() { if (Core.root.shown) api.opened(); else api.closed() }
    }
    property Connections themeConn: Connections {
        target: Theme
        function onIsLightChanged() { api.themeUpdated() }
        function onAccentChanged() { api.themeUpdated() }
        function onBackgroundChanged() { api.themeUpdated() }
    }
    property Connections notifsConn: Connections {
        target: Notifs
        function onReceived(entry) { if (api.can("notifications")) api.notification(entry) }
    }

    // ===================== версия 2 =====================

    // ---------- язык и журнал ----------
    readonly property string lang: Tr.lang                                   // "ru" | "en"
    function tr(ru, en) { return Tr.ru || en === undefined ? ru : en }       // свой текст на языке интерфейса
    function fmt(args) { return "[" + owner + "] " + Array.prototype.map.call(args, a => typeof a === "object" ? JSON.stringify(a) : String(a)).join(" ") }
    function log() { console.log(fmt(arguments)) }
    function warn() { console.warn(fmt(arguments)) }

    // ---------- сколько эта часть плагина делает — для «Настройки» → «Процессы» (только показ, права от этого не зависят) ----------
    readonly property QtObject usage: QtObject {
        property int timers: 0              // живых таймеров setTimeout/setInterval
        property int fast: 0                // из них повторяющихся чаще раза в секунду (нагрузка — «Процессы» предупредят)
        property int exec: 0                // запусков api.exec и api.run с начала
        property int http: 0                // запросов api.http с начала
        readonly property double since: Date.now()
    }

    // ---------- таймеры: в QML нет setTimeout; таймеры живут не дольше этой части плагина ----------
    property Component timerComp: Component {
        Timer {
            property bool fast: false
            Component.onCompleted: { api.usage.timers++; if (repeat && interval < 1000) { fast = true; api.usage.fast++ } }
            Component.onDestruction: { api.usage.timers--; if (fast) api.usage.fast-- }
            property var fn: null
            property bool dead: false          // уже уничтожается: повторный clearTimer — без ошибки
            onTriggered: {
                if (!repeat) dead = true
                try { if (fn) fn() } catch (e) { console.warn("glide-shell: " + api.owner + ": таймер: " + e) }
                if (!repeat) destroy()
            }
        }
    }
    function setTimeout(fn, ms) { var t = timerComp.createObject(api, { fn: fn, interval: Math.max(0, ms || 0), repeat: false }); t.start(); return t }
    function setInterval(fn, ms) { var t = timerComp.createObject(api, { fn: fn, interval: Math.max(16, ms || 0), repeat: true }); t.start(); return t }
    function clearTimer(t) { try { if (t && !t.dead) { t.dead = true; t.stop(); t.destroy() } } catch (e) {} }

    // ---------- файлы: своя папка ~/.local/share/glide-shell/plugin-data/<id> (tools/qp-files.py) ----------
    // имена — без папок: латиница, цифры, «_», «.», «-»; обратный вызов — один раз
    readonly property string dataDir: me ? (Quickshell.env("XDG_DATA_HOME") || Quickshell.env("HOME") + "/.local/share")
                                              + "/glide-shell/plugin-data/" + me.replace(/[^\w.-]/g, "_") : ""
    readonly property QtObject files: QtObject {
        function tool(args, stdin, done) {
            return api.spawn(["python3", "-I", Quickshell.shellDir + "/tools/qp-files.py"].concat(args), { stdin: stdin || "", timeout: 30000 }, done)
        }
        // cb(text) — null, если файла нет
        function read(name, cb) { tool(["read", api.dataDir, String(name)], "", (code, out) => { if (cb) cb(code === 0 ? out : null) }) }
        // cb(ok)
        function write(name, text, cb) { tool(["write", api.dataDir, String(name)], JSON.stringify(String(text)), (code, out, err) => {
            if (code !== 0) console.warn("glide-shell: " + api.owner + ": files.write: " + err.trim())
            if (cb) cb(code === 0) }) }
        // cb([{name, size, mtime}])
        function list(cb) { tool(["list", api.dataDir], "", (code, out) => { var l = []; try { l = JSON.parse(out) } catch (e) {} if (cb) cb(l) }) }
        // cb(ok)
        function remove(name, cb) { tool(["remove", api.dataDir, String(name)], "", (code) => { if (cb) cb(code === 0) }) }
    }

    // ---------- сеть (разрешение network): api.http(url, {method, headers, body, timeout}, (status, text, headers) => …) ----------
    // status 0 — нет разрешения, сети, ответа за timeout (по умолчанию 30 с) или адрес не http(s)
    function http(url, opts, cb) {
        if (typeof opts === "function") { cb = opts; opts = {} }
        opts = opts || {}
        var done = false
        function finish(status, text, headers) {
            if (done) return
            done = true
            try { if (cb) cb(status, text, headers || {}) } catch (e) { console.warn("glide-shell: " + api.owner + ": api.http: " + e) }
        }
        if (!need("network", "http") || !/^https?:\/\//i.test(String(url))) { Qt.callLater(() => finish(0, "", {})); return { abort: function () {} } }
        usage.http++
        var x = new XMLHttpRequest()
        var timer = api.setTimeout(() => { x.abort(); finish(0, "", {}) }, opts.timeout || 30000)
        x.onreadystatechange = function () {
            if (x.readyState !== XMLHttpRequest.DONE) return
            api.clearTimer(timer)
            var h = {}
            for (var line of (x.getAllResponseHeaders() || "").split(/\r?\n/)) {
                var i = line.indexOf(":")
                if (i > 0) h[line.slice(0, i).trim().toLowerCase()] = line.slice(i + 1).trim()
            }
            finish(x.status, x.responseText, h)
        }
        x.open(opts.method || "GET", String(url))
        for (var k in (opts.headers || {})) x.setRequestHeader(k, String(opts.headers[k]))
        var body = opts.body
        x.send(body === undefined ? null : typeof body === "string" ? body : JSON.stringify(body))
        return { abort: function () { api.clearTimer(timer); x.abort(); finish(0, "", {}) } }
    }

    // ---------- сообщения между плагинами: api.send(id | "*", name, data) → у получателя onMessage(from, name, data) ----------
    // Части одного плагина (раздел, служба, элемент бара) пишут друг другу без разрешения: send(свой id, …) доходит
    // до остальных частей, но не до самой себя. С другими плагинами — разрешение «messages» у обоих.
    signal message(string from, string name, var data)
    function send(to, name, data) {
        if (!me) return false
        to = String(to)
        if (to !== me && !need("messages", "send")) return false
        var copy = data === undefined ? null : JSON.parse(JSON.stringify(data))   // получателю — копия, не общий объект
        Core.root.pluginMessage(me, to, String(name), copy, api)
        return true
    }
    property Connections busConn: Connections {
        target: Core.root
        ignoreUnknownSignals: true
        function onPluginMessage(from, to, name, data, sender) {
            if (!api.me || sender === api || (to !== api.me && to !== "*")) return
            if (from !== api.me && !api.can("messages")) return   // чужие — только с разрешением; «*» без него — лишь своим
            api.message(from, name, data)
        }
    }
    Component.onDestruction: { island.clear(); Core.setSearch(api, me, null); if (Core.confirms) Core.confirms.dropScope(api); if (Core.clipwatch) Core.clipwatch.listen(api, false); Permissions.unregister(api) }
}
