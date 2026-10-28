pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Настройки панели (раздел "panel" в ~/.config/glide-shell/config.json).
// data заполняет shell.qml из qp-discover; set() пишет через tools/qp-config.py и шлёт saved().
Singleton {
    id: prefs
    // Последний ответ qp-discover (настройки, категории, плагины) — на диске: при старте он читается сразу,
    // и оболочка с первого кадра живёт с настройками пользователя, а не с умолчаниями, пока идёт discover
    // (при входе на HDD это бывало 10+ с, и всё перестраивалось). Свежий discover потом приходит в фоне.
    readonly property string cachePath: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state")
                                        + "/glide-shell/discover-cache.json"
    FileView { id: cacheFile; path: prefs.cachePath; blockLoading: true; printErrors: false }
    readonly property string cachedRaw: { try { return cacheFile.text() } catch (e) { return "" } }
    function saveCache(raw) { if (raw !== cachedRaw) cacheFile.setText(raw) }
    property var data: { try { return JSON.parse(cachedRaw).panel || {} } catch (e) { return {} } }
    signal saved()

    // «тёплый» старт: фоновые помощники на Python (погода, KDE Connect, камера, агент Bluetooth) запускаются
    // через несколько секунд — пока оболочка и бар грузятся, они не толкаются с ними за диск
    property bool warm: false
    Timer { running: true; interval: 6000; onTriggered: prefs.warm = true }

    // открывать наведением на край/остров; с баром по умолчанию выключено — мышь часто ходит мимо часов
    readonly property bool edgeTrigger: data.edgeTrigger === undefined ? !bar : data.edgeTrigger === true
    readonly property bool edgePill: data.edgePill !== false           // видимая полоска у края
    readonly property int hoverDelay: num(data.hoverDelay, 120)        // мс до открытия по наведению
    readonly property int width: num(data.width, 380)                  // ширина карточки
    readonly property int perPage: Math.max(3, num(data.perPage, 6))   // категорий на странице рейки
    readonly property string lang: ["ru", "en"].indexOf(data.lang) >= 0 ? data.lang : "auto"   // язык интерфейса (Tr.qml)
    readonly property real anim: num(data.anim, 1)                     // множитель длительности, 0 — без анимаций
    readonly property bool dim: data.dim !== false                     // затемнять фон
    readonly property string style: data.style === "edge" ? "edge" : "island"   // остров сверху или рейка у края
    readonly property bool islandOverBar: data.islandOverBar === true  // остров поверх чужого бара, а не под ним
    readonly property bool bar: data.bar !== false                     // свой верхний бар с островом по центру (при любом виде)
    readonly property bool islandMusic: data.islandMusic !== false     // играющая музыка в острове
    readonly property bool islandFlash: data.islandFlash !== false     // подтверждения действий в острове
    readonly property bool islandNotif: data.islandNotif !== false     // всплывающие уведомления в острове (история — всегда)
    // поиск: файлы домашней папки (tools/glide-files.py, свой индекс) и «искать в интернете» последним пунктом
    // мастер первого запуска (Welcome.qml): welcome ставит setup.sh в первые настройки, welcomeDone — пройден/пропущен
    readonly property bool welcome: data.welcome === true
    readonly property bool welcomeDone: data.welcomeDone === true
    readonly property bool fileSearch: data.fileSearch !== false
    readonly property bool pluginLock: data.pluginLock !== false   // включать/выключать плагины — только по паролю
    readonly property var pluginSettings: data.pluginSettings || ({})        // настройки плагинов из plugin.json: {id: {key: value}}
    function setPluginSetting(id, key, value) {
        var all = JSON.parse(JSON.stringify(pluginSettings))
        all[id] = Object.assign({}, all[id] || {}); all[id][key] = value
        set("pluginSettings", all)
    }
    readonly property bool archUpdates: data.archUpdates !== false          // обновления Arch в баре (ArchUpdates.qml)
    readonly property bool updateCheck: data.updateCheck !== false        // искать обновления раз в 6 ч (Updates.qml)
    readonly property string updateNotified: data.updateNotified || ""     // о какой версии уже сказали
    readonly property string webSearch: ["duckduckgo", "google", "yandex", "bing", "off"].indexOf(data.webSearch) >= 0 ? data.webSearch : "duckduckgo"
    readonly property bool islandTimer: data.islandTimer !== false     // таймер в острове
    // значки у часов острова: [{id, side: left|right, on}] — порядок, сторона, включён; видны, только когда есть что показать
    readonly property var islandIconIds: ["weather", "battery", "notif", "dnd", "vpn", "mic", "volume", "bt", "awake", "night", "layout", "ptimer"]
    readonly property var islandIcons: {
        var out = Array.isArray(data.islandIcons)
            ? data.islandIcons.filter(x => x && islandIconIds.indexOf(x.id) >= 0).map(x => ({ id: x.id, side: x.side === "left" ? "left" : "right", on: x.on === true }))
            : [{ id: "weather", side: "right", on: data.islandWeather !== false }]   // прежняя настройка «температура у часов»
        for (var id of islandIconIds) if (!out.some(x => x.id === id)) out.push({ id: id, side: "right", on: id === "ptimer" })   // таймер выключения — виден сразу
        return out
    }
    // порядок строк острова (и что главнее в компактном виде): чего нет в списке — дописывается в конец
    readonly property bool islandLive: data.islandLive !== false   // «живые активности» в острове
    readonly property var islandKinds: ["osd", "flash", "rec", "live", "notif", "music", "timer"]   // live — Activities.qml
    readonly property var islandOrder: {
        var o = Array.isArray(data.islandOrder) ? data.islandOrder.filter(k => islandKinds.indexOf(k) >= 0) : []
        for (var k of islandKinds) if (o.indexOf(k) < 0) o.push(k)
        return o
    }
    readonly property bool islandPrivacy: data.islandPrivacy !== false // остров окрашивается, пока пишут камеру/микрофон
    // активности в острове с баром: inline — в строке часов (остров не ниже бара); raise — строками, но остров
    // прижимается к верхнему краю; stack — строками под часами
    readonly property string islandMode: ["inline", "raise", "stack"].indexOf(data.islandMode) >= 0 ? data.islandMode
                                         : data.islandInline === false ? "stack" : "inline"
    readonly property bool islandInline: islandMode === "inline"

    // ---- вид ----
    readonly property string iconFont: "JetBrainsMono Nerd Font"       // значки категорий, плагинов и бара
    readonly property color accent: /^#[0-9a-fA-F]{6}$/.test(data.accent || "") ? data.accent : "#7b61ff"   // фиолетовый Glide
    readonly property color accentSoft: Qt.rgba(accent.r, accent.g, accent.b, 0.22)    // фон выделенного
    readonly property color accentHover: Qt.rgba(accent.r, accent.g, accent.b, 0.42)
    readonly property real bounce: num(data.bounce, 1)                 // упругость пружин: 0 — без отскока
    // ---- тема (Theme.qml) ----
    // тема: dark | light | auto (днём светлая, после заката тёмная — закат и восход из погоды); тон — у тёмной
    readonly property string themeMode: ["dark", "light", "auto"].indexOf(data.themeMode) >= 0 ? data.themeMode : "dark"
    readonly property bool niriAccent: data.niriAccent === true   // рамка фокуса и обводка окон niri — цветом акцента
    readonly property bool themeApps: data.themeApps !== false     // светлая/тёмная схема и акцент — приложениям (gsettings)
    readonly property bool themeGtk3: data.themeGtk3 === true      // и тема GTK3: Adwaita / Adwaita-dark
    readonly property string themeTone: ["glide", "amoled", "soft"].indexOf(data.themeTone) >= 0 ? data.themeTone : "glide"
    readonly property real themeRadius: Math.max(0, Math.min(1.6, num(data.themeRadius, 1)))     // масштаб скруглений
    readonly property real themeFont: Math.max(0.85, Math.min(1.2, num(data.themeFont, 1)))      // масштаб шрифта
    readonly property real themeOpacity: Math.max(0.5, Math.min(1, num(data.themeOpacity, 1)))   // фон бара/острова/дока/панели
    readonly property bool themeWallpaper: data.themeWallpaper !== false   // обои (webpaper) — в цветах акцента
    // обои: scene — HTML-сцена webpaper (красится в акцент), image — картинка Glide Shell (Wallpaper.qml)
    readonly property string wallMode: data.wallMode === "scene" ? "scene" : "image"   // scene — нужна служба webpaper
    readonly property string wallPath: typeof data.wallPath === "string" && data.wallPath ? data.wallPath : "~/Изображения/Обои"
    readonly property int wallEvery: num(data.wallEvery, 0)               // минут до следующей картинки папки, 0 — не менять
    readonly property bool wallTheme: data.wallTheme !== false            // акцент и тон — из картинки
    readonly property string wallFit: data.wallFit === "fit" ? "fit" : "fill"
    readonly property int wallFps: [15, 24, 30, 60].indexOf(data.wallFps) >= 0 ? data.wallFps : 30   // кадров в секунду у GIF/видео
    readonly property bool wallBatteryPause: data.wallBatteryPause !== false   // от батареи анимация стоит
    // виджеты рабочего стола: [{id, type: clock|date|weather|music|system|text, screen ("" — главный), anchor
    // (tl t tr l c r bl b br), dx, dy, size (0.75…2), color (text|accent|muted), opacity, …свои поля типа}]
    readonly property var widgets: Array.isArray(data.widgets) ? data.widgets : []
    readonly property string wallScene: typeof data.wallScene === "string" ? data.wallScene : ""   // HTML-сцена webpaper ("" — как в службе)

    // ---- остров ----
    readonly property int flashMs: num(data.flashMs, 2200)             // сколько держится подтверждение
    readonly property int battWarn: num(data.battWarn, 20)             // % — предупредить о низком заряде (0 — нет)
    readonly property int battCrit: num(data.battCrit, 10)             // % — срочное предупреждение
    // ночной свет (NightLight.qml, wlsunset): off / on — всегда / auto — от заката до восхода
    readonly property string night: ["off", "on", "auto"].indexOf(data.night) >= 0 ? data.night : "off"
    readonly property string nightLast: data.nightLast === "auto" ? "auto" : "on"   // куда включает плитка
    readonly property int nightTemp: num(data.nightTemp, 4500)        // K
    readonly property bool islandOsd: data.islandOsd !== false        // громкость, яркость и т. п. в острове
    readonly property int musicGrace: num(data.musicGrace, 6)          // с после паузы; -1 — пока открыт плеер
    // эквалайзер: smooth — плавно (60 кадров/с, заметно грузит), eco — ступеньками, off — неподвижный
    readonly property string eqMode: ["smooth", "eco", "off"].indexOf(data.eqMode) >= 0 ? data.eqMode : "eco"

    // ---- док ----
    readonly property bool dock: data.dock !== false
    // smart — виден на пустом воркспейсе и по наведению; autohide — только по наведению;
    // always — всегда виден и резервирует место под собой
    readonly property string dockMode: ["smart", "autohide", "always"].indexOf(data.dockMode) >= 0 ? data.dockMode : "smart"
    readonly property int dockIcon: num(data.dockIcon, 40)
    readonly property var dockPinned: Array.isArray(data.dockPinned) ? data.dockPinned : null   // null — ещё не перенесено из DMS
    readonly property bool dockButtons: data.dockButtons !== false     // «Приложения» и «Обзор» по краям

    // ---- уведомления: свой сервер вместо DMS (имя на шине одно — пока жив DMS, оно у него) ----
    readonly property bool notifications: data.notifications === true
    readonly property var notifMuted: Array.isArray(data.notifMuted) ? data.notifMuted : []   // приложения без всплывашек
    function notifMute(app, on) {
        var m = notifMuted.filter(x => x !== app)
        if (on) m.push(app)
        set("notifMuted", m)
    }
    readonly property bool notifKeep: data.notifKeep !== false             // история уведомлений переживает перезапуск
    readonly property bool polkit: data.polkit === true                 // своё окно пароля polkit (агент тоже один)
    // «не беспокоить» сам: ночью (часы с dndFrom до dndTo) и пока идёт демонстрация экрана
    readonly property bool dndSchedule: data.dndSchedule !== false
    readonly property int dndFrom: num(data.dndFrom, 23)
    readonly property int dndTo: num(data.dndTo, 8)
    readonly property bool dndCasting: data.dndCasting !== false
    // приватность уведомлений: full — всё, title — без текста, app — только «Новое уведомление» и приложение
    readonly property string notifContent: ["full", "title", "app"].indexOf(data.notifContent) >= 0 ? data.notifContent : "full"
    readonly property bool notifHideCapture: data.notifHideCapture !== false   // запись/демонстрация — как «app»
    readonly property bool overlayPin: data.overlayPin === true      // плашка оверлея в углу (Overlay.qml)
    readonly property var automations: Array.isArray(data.automations) ? data.automations : []   // правила (Automation.qml)
    readonly property string recOutput: typeof data.recOutput === "string" ? data.recOutput : ""   // монитор записи; "" — где фокус
    readonly property var privacyApps: Array.isArray(data.privacyApps) ? data.privacyApps : []   // скрыты на записи (niri)

    // ---- KDE Connect: телефон в панели и баре ----
    readonly property bool kdeconnect: data.kdeconnect !== false
    // ---- съёмные диски (Drives.qml, плагин drives): следить и подключать вставленное само ----
    readonly property bool drives: data.drives !== false
    readonly property bool drivesAutomount: data.drivesAutomount !== false

    // ---- погода (Weather.qml) ----
    readonly property bool weather: data.weather !== false
    readonly property bool holidays: data.holidays !== false             // праздники и переносы РФ в календаре
    readonly property string weatherCity: typeof data.weatherCity === "string" ? data.weatherCity.trim() : ""   // "" — сама
    readonly property bool islandWeather: data.islandWeather !== false   // температура у часов в острове

    // ---- вид экрана блокировки ----
    readonly property int lockClockSize: num(data.lockClockSize, 112)                  // пикселей: 56 / 80 / 112 / 140
    readonly property bool lockClockBold: data.lockClockBold === true                  // жирные цифры вместо тонких
    // анимация после верного пароля (замок и экран входа): rise | iris | curtains | tiles | zoom | island | random
    readonly property string unlockStyle: ["rise", "iris", "curtains", "tiles", "zoom", "island", "random"].indexOf(data.unlockStyle) >= 0 ? data.unlockStyle : "rise"
    // glow | solid | wallpaper (как обои рабочего стола) | image (lockImage: файл или папка — случайная при каждой блокировке)
    readonly property string lockBackground: ["glow", "solid", "wallpaper", "image"].indexOf(data.lockBackground) >= 0 ? data.lockBackground : "glow"
    readonly property string lockImage: typeof data.lockImage === "string" ? data.lockImage.trim() : ""   // путь к картинке или папке
    readonly property real lockDim: Math.max(0, Math.min(0.8, num(data.lockDim, 0.45)))   // затемнение картинки: 0 / 0.25 / 0.45 / 0.65
    readonly property int lockBlur: [0, 32, 64].indexOf(data.lockBlur) >= 0 ? data.lockBlur : 0   // размытие: нет / лёгкое / сильное
    readonly property string lockGreeting: typeof data.lockGreeting === "string" ? data.lockGreeting : ""
    readonly property bool lockShowUser: data.lockShowUser !== false
    readonly property bool lockShowMedia: data.lockShowMedia !== false
    readonly property bool lockShowUnread: data.lockShowUnread !== false
    readonly property bool lockShowBattery: data.lockShowBattery !== false
    readonly property bool lockShowLayout: data.lockShowLayout !== false

    // ---- блокировка ----
    readonly property bool lockBeforeSleep: data.lockBeforeSleep !== false   // запирать экран перед сном
    readonly property int idleOff: Math.max(0, num(data.idleOff, 5))     // мин бездействия до гашения экрана, 0 — никогда
    readonly property int idleLock: Math.max(0, num(data.idleLock, 10))  // мин бездействия до блокировки, 0 — никогда

    // ---- бар ----
    readonly property string clockDate: ["long", "short", "none"].indexOf(data.clockDate) >= 0 ? data.clockDate : "long"
    readonly property bool clockSeconds: data.clockSeconds === true
    readonly property bool barAllWorkspaces: data.barAllWorkspaces === true   // и пустые воркспейсы
    // несколько мониторов: unite — один бар на весь стол (левая капсула у левого края крайнего левого монитора,
    // правая — у правого края крайнего правого, остров на главном); extend — весь бар на главном, на соседних —
    // продолжение: их столы и окно; mirror — полный бар на каждом (свои столы); standard — бар только на главном
    readonly property string monitorMode: ["unite", "extend", "mirror", "standard"].indexOf(data.monitorMode) >= 0 ? data.monitorMode : "extend"
    readonly property string mainScreen: typeof data.mainScreen === "string" ? data.mainScreen : ""   // "" — в фокусе
    readonly property bool dockAllScreens: data.dockAllScreens !== false      // док на каждом мониторе
    readonly property bool barWsIcons: data.barWsIcons !== false       // иконки приложений на воркспейсах
    readonly property var barHide: Array.isArray(data.barHide) ? data.barHide : []   // прежний список скрытых (перенос)
    // элементы боковых островов бара: [{id, place: left | right | off}] — порядок и место каждого (Bar.qml, PartSlot)
    readonly property var barLeftDefault: ["power", "workspaces", "window"]
    readonly property var barRightDefault: ["layout", "cpu", "mem", "clipboard", "notifications", "battery", "phone", "vpn", "awake", "control", "tray"]
    readonly property var barExtra: ["volume", "mic", "bluetooth", "night", "weather", "powerprofile", "screenshot", "net"]   // новые — выключены
    readonly property var barNewOn: ["updates"].concat(pluginBars)   // новые, но включённые сразу (видны, когда есть что показать)
    property var pluginBars: []   // элементы бара из плагинов («plugin:<id>», plugin.json «bar») — задаёт shell.qml
    readonly property var barItems: {
        var known = barLeftDefault.concat(barRightDefault, barExtra, barNewOn)
        var out = Array.isArray(data.barItems)
            ? data.barItems.filter(x => x && known.indexOf(x.id) >= 0).map(x => ({ id: x.id, place: ["left", "right"].indexOf(x.place) >= 0 ? x.place : "off" }))
            : barLeftDefault.map(id => ({ id: id, place: barHide.indexOf(id) >= 0 ? "off" : "left" }))
                .concat(barRightDefault.map(id => ({ id: id, place: barHide.indexOf(id) >= 0 ? "off" : "right" })))
        for (var id of known) {
            if (out.some(x => x.id === id)) continue
            if (barNewOn.indexOf(id) < 0) { out.push({ id: id, place: "off" }); continue }
            var at = out.findIndex(x => x.id === "control")   // включённое новое — перед «Управлением»
            out.splice(at >= 0 ? at : out.length, 0, { id: id, place: "right" })
        }
        return out
    }
    function barShows(id) { var x = barItems.find(i => i.id === id); return !!x && x.place !== "off" }
    function toggleBarItem(id) {   // прежний вызов: скрыть / вернуть на место по умолчанию
        set("barItems", barItems.map(x => x.id !== id ? x : ({ id: id, place: x.place !== "off" ? "off"
                                                                : barLeftDefault.indexOf(id) >= 0 ? "left" : "right" })))
    }

    function num(v, def) { return typeof v === "number" && isFinite(v) ? v : def }
    function ms(d) { return Math.round(d * anim) }

    // Записи в config.json идут строго по очереди (JobQueue: своя занятость — running становится true не сразу,
    // и прежняя очередь здесь теряла все быстрые записи, кроме последней)
    function run(args) { writer.add(["python3", Quickshell.shellDir + "/tools/qp-config.py"].concat(args)) }

    function set(key, value) {
        var d = Object.assign({}, data)   // сразу применяем локально, файл догонит
        d[key] = value
        data = d
        run(["set", "panel." + key, JSON.stringify(value)])
    }
    function reset() { data = ({}); run(["reset-panel"]) }

    JobQueue {
        id: writer
        stderr: StdioCollector { onStreamFinished: if (text.trim()) console.warn("glide-shell:", text.trim()) }
        onFinished: if (!jobs.length) prefs.saved()
    }
}
