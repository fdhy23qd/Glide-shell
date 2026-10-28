import QtQuick
import QtQml
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower

// Glide Shell — оболочка рабочего стола из экосистемы Glide: бар, остров, панель быстрых действий.
// Ядро рисует панель и запускает команды; всё содержимое приходит из плагинов.
ShellRoot {
    id: root

    property bool shown: false
    property var plugins: []
    property var categories: []
    property string pluginsRaw: ""
    property string profile: ""
    property string category: ""
    property string query: ""
    property var ctx: ({ window: null, selection: "", clipboard: "" })   // снимок в момент вызова
    property var allPlugins: []           // все плагины, включая выключенные (для настроек)
    property bool settingsOpen: false
    property string settingsPage: "look"
    function editDesktop(on) { if (on !== false) close(); desktopWidgets.editing = on !== false }
    property string widgetToOpen: ""   // какой виджет раскрыть в настройках («Виджеты»; правая кнопка по виджету в правке)   // открытый раздел настроек (запоминается до перезапуска)
    property int railPage: 0              // текущая страница категорий на рейке
    property int railDir: 1               // направление последнего перелистывания (для анимации)
    property var handoff: null            // {to, text, prompt, ts}: текст, переданный другому плагину (чату ИИ)
    property bool preferItemFocus: true   // поля с "autofocus" забирают фокус при открытии
    property int selected: 0              // выбранный результат поиска (↑/↓)

    // 0 → 1 при открытии; окно остаётся на экране, пока идёт анимация закрытия
    property real reveal: shown ? 1 : 0
    Behavior on reveal {
        NumberAnimation {
            duration: Prefs.ms(root.shown ? (root.island ? 460 : 320) : (root.island ? 150 : 200))
            easing.type: root.shown ? (root.island ? Easing.OutCubic : Easing.OutExpo) : Easing.InCubic
        }
    }
    // в острове содержимое проявляется, когда фигура уже заметно выросла
    readonly property real contentReveal: island ? Math.max(0, (reveal - 0.35) / 0.65) : reveal

    // ---------- остров ----------
    readonly property bool island: Prefs.style === "island"
    readonly property bool barOn: Prefs.bar              // свой бар (Bar.qml); остров — его центр
    // ---- мониторы: бар и док — на каждом (или только здесь), остров и панель — на мониторе в фокусе ----
    // переезжают, только пока панель закрыта: открытая не прыгает между экранами
    readonly property var focusedScreen: Quickshell.screens.find(s => s.name === Niri.focusedOutput) || Quickshell.screens[0] || null
    // главный монитор: выбранный в настройках (если подключён) или тот, что в фокусе
    readonly property var mainScreen: Quickshell.screens.find(s => Prefs.mainScreen !== "" && s.name === Prefs.mainScreen) || focusedScreen
    // крайние мониторы слева и справа — для режима «объединение»
    readonly property var leftmostScreen: Quickshell.screens.reduce((a, s) => !a || s.x < a.x ? s : a, null)
    readonly property var rightmostScreen: Quickshell.screens.reduce((a, s) => !a || s.x + s.width > a.x + a.width ? s : a, null)
    property var panelScreen: mainScreen
    onMainScreenChanged: followFocus()
    function followFocus() { if (!shown && !islandClosing && panelScreen !== mainScreen) panelScreen = mainScreen }
    onIslandClosingChanged: Qt.callLater(followFocus)
    function onScreen(list, s) { return list.find(x => x && x.screen === s) || list[0] || null }
    readonly property var mainBar: onScreen(bars.instances, panelScreen)     // бар монитора с островом (IPC, вспышки)
    readonly property var mainDock: onScreen(docks.instances, panelScreen)
    // бары с левой и правой капсулой (в «объединении» это могут быть разные мониторы) — для IPC и полёта в колокольчик
    readonly property var leftBar: bars.instances.find(b => b && b.showLeft) || mainBar
    readonly property var rightBar: bars.instances.find(b => b && b.showRight) || mainBar
    readonly property bool islandShown: island || barOn  // компактный остров виден и при рейке у края, если есть бар
    readonly property bool islandOver: barOn || Prefs.islandOverBar   // остров отсчитывается от края экрана
    readonly property int barHeight: 44
    readonly property int edgeTop: barOn ? barHeight : 0   // рейка у края не залезает на бар
    // режим «прижать к верху»: пока в острове активность, он поднимается вплотную к краю экрана
    readonly property int islandTop: Prefs.islandMode === "raise" && activity !== "idle" && activity !== "" ? 0 : 6
    readonly property int islandRadius: Theme.radiusXl
    // пока приложение пишет камеру или микрофон или идёт демонстрация (запись) экрана, остров окрашивается: камера —
    // зелёным, микрофон — янтарным, экран — красным; за ними — цвета плагинов (api.island.tint, не больше трёх).
    // Один цвет — заливка с оттенком и обводка; несколько — неподвижный градиент (IslandTint)
    readonly property bool castOn: Niri.casts.length > 0 || Recorder.recording
    readonly property bool privacyOn: Prefs.islandPrivacy && (camApps.length > 0 || micApps.length > 0 || castOn)
    readonly property var islandColors: {
        var c = []
        if (Prefs.islandPrivacy) {
            if (camApps.length) c.push(Theme.success)
            if (micApps.length) c.push(Theme.warning)
            if (castOn) c.push(Theme.error)
        }
        for (var t of Core.islandTints.slice(-3)) c.push(t.color)
        return c
    }
    readonly property color islandOne: islandColors.length === 1 ? islandColors[0] : Theme.outline
    readonly property color islandColor: islandColors.length === 1 ? Qt.tint(Theme.backgroundBar, Qt.rgba(islandOne.r, islandOne.g, islandOne.b, 0.16))
                                                   : Theme.backgroundBar   // и раскрытая панель (blob) — тем же цветом
    readonly property color islandBorder: islandColors.length > 1 ? "transparent" : islandOne   // обводка, как у карточек Glide
    property bool islandHover: false      // курсор над островом (уход — с задержкой)
    property bool islandClosing: false    // панель закрыта, но фигура ещё сжимается в остров
    property double closedAt: 0
    readonly property bool panelVisible: win.visible
    readonly property bool blobAtCompact: win.blobSettled   // фигура панели совпадает с островом
    readonly property bool islandPeek: islandHover && !shown
    readonly property int islandCats: Math.min(categories.length, 6)
    onShownChanged: if (!shown) {
        closedAt = Date.now()
        if (island && Prefs.anim > 0) islandClosing = true
        Qt.callLater(followFocus)   // фокус ушёл на другой монитор, пока панель была открыта
    }
    Timer { running: root.islandClosing; interval: 2500; onTriggered: root.islandClosing = false }   // страховка

    // что сейчас показывает остров
    // что сейчас показывает остров: первое по порядку из настроек (Prefs.islandOrder), что есть
    function activityOn(k) {
        return k === "osd" ? !!osd : k === "flash" ? !!flashMsg : k === "rec" ? recOn : k === "notif" ? !!notif
             : k === "music" ? musicOn : k === "timer" ? timerOn : k === "live" ? liveOn : false
    }
    readonly property string activity: {
        if (!islandShown) return ""
        for (var k of Prefs.islandOrder) if (activityOn(k)) return k
        return "idle"
    }
    readonly property var notif: Prefs.islandNotif ? Notifs.popup : null   // всплывающее уведомление
    readonly property bool notifActions: !!notif && (notif.actions.length > 0 || notif.reply)
    property bool replying: false        // в острове пишут ответ на уведомление (Island.qml)
    onNotifChanged: replying = false
    Binding { target: Notifs; property: "replyLock"; value: root.replying }
    // С баром остров — стопка строк: сверху всегда часы, под ними как продолжение острова
    // строки активностей (подтверждение, музыка, таймер); наведение раскрывает строки.
    property real clockIconsW: 0          // значки у часов (Island.qml сообщает ширину видимых)
    readonly property int clockW: Math.ceil(clockTimeMetrics.advanceWidth + (clockDate ? clockDateMetrics.advanceWidth + 8 : 0)
                                            + clockIconsW) + 32   // 32: отступы
    // погода у часов: значок и температура
    readonly property string clockWeather: Prefs.islandWeather && Weather.ok ? Weather.temp(Weather.data.now.temp) : ""
    readonly property int flashW: Math.min(380, Math.max(140, Math.ceil(flashMetrics.advanceWidth) + 64))
    // Компактный вид (Prefs.islandInline): главная активность — в строке часов, справа от времени;
    // остров не выше бара и не заслоняет окна. Стопка строк — только при наведении (или без компактного вида).
    readonly property bool stacked: barOn && (!Prefs.islandInline || islandPeek)
    readonly property bool inlineAct: barOn && !stacked && activity !== "idle" && activity !== ""
    readonly property int inlineX: Math.ceil(clockTimeMetrics.advanceWidth) + 30   // где начинается активность
    readonly property int inlineActW: {
        switch (activity) {
        case "osd": return osd && osd.value < 0 ? 240 : 210
        case "flash": return Math.min(300, flashW - 16)
        case "notif": return 300
        case "music": return 232
        case "timer": return 150
        case "rec": return 160
        case "live": return 230
        }
        return 0
    }
    readonly property int rowOsdH: stacked && osd ? 32 : 0
    readonly property int rowFlashH: stacked && flashMsg ? 32 : 0
    readonly property int notifPeekH: notifActions ? 116 : 84
    readonly property int rowNotifH: stacked && notif ? (islandPeek ? notifPeekH : 32) : 0
    readonly property int rowMusicH: stacked && musicOn ? (islandPeek ? 88 : 32) : 0
    readonly property int rowTimerH: stacked && timerOn ? (islandPeek ? 64 : 32) : 0
    readonly property bool recOn: Recorder.recording           // запись экрана
    readonly property int rowRecH: stacked && recOn ? 32 : 0
    readonly property bool liveOn: Prefs.islandLive && Activities.list.length > 0   // «живые активности» плагинов и приложений
    readonly property int rowLiveH: stacked && liveOn ? (islandPeek ? 64 : 32) : 0
    function rowH(k) {
        return k === "osd" ? rowOsdH : k === "flash" ? rowFlashH : k === "notif" ? rowNotifH : k === "music" ? rowMusicH
             : k === "timer" ? rowTimerH : k === "rec" ? rowRecH : k === "live" ? rowLiveH : 0
    }
    function rowY(k) {   // строки стопки — в порядке из настроек
        var y = 32
        for (var x of Prefs.islandOrder) { if (x === k) return y; y += rowH(x) }
        return y
    }
    readonly property int rowsH: rowOsdH + rowFlashH + rowNotifH + rowMusicH + rowTimerH + rowRecH + rowLiveH
    readonly property int osdW: osd && osd.value < 0 ? 300 : 260
    readonly property int compactRadius: barOn && rowsH ? 18 : islandRadius   // у стопки строк углы скромнее
    readonly property int compactW: {
        if (barOn && !stacked) return inlineAct ? inlineX + inlineActW : clockW
        if (barOn) return Math.max(clockW + (islandPeek && rowsH === 0 ? 16 : 0),
                                   rowOsdH ? osdW : 0,
                                   rowFlashH ? flashW : 0,
                                   rowNotifH ? (islandPeek ? 400 : 320) : 0,
                                   rowMusicH ? (islandPeek ? 360 : 232) : 0,
                                   rowTimerH ? (islandPeek ? 300 : 168) : 0,
                                   rowRecH ? 200 : 0,
                                   rowLiveH ? (islandPeek ? 340 : 250) : 0)
        switch (activity) {
        case "osd": return osdW
        case "flash": return flashW
        case "notif": return islandPeek ? 400 : 320
        case "music": return islandPeek ? 360 : 232
        case "timer": return islandPeek ? 300 : 168
        case "rec": return 200
        case "live": return islandPeek ? 340 : 250
        }
        if (islandPeek && islandCats > 0) return islandCats * 32 + 18
        return islandPeek ? 156 : (Prefs.edgePill ? 112 : 140)
    }
    readonly property int compactH: {
        if (barOn && !stacked) return 32   // компактно: одна строка, в высоту бара
        if (barOn) return (islandPeek && rowsH === 0 ? 36 : 32) + rowsH + (rowsH ? 4 : 0)
        switch (activity) {
        case "osd": return 34
        case "flash": return 34
        case "notif": return islandPeek ? notifPeekH : 34
        case "music": return islandPeek ? 88 : 32
        case "timer": return islandPeek ? 64 : 32
        case "rec": return 34
        case "live": return islandPeek ? 64 : 34
        }
        return islandPeek ? 36 : (Prefs.edgePill ? 28 : 8)
    }

    // часы: в покое остров с баром показывает время и дату
    property date clockNow: new Date()
    readonly property string clockTime: Qt.formatTime(clockNow, Prefs.clockSeconds ? "HH:mm:ss" : "HH:mm")
    readonly property string clockDate: Prefs.clockDate === "none" ? ""
        : Tr.locale.toString(clockNow, Prefs.clockDate === "short" ? "ddd dd.MM" : "ddd, d MMMM")
    Timer {   // без секунд часы просыпаются раз в минуту, ровно на её границе
        id: clockTick
        running: root.barOn
        repeat: true
        interval: 1000
        onTriggered: {
            root.clockNow = new Date()
            desktopWidgets.tick()
            interval = Prefs.clockSeconds ? 1000
                     : 60000 - root.clockNow.getSeconds() * 1000 - root.clockNow.getMilliseconds() + 20
        }
    }
    Connections { target: Prefs; function onClockSecondsChanged() { clockTick.interval = 1000; clockTick.restart() } }
    TextMetrics { id: clockTimeMetrics; font.pixelSize: Theme.fs(13); font.bold: true; text: root.clockTime }
    TextMetrics { id: clockDateMetrics; font.pixelSize: Theme.fs(12); text: root.clockDate }
    TextMetrics { id: clockWxMetrics; font.pixelSize: Theme.fs(12); text: root.clockWeather }
    function openFromIsland(kind) {   // клик по острову: категория активности (по умолчанию — текущей)
        if (kind === undefined) kind = activity
        if (kind === "osd") { openCategory("control"); return }
        // часы → «Управление» (там тоже время и дата; календарь — щелчком по ним); нет его — «Сегодня»
        if (kind === "idle" && barOn) {
            var to = ["control", "today"].find(id => categories.some(c => c.id === id))
            if (to) { openCategory(to); return }
        }
        if (kind === "notif") { if (!Notifs.activate(notif)) openCategory("notify"); return }
        if (kind === "rec") { Recorder.stop(); return }   // клик по строке записи — остановить
        if (kind === "live") { if (Activities.top) Activities.click(Activities.top.id); return }
        var p = kind === "music" ? pluginById("music") : kind === "timer" ? pluginById("timer") : null
        if (p) openCategory(p.categories[0]); else open()
    }

    // ---------- OSD: громкость, микрофон, яркость, профиль питания, выход звука ----------
    property var osd: null            // {icon, label, value: 0..1 или -1 (без полосы), text}
    property bool osdArmed: false     // сразу после запуска значения «меняются» сами — молчим
    property double sinkChangedAt: 0
    Timer { running: true; interval: 3000; onTriggered: root.osdArmed = true }
    Timer { id: osdTimer; interval: 1600; onTriggered: root.osd = null }
    function nf(code) { return String.fromCodePoint(code) }
    function showOsd(icon, label, value, text) {
        if (!osdArmed || !islandShown || !Prefs.islandOsd || shown) return
        osd = { icon: icon, label: label, value: value, text: text }
        osdTimer.restart()
    }
    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var source: Pipewire.defaultAudioSource
    PwObjectTracker { objects: [root.sink, root.source].filter(o => !!o) }
    function volumeOsd() {
        var a = sink && sink.audio
        if (!a || Date.now() - sinkChangedAt < 1500) return   // новый выход только подключился
        var v = a.volume
        showOsd(a.muted ? nf(0xF0581) : v > 0.66 ? nf(0xF057E) : v > 0.33 ? nf(0xF0580) : nf(0xF057F),
                Tr.t("Громкость"), a.muted ? 0 : Math.min(1, v), a.muted ? Tr.t("без звука") : Math.round(v * 100) + "%")
    }
    Connections {
        target: root.sink && root.sink.audio ? root.sink.audio : null
        function onVolumeChanged() { root.volumeOsd() }
        function onMutedChanged() { root.volumeOsd() }
    }
    Connections {
        target: root.source && root.source.audio ? root.source.audio : null
        function onMutedChanged() {
            var a = root.source.audio
            root.showOsd(a.muted ? root.nf(0xF036D) : root.nf(0xF036C), Tr.t("Микрофон"), -1, a.muted ? Tr.t("выключен") : Tr.t("включён"))
        }
        function onVolumeChanged() {
            var a = root.source.audio
            if (Date.now() - root.sinkChangedAt > 1500)
                root.showOsd(root.nf(0xF036C), Tr.t("Микрофон"), Math.min(1, a.volume), Math.round(a.volume * 100) + "%")
        }
    }
    property var lastSinkId: null
    onSinkChanged: {   // переключили выход звука
        sinkChangedAt = Date.now()
        if (sink && lastSinkId !== null && sink.id !== lastSinkId)
            showOsd(nf(0xF04C3), Tr.t("Выход звука"), -1, sink.description || sink.nickname || sink.name)
        if (sink) lastSinkId = sink.id
    }
    Connections {
        target: PowerProfiles
        function onProfileChanged() {
            var p = PowerProfiles.profile
            root.showOsd(p === PowerProfile.PowerSaver ? root.nf(0xF032A) : p === PowerProfile.Performance ? root.nf(0xF04C5) : root.nf(0xF05D1),
                         Tr.t("Профиль питания"), -1,
                         p === PowerProfile.PowerSaver ? Tr.t("экономия") : p === PowerProfile.Performance ? Tr.t("мощность") : Tr.t("баланс"))
        }
    }
    // ---------- раскладка и Caps Lock ----------
    Connections {
        target: Niri
        function onLayoutIdxChanged() {
            var n = Niri.layouts[Niri.layoutIdx] || ""
            var names = { English: "English", Russian: Tr.t("Русская"), Ukrainian: Tr.t("Українська"), German: "Deutsch" }
            root.showOsd(root.nf(0xF030C), Tr.t("Раскладка"), -1, names[n.split(/[\s(]/)[0]] || n)
        }
    }
    // У Caps Lock нет события ни в niri, ни в Quickshell — читаем светодиоды клавиатур
    // (/sys/class/leds/*::capslock). Петля на встроенных командах bash: read из файла и read -t вместо
    // sleep — без порождения процессов; печатает только изменения.
    // ---------- запись экрана: итог — вспышкой в острове ----------
    Connections {
        target: Recorder
        function onFinished(file, ok) {
            if (ok) root.flash("●", Tr.t("Запись сохранена в «Видео/Записи экрана»"), Theme.success)
            else root.flash("!", Tr.t("Запись не удалась: ") + Recorder.error, Theme.error)
        }
    }

    // ---------- камера и микрофон ----------
    // Камера: tools/glide-privacy.py — inotify на /dev/video* (браузеры открывают её мимо PipeWire).
    // Микрофон: потоки записи PipeWire; запись звука системы (визуализаторы, OBS — stream.capture.sink) не в счёт.
    property var camApps: []
    Process {
        running: Prefs.warm   // через несколько секунд после старта
        stdinEnabled: true   // закрытый stdin — сигнал помощнику выйти
        command: ["setpriv", "--pdeathsig", "TERM", "python3", "-I", Quickshell.shellDir + "/tools/glide-privacy.py"]
        stdout: SplitParser {
            onRead: line => {
                var m
                try { m = JSON.parse(line) } catch (e) { return }
                var fresh = m.camera.filter(a => root.camApps.indexOf(a) < 0)
                root.camApps = m.camera
                if (fresh.length) root.showOsd(root.nf(0xF0100), Tr.t("Камера"), -1, fresh.join(", "))
            }
        }
    }
    readonly property var micNodes: Pipewire.nodes.values.filter(n => n.type === PwNodeType.AudioInStream)
    PwObjectTracker { objects: root.micNodes }
    readonly property var micApps: {
        var out = []
        for (var n of micNodes) {
            var p = n.properties || {}
            if (p["stream.capture.sink"] === "true") continue
            var name = p["application.name"] || n.description || n.name || Tr.t("приложение")
            if (out.indexOf(name) < 0) out.push(name)
        }
        return out
    }
    property var micShown: []
    onMicAppsChanged: {
        var fresh = micApps.filter(a => micShown.indexOf(a) < 0)
        micShown = micApps
        if (fresh.length) showOsd(nf(0xF036C), Tr.t("Микрофон"), -1, fresh.join(", "))
    }

    property bool capsLock: false
    Process {
        running: true
        command: ["setpriv", "--pdeathsig", "TERM", "bash", "-c",
                  'exec 3<> <(:); p=; while :; do s=0; for f in /sys/class/leds/*::capslock/brightness; do '
                  + '[ -r "$f" ] && read -r v < "$f" && [ "$v" != 0 ] && s=1; done; '
                  + '[ "$s" != "$p" ] && { echo "$s"; p=$s; }; read -t 0.4 -u 3; done']
        stdout: SplitParser {
            onRead: line => {
                var on = line.trim() === "1"
                if (on === root.capsLock) return
                root.capsLock = on
                root.showOsd(root.nf(0xF0632), "Caps Lock", -1, on ? Tr.t("включён") : Tr.t("выключен"))
            }
        }
    }
    // ---------- низкий заряд: предупреждение один раз на порог, пока не поставят на зарядку ----------
    readonly property var battery: UPower.displayDevice
    readonly property bool battDischarging: !!battery && battery.isLaptopBattery && UPower.onBattery
    readonly property int battPct: battery ? Math.round(battery.percentage * 100) : 100
    property int battWarned: 101          // самый низкий порог, о котором уже сказали
    onBattDischargingChanged: if (!battDischarging) battWarned = 101; else checkBattery()
    onBattPctChanged: checkBattery()
    Timer { running: true; interval: 10000; onTriggered: root.checkBattery() }   // запустились уже на низком заряде
    function checkBattery() {
        if (!battDischarging) return
        var crit = Prefs.battCrit > 0 && battPct <= Prefs.battCrit
        var warn = Prefs.battWarn > 0 && battPct <= Prefs.battWarn
        var level = crit ? Prefs.battCrit : warn ? Prefs.battWarn : 101
        if (level >= battWarned) return
        battWarned = level
        var left = battery.timeToEmpty > 0 ? Math.round(battery.timeToEmpty / 60) : 0
        var text = Tr.t("Заряд ") + battPct + "%" + (left ? " · " + Tr.t("осталось ≈") + (left >= 60 ? Math.floor(left / 60) + Tr.t(" ч ") : "") + left % 60 + Tr.t(" мин") : "")
        runRaw(["notify-send", "-a", "Glide Shell", "-u", crit ? "critical" : "normal", "-i", "battery-caution",
                crit ? Tr.t("Батарея почти разряжена") : Tr.t("Низкий заряд"),
                text + (crit ? Tr.t(". Подключи зарядку") : "")], "", "")
    }

    readonly property bool nightOn: NightLight.on   // синглтон ленивый — без обращения ночной свет не запустится
    readonly property int drivesMounted: Drives.mounted.length   // и съёмные диски (уведомления о вставленном) — тоже
    readonly property bool updatesAvailable: Updates.available   // и проверка обновлений — тоже
    readonly property int archUpdates: ArchUpdates.count
    onPluginsChanged: Prefs.pluginBars = plugins.filter(p => p.bar).map(p => "plugin:" + p.id)

    // ---------- «не засыпать» ----------
    // Wayland idle-inhibit на окне острова — экран не гаснет (учитывают niri и демоны простоя),
    // systemd-inhibit idle:sleep — система не уходит в сон. Состояние переживает перезапуск.
    property bool awake: false
    FileView {
        id: awakeFile
        path: root.stateReady ? root.stateDir + "/awake" : ""
        printErrors: false
        onLoaded: root.awake = text().trim() === "1"
        onLoadFailed: awakeMigrate.running = true   // первый запуск: забираем состояние у DMS и старого плагина
    }
    Process {
        id: awakeMigrate
        command: ["sh", "-c", 'on=0; dms ipc call inhibit status 2>/dev/null | grep -qi enabled && on=1; '
                  + 'f="${XDG_RUNTIME_DIR:-/tmp}/glide-shell-awake.pid"; '
                  + '[ -f "$f" ] && kill "$(cat "$f")" 2>/dev/null && on=1; rm -f "$f"; '
                  + 'dms ipc call inhibit disable >/dev/null 2>&1; echo $on']
        stdout: StdioCollector { onStreamFinished: root.setAwake(text.trim() === "1", true) }
    }
    function setAwake(on, quiet) {
        awakeFile.setText(on ? "1\n" : "0\n")
        if (on === awake) return
        awake = on
        if (!quiet) showOsd(nf(on ? 0xF0176 : 0xF06CA), Tr.t("Не засыпать"), -1, on ? Tr.t("включено") : Tr.t("выключено"))
    }
    Process {   // блокировка сна живёт, пока живёт этот процесс
        running: root.awake
        // setpriv --pdeathsig: умирает вместе с оболочкой, иначе после перезапуска сирота держит сон вечно
        command: ["setpriv", "--pdeathsig", "TERM", "systemd-inhibit", "--what=idle:sleep", "--who=Glide Shell",
                  Tr.t("--why=Не засыпать"), "setpriv", "--pdeathsig", "TERM", "sleep", "infinity"]
    }
    IdleInhibitor { window: islandWin; enabled: root.awake }

    function brightnessOsd(pct) {   // зовёт tools/glide-brightness.sh после смены яркости
        showOsd(pct > 66 ? nf(0xF00E0) : pct > 33 ? nf(0xF00DF) : nf(0xF00DE), Tr.t("Яркость"), pct / 100, pct + "%")
    }

    // вспышка: короткое сообщение в острове
    property var flashMsg: null           // {icon, text, color}
    function flash(icon, text, color) {
        if (!islandShown) return
        flashMsg = { icon: icon || "✓", text: text || "", color: color || Theme.success }
        flashTimer.restart()
    }
    Timer { id: flashTimer; interval: Math.max(500, Prefs.flashMs); onTriggered: root.flashMsg = null }
    TextMetrics { id: flashMetrics; font.pixelSize: Theme.fs(13); text: root.flashMsg ? root.flashMsg.text : "" }

    // музыка: играющий плеер; после паузы остаётся ещё на несколько секунд
    readonly property var playingPlayer: {
        var vs = Mpris.players.values
        for (var i = 0; i < vs.length; i++) if (vs[i].isPlaying) return vs[i]
        return null
    }
    property var musicPlayer: null
    onPlayingPlayerChanged: {
        if (playingPlayer) { musicPlayer = playingPlayer; musicGrace.stop() }
        else if (Prefs.musicGrace === 0) musicPlayer = null
        else if (Prefs.musicGrace > 0) musicGrace.restart()   // -1: остаётся, пока плеер открыт
    }
    Timer {
        id: musicGrace
        interval: Math.max(1, Prefs.musicGrace) * 1000
        onTriggered: {
            if (root.playingPlayer) return
            if (root.islandHover) restart(); else root.musicPlayer = null
        }
    }
    readonly property bool musicOn: islandShown && Prefs.islandMusic && !!musicPlayer
                                    && Mpris.players.values.indexOf(musicPlayer) >= 0

    // таймер: плагин timer пишет «конец_мс всего_с pid» в $XDG_STATE_HOME/glide-shell/timer
    readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/glide-shell"
    property bool stateReady: false
    property var timerState: null
    property double now: Date.now()
    readonly property bool timerOn: Prefs.islandTimer && !!timerState && timerState.end > now
    readonly property real timerLeft: timerOn ? Math.ceil((timerState.end - now) / 1000) : 0
    readonly property real timerTotal: timerState ? timerState.total : 0
    readonly property real timerProgress: timerOn ? Math.min(1, (timerState.end - now) / 1000 / timerState.total) : 0
    function parseTimer(t) {
        var a = t.trim().split(/\s+/)
        var end = Number(a[0]), total = Number(a[1])
        now = Date.now()
        timerState = end > now && total > 0 ? { end: end, total: total, pid: a[2] || "" } : null
    }
    function cancelTimer() {
        if (!timerState) return
        runRaw(["sh", "-c", 'pkill -P "$1" 2>/dev/null; kill "$1" 2>/dev/null; : > "$2"',
                "sh", timerState.pid, stateDir + "/timer"], "", "")
        timerState = null
    }
    Timer {
        running: !!root.timerState
        interval: 500; repeat: true
        onTriggered: {
            root.now = Date.now()
            if (root.timerState && root.now >= root.timerState.end) {
                root.timerState = null
                root.flash("◷", Tr.t("Таймер: время вышло"), Theme.warning)
            }
        }
    }
    Process {
        id: stateInit
        command: ["sh", "-c", 'mkdir -p "$1" && touch "$1/timer"', "sh", root.stateDir]
        onExited: root.stateReady = true
    }
    FileView {
        path: root.stateReady ? root.stateDir + "/timer" : ""
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.parseTimer(text())
    }
    signal opened()
    signal refresh()

    readonly property string focusedJson: JSON.stringify(ctx.window === undefined ? null : ctx.window)
    readonly property string contextText: ctx.selection || ctx.clipboard || ""
    readonly property string contextLabel: ctx.selection ? Tr.t("Выделено") : Tr.t("Буфер")
    readonly property var contextActions: computeContext(contextText, plugins)
    readonly property var results: computeResults(query, plugins)
    readonly property var visiblePlugins: plugins.filter(p => p.categories.indexOf(category) >= 0)
    readonly property int categoryIndex: {
        for (var i = 0; i < categories.length; i++) if (categories[i].id === category) return i
        return -1
    }
    readonly property int pageCount: Math.max(1, Math.ceil(categories.length / Prefs.perPage))
    readonly property var pageCategories: categories.slice(railPage * Prefs.perPage, (railPage + 1) * Prefs.perPage)
    onCategoryIndexChanged: followCategory()
    onPageCountChanged: followCategory()
    readonly property string categoryName: {
        for (var i = 0; i < categories.length; i++)
            if (categories[i].id === category) return categories[i].name
        return ""
    }

    // --- API для QML-плагинов ---
    readonly property QtObject api: QtObject {
        readonly property bool shown: root.shown
        readonly property string contextText: root.contextText     // выделение или буфер в момент вызова
        readonly property var handoff: root.handoff
        readonly property color accent: Prefs.accent                // акцентный цвет из настроек
        readonly property color accentText: Theme.accentText            // текст на акценте (белый или тёмный)
        readonly property var appCounts: root.appCounts                 // id приложения → число запусков
        function launchApp(entry) { root.launchApp(entry) }
        readonly property bool awake: root.awake                        // «не засыпать»
        readonly property var powerTimer: root.powerTimer               // выключение по таймеру: {action, end} или null
        readonly property real now: root.now
        readonly property var notifs: Notifs                            // уведомления: list, dnd, setDnd, remove…
        readonly property var weather: Weather                          // погода: data, ok, refresh, temp, icon, describe
        readonly property var recorder: Recorder                        // запись экрана: start, stop, recording, elapsed
        readonly property var kdeconnect: KdeConnect                    // телефон: devices, phone, act(d, действие)
        readonly property var theme: Theme                              // цвета, r(n) — скругление, fs(n) — шрифт
        function setPref(key, value) { Prefs.set(key, value) }          // записать настройку панели
        function setAwake(on) { root.setAwake(on) }
        readonly property string iconFont: Prefs.iconFont
        function run(argv, text) { root.runRaw(argv, text || "", "") }
        function close() { root.close() }
        function openCategory(id) { root.openCategory(id) }              // перейти в другую категорию панели
        function copy(text) { root.runRaw(["sh", "-c", 'printf %s "$QP_TEXT" | wl-copy'], text, "") }
        function flash(icon, text, color) { root.flash(icon, text, color) }   // сообщение в острове
        function takeHandoff(id) {   // забрать переданный текст (один раз)
            var h = root.handoff
            if (!h || h.to !== id) return null
            root.handoff = null
            return h
        }
    }
    readonly property bool wide: visiblePlugins.some(p => p.wide) && !settingsOpen && query === ""
    function pluginById(id) {
        for (var i = 0; i < plugins.length; i++) if (plugins[i].id === id) return plugins[i]
        return null
    }

    // ---------- запуск команд ----------
    function expand(argv, dir, text) {
        return argv.map(a => a.split("{text}").join(text).split("{dir}").join(dir))
    }
    function runRaw(argv, text, dir) {
        var p = procComp.createObject(root, {
            command: argv,
            environment: ({
                QP_TEXT: text, QP_DIR: dir, QP_FOCUSED: root.focusedJson,
                QP_SELECTION: root.ctx.selection || "", QP_CLIPBOARD: root.ctx.clipboard || "",
                QP_STYLE: Prefs.style
            })
        })
        p.running = true
    }
    function run(plugin, spec, text) {
        if (!spec.handoff && !Permissions.has(plugin.id, plugin, "exec")) {   // API 2: команды кнопок — по разрешению «exec»
            flash(String.fromCodePoint(0xF033E), Tr.t("«") + plugin.name + Tr.t("»: нужно разрешение «Запуск программ»"), Theme.warning)
            Permissions.request(plugin.id, plugin.name, plugin, "exec", "")
            return
        }
        if (spec.handoff) {   // не команда, а передача текста другому плагину (например, в чат ИИ)
            var target = pluginById(spec.handoff)
            if (!target) return
            handoff = { to: target.id, text: text || "", prompt: spec.prompt || "", ts: Date.now() }
            setCategory(target.categories[0])
            return
        }
        var argv = expand(spec.command, plugin.dir, text || "")
        if (spec.output)   // результат команды → буфер и/или уведомление
            argv = ["python3", Quickshell.shellDir + "/tools/qp-run.py", spec.output, "--"].concat(argv)
        runRaw(argv, text || "", plugin.dir)
        if (spec.close === false) refreshTimer.restart()
        else {
            close()
            if (Prefs.islandFlash) flash("✓", spec.label || plugin.name)
        }
    }

    // ---------- контекстные действия ----------
    function test(w, t) {
        var s = t.trim()
        switch (w) {
        case "text": return s.length > 0
        case "multiline": return t.indexOf("\n") >= 0
        case "json":
            if (s[0] !== "{" && s[0] !== "[") return false
            try { JSON.parse(s); return true } catch (e) { return false }
        case "xml": return /^<[\w?!]/.test(s) && />$/.test(s)
        case "url": return /^https?:\/\/\S+$/.test(s)
        case "host": return /^([a-z0-9-]+\.)+[a-z]{2,}$/i.test(s) && !fileLike.test(s)   // readme.md, main.py — файлы
        case "jwt": return /^eyJ[\w-]*\.[\w-]+\.[\w-]*$/.test(s)
        case "number": return /^-?\d+(\.\d+)?$/.test(s)
        case "timestamp": return /^\d{9,13}(\.\d+)?$/.test(s)
        case "path": return /^(\/|~\/)\S.*$/.test(s) && s.indexOf("\n") < 0
        case "base64": {   // «password», «function» — 8 букв, но не base64: нужны цифра, +, /, = или обе регистра на длинном
            var c = s.replace(/\s/g, "")
            return /^[A-Za-z0-9+\/=\s]{8,}$/.test(s) && c.length % 4 === 0
                   && (/[0-9+\/=]/.test(c) || (c.length >= 16 && /[a-z]/.test(c) && /[A-Z]/.test(c)))
        }
        case "urlenc": return /%[0-9A-Fa-f]{2}/.test(s)
        }
        return false
    }
    // одно имя и расширение файла — не хост (у .md, .py, .sh есть и такие домены, но в выделении это почти всегда файл)
    readonly property var fileLike: /^[^.]+\.(md|txt|py|js|ts|qml|json|sh|png|jpe?g|gif|webp|svg|pdf|html?|css|cpp|c|h|hpp|rs|go|java|kt|rb|php|zip|gz|xz|tar|7z|log|conf|cfg|ini|kdl|toml|ya?ml|xml|csv|mp3|mp4|mkv|webm|ogg|flac|wav|docx?|xlsx?|pptx?|odt|desktop|service|lock)$/i
    function matches(when, t) {
        var ws = when === undefined ? ["text"] : (Array.isArray(when) ? when : [when])
        for (var i = 0; i < ws.length; i++) if (test(ws[i], t)) return true
        return false
    }
    function computeContext(t, ps) {
        var out = []
        if (!t) return out
        for (var i = 0; i < ps.length; i++) {
            var acts = ps[i].contextActions || []
            for (var j = 0; j < acts.length; j++)
                if (matches(acts[j].when, t)) out.push({ plugin: ps[i], spec: acts[j] })
        }
        return out.slice(0, 12)
    }

    // ---------- приложения (лаунчер) ----------
    // список — из встроенной службы Quickshell (.desktop-файлы), без Python;
    // сколько раз запускали — в $XDG_STATE_HOME/glide-shell/apps.json, частые выше
    FileView {
        path: root.stateReady ? root.stateDir + "/apps.json" : ""
        printErrors: false
        onAdapterUpdated: writeAdapter()
        JsonAdapter { id: appsData; property var counts: ({}) }
    }
    readonly property var appCounts: appsData.counts
    function launchApp(e) {
        if (!e) return
        var c = Object.assign({}, appsData.counts)
        c[e.id] = (c[e.id] || 0) + 1
        appsData.counts = c
        // Terminal=true открываем в терминале сами. Каждое приложение — в своей scope-группе systemd:
        // иначе оно жило бы в группе службы glide-shell и могло погибнуть при её перезапуске.
        var cmd = e.runInTerminal ? [Quickshell.env("TERMINAL") || "alacritty", "-e"].concat(e.command) : e.command
        if (!cmd || !cmd.length) { e.execute(); close(); return }   // без Exec (запуск через D-Bus) — как умеет сам
        var unit = "app-glide-" + String(e.id || "app").replace(/[^A-Za-z0-9_.-]/g, "_") + "-" + Date.now()
        // execDetached принимает только список (JS-объект в ProcessContext не превращается) — папка ключом systemd-run
        Quickshell.execDetached(["systemd-run", "--user", "--scope", "--collect", "--quiet", "--unit=" + unit,
                                 "--working-directory=" + (e.workingDirectory || Quickshell.env("HOME"))].concat(cmd))
        close()
    }
    function appResults(words, all) {
        var out = [], apps = DesktopEntries.applications.values
        for (var i = 0; i < apps.length; i++) {
            var e = apps[i]
            if (e.noDisplay) continue
            var name = e.name.toLowerCase()
            var hay = name + " " + (e.genericName || "").toLowerCase() + " " + e.id.toLowerCase()
                      + " " + (e.keywords || []).join(" ").toLowerCase()
            if (!all(hay)) continue
            var w0 = words[0]
            var score = (name.indexOf(w0) === 0 ? 100 : name.indexOf(" " + w0) >= 0 ? 60 : 20)
                        + Math.min(60, (appCounts[e.id] || 0) * 6)
            out.push({ kind: "app", label: e.name, sub: e.genericName || Tr.t("приложение"), entry: e, icon: e.icon, score: score })
        }
        out.sort((a, b) => b.score - a.score)
        return out.slice(0, 6)
    }

    // ---------- поиск по действиям ----------
    function computeResults(q, ps) {
        var words = q.trim().toLowerCase().split(/\s+/).filter(w => w.length)
        if (words.length === 0) return []
        function all(hay) {
            for (var i = 0; i < words.length; i++) if (hay.indexOf(words[i]) < 0) return false
            return true
        }
        var out = providers.top.concat(appResults(words, all))   // ответы плагинов (top) — над приложениями
        for (var i = 0; i < ps.length; i++) {
            var p = ps[i]
            var pHay = (p.name + " " + (p.keywords || []).join(" ")).toLowerCase()
            if (all(pHay)) out.push({ kind: "goto", label: p.name, sub: Tr.t("открыть"), plugin: p })
            var items = p.items || []
            for (var j = 0; j < items.length; j++) {
                var it = items[j]
                if (it.type !== "button") continue
                if (all(pHay + " " + (it.label || "").toLowerCase()))
                    out.push({ kind: "run", label: it.label, sub: p.name, plugin: p, spec: it })
            }
        }
        out = out.concat(providers.rest).slice(0, 20)   // остальное от плагинов — после команд
        // файлы (ответ помощника на этот же запрос) и «искать в интернете» последним
        // файлы — без тех, что уже показал плагин (недавние: id результата — путь)
        if (fileHits.q === q) for (var f of fileHits.items) if (!out.some(r => r.kind === "plugin" && r.id === f.path))
            out.push({ kind: "file", label: f.name, sub: f.dir, path: f.path, isdir: f.isdir })
        if (Prefs.webSearch !== "off" && q.trim().length >= 2)
            out.push({ kind: "web", label: Tr.t("Искать в интернете: ") + q.trim(), sub: webNames[Prefs.webSearch], q: q.trim() })
        return out
    }
    // ---- поиск файлов: один долгоживущий помощник держит индекс в памяти, запрос — строкой в stdin ----
    readonly property var webNames: ({ duckduckgo: "DuckDuckGo", google: "Google", yandex: Tr.t("Яндекс"), bing: "Bing" })
    readonly property var webUrls: ({ duckduckgo: "https://duckduckgo.com/?q=", google: "https://www.google.com/search?q=",
                                      yandex: "https://yandex.ru/search/?text=", bing: "https://www.bing.com/search?q=" })
    property var fileHits: ({ q: "", items: [] })
    SearchProviders { id: providers; query: root.query }   // результаты плагинов (api.search, разрешение «search»)
    property bool filesWanted: false     // помощник жив: с первого поиска и 5 мин после закрытия панели
    // ---- мастер первого запуска ----
    property bool welcomeOpen: false
    Timer { running: Prefs.warm && Prefs.welcome && !Prefs.welcomeDone && !lockScreen.locked; interval: 800; onTriggered: root.welcomeOpen = true }
    LazyLoader {
        active: root.welcomeOpen
        Welcome { root: root; screen: root.panelScreen; onDone: root.welcomeOpen = false }
    }
    // ---- выключение по таймеру (tools/glide-powertimer.sh): состояние для острова и раздела «Питание» ----
    property var powerTimer: null
    FileView {
        path: root.stateDir + "/powertimer"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: { try { var d = JSON.parse(text()); root.powerTimer = d.end * 1000 > Date.now() ? d : null } catch (e) { root.powerTimer = null } }
        onLoadFailed: root.powerTimer = null
    }
    Timer {   // остаток в острове и разделе; после срока — убрать (сон: после пробуждения файла уже нет)
        running: !!root.powerTimer; repeat: true; interval: 20000; triggeredOnStart: true
        onTriggered: { root.now = Date.now(); if (root.powerTimer && root.powerTimer.end * 1000 <= root.now) root.powerTimer = null }
    }
    property string pendingSearch: ""    // IPC search до показа панели
    Connections {
        target: root
        function onShownChanged() {
            if (root.shown) { filesIdle.stop(); if (root.pendingSearch !== "") { var t = root.pendingSearch; root.pendingSearch = ""; Qt.callLater(() => win.setSearch(t)) } }
            else if (root.filesWanted) filesIdle.restart()
        }
    }
    Timer { id: filesIdle; interval: 300000; onTriggered: root.filesWanted = false }
    Process {
        id: filesProc
        running: root.filesWanted && Prefs.fileSearch
        stdinEnabled: true
        command: ["setpriv", "--pdeathsig", "TERM", "ionice", "-c3", "nice", "-n", "10",
                  "python3", "-I", Quickshell.shellDir + "/tools/glide-files.py", "serve"]
        stdout: SplitParser {
            onRead: (line) => { try { var d = JSON.parse(line); if (d.q === root.query) root.fileHits = d } catch (e) {} }
        }
    }
    Timer {   // между нажатиями — пауза, чтобы не искать на каждую букву
        id: filesAsk
        interval: 160
        onTriggered: if (filesProc.running && root.query.trim().length >= 2) filesProc.write(root.query + "\n")
    }
    onQueryChanged: {
        if (previewPath) showPreview("")
        selected = 0
        if (!Prefs.fileSearch || query.trim().length < 2) return
        if (!filesWanted) filesWanted = true
        filesAsk.restart()
    }
    function openPath(p) {   // в своей scope-группе: открытое приложение не живёт в группе службы оболочки
        Quickshell.execDetached(["systemd-run", "--user", "--scope", "--collect", "--quiet", "xdg-open", p])
        close()
    }
    function activate(r) {
        if (r.kind === "app") launchApp(r.entry)
        else if (r.kind === "file") openPath(r.path)
        else if (r.kind === "web") openPath(webUrls[Prefs.webSearch] + encodeURIComponent(r.q))
        else if (r.kind === "plugin") { providers.activate(r, root); close() }
        else if (r.kind === "run" && !r.spec.confirm) run(r.plugin, r.spec, "")
        else { category = r.plugin.categories[0]; clearSearch() }
    }
    function activateSelected() { if (results.length) activate(results[Math.min(selected, results.length - 1)]) }
    function moveSelection(d) {
        if (results.length) selected = (selected + d + results.length) % results.length
        if (previewPath) { var r = results[selected]; showPreview(r && r.kind === "file" ? r.path : "") }   // просмотр едет за выбором
    }

    // ---------- фон плагинов: plugin.json «service» — QML без интерфейса, живёт с оболочкой (таймеры, слежение) ----------
    // модель — по подписи: список плагинов пересобирается при каждом открытии панели, а службы не должны перезапускаться
    readonly property string serviceSig: JSON.stringify(plugins.filter(p => p.service)
        .map(p => ({ id: p.id, name: p.name, dir: p.dir, service: p.service, mtime: p.mtime || 0, settings: p.settings || [] })))
    Instantiator {
        model: Prefs.warm ? JSON.parse(root.serviceSig) : []
        delegate: Loader {
            id: svc
            required property var modelData
            property ApiScope scope: ApiScope { owner: svc.modelData.id; ownerName: svc.modelData.name; manifest: svc.modelData }
            // полный манифест (api, permissions, trusted) — из списка оболочки, а не урезанная подпись serviceSig;
            // api — начальным свойством: есть уже в Component.onCompleted службы
            Component.onCompleted: {
                Permissions.register(scope, modelData.id, modelData.name, root.pluginById(modelData.id) || {})
                setSource("file://" + modelData.dir + "/" + modelData.service + "?v=" + modelData.mtime, { api: scope })
            }
            onLoaded: if ("pluginDir" in item) item.pluginDir = modelData.dir
            onStatusChanged: if (status === Loader.Error) console.warn("glide-shell: служба плагина " + modelData.id + " не загрузилась")
        }
    }

    // ---------- чужие приложения: служба D-Bus org.glide.Shell (tools/glide-shell.py, docs/API.md) ----------
    function fromDbus(payload) {
        var m
        var raw = Qt.atob(payload)   // Qt 6 сам раскодирует UTF-8; на старых — байты, их перекодировать
        try { m = JSON.parse(raw) } catch (e) {
            try { m = JSON.parse(decodeURIComponent(escape(raw))) } catch (e2) { return "bad payload" }
        }
        var id = "ext:" + (m.id || "")
        switch (m.op) {
        case "flash": flash(m.icon || String.fromCodePoint(0xF02FC), m.text || "", Prefs.accent); break
        case "start": Activities.start(id, Object.assign({ owner: "dbus" }, m.props || {})); break
        case "update": Activities.update(id, Object.assign({ owner: "dbus" }, m.props || {})); break
        case "end": Activities.end(id); break
        case "open": if (m.category) openCategory(m.category); else open(); break
        case "close": close(); break
        case "search": if (shown) win.setSearch(m.text || ""); else { pendingSearch = m.text || ""; open() } break
        case "dnd": Notifs.setDnd(!!m.on); break
        case "settings": showSettings(m.page || ""); break
        default: return "unknown op"
        }
        return "ok"
    }
    function toDbus(id, event) {   // щелчок, кнопка, «×» по активности приложения — обратно в службу (она шлёт сигнал)
        if (id.indexOf("ext:") !== 0) return
        Quickshell.execDetached(["gdbus", "call", "--session", "--dest", "org.glide.Shell", "--object-path", "/org/glide/Shell",
                                 "--method", "org.glide.Shell1.ActivityEvent", id.slice(4), event])
    }
    Connections {
        target: Activities
        function onClicked(id) { root.toDbus(id, "clicked") }
        function onAction(id) { root.toDbus(id, "action") }
        function onEnded(id) { root.toDbus(id, "closed") }
    }
    // тема для приложений — $XDG_RUNTIME_DIR/glide-shell-theme.json (GetTheme / ThemeChanged у службы)
    readonly property string themeJson: JSON.stringify({
        accent: String(Prefs.accent), accentText: String(Theme.accentText), isLight: Theme.isLight, tone: Prefs.themeTone,
        background: String(Theme.background), surface: String(Theme.surface), surfaceHigh: String(Theme.surfaceHigh),
        outline: String(Theme.outline), text: String(Theme.text), textSecondary: String(Theme.textSecondary),
        radius: Prefs.themeRadius, font: Prefs.themeFont, lang: Tr.lang
    })
    onThemeJsonChanged: themeWrite.restart()
    Timer { id: themeWrite; interval: 400; running: true; onTriggered: themeFile.setText(root.themeJson) }
    FileView {
        id: themeFile
        path: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/glide-shell-theme.json"
        printErrors: false
        atomicWrites: true
    }

    // ---------- быстрый просмотр файла в поиске (Shift+Пробел; tools/glide-preview.py) ----------
    property string previewPath: ""
    property var preview: null
    function togglePreview() {
        var r = results[Math.min(selected, results.length - 1)]
        showPreview(previewPath || !r || r.kind !== "file" ? "" : r.path)
    }
    function showPreview(path) {
        previewPath = path
        preview = null
        if (!path) return
        previewProc.running = false
        previewProc.command = ["python3", "-I", Quickshell.shellDir + "/tools/glide-preview.py", path]
        previewProc.running = true
    }
    Process {
        id: previewProc
        stdout: StdioCollector {
            onStreamFinished: { try { var d = JSON.parse(text); if (root.previewPath) root.preview = d } catch (e) {} }
        }
    }

    function clearSearch() { query = ""; win.clearSearchUi() }

    // ---------- панель ----------
    function open() {
        if (shown || ctxProc.running) return
        discover.running = true
        ctxProc.running = true   // сначала снимок контекста, потом показ
    }
    function close() { shown = false }
    function toggle() { shown ? close() : open() }

    function hasCategory(id) {
        for (var i = 0; i < categories.length; i++) if (categories[i].id === id) return true
        return false
    }
    function setCategory(id) { settingsOpen = false; category = id; clearSearch() }
    function openSettings() { settingsOpen = !settingsOpen; clearSearch() }
    function showSettings(page) { settingsPage = page || "look"; settingsOpen = true; clearSearch(); if (!shown) open() }

    // ---------- разрешения плагинов (Permissions.qml) и сообщения между ними (api.send → onMessage) ----------
    signal pluginMessage(string from, string to, string name, var data, var sender)   // sender — объект api отправителя
    Connections {
        target: Permissions
        function onAsked(owner) { root.showSettings("plugins") }   // плагин попросил разрешение — вопрос в «Плагинах»
        function onTampered() {
            root.flash(String.fromCodePoint(0xF0026), Tr.t("Разрешения плагинов изменили в обход настроек — изменение отменено"), Theme.error)
        }
        function onGrantsChanged() { root.updateDaemons() }
    }

    // ---------- страницы рейки ----------
    function setPage(p) {
        p = Math.max(0, Math.min(pageCount - 1, p))
        if (p === railPage) return
        railDir = p > railPage ? 1 : -1
        railPage = p
    }
    function flipPage(d) { setPage((railPage + d + pageCount) % pageCount) }
    function followCategory() {   // страница рейки едет за текущей категорией
        if (categoryIndex >= 0) setPage(Math.floor(categoryIndex / Prefs.perPage))
        else setPage(Math.min(railPage, pageCount - 1))
    }
    Connections {
        target: Prefs
        function onPerPageChanged() { root.followCategory() }
        function onSaved() { discover.running = true }
    }

    // ---------- настройки ----------
    function togglePlugin(id) { Prefs.run(["toggle-disabled", id]) }
    function rediscover() { discover.running = true }                 // список плагинов заново (после установки)
    property string pluginArchive: ""                                 // архив для карточки установки (IPC pluginInstall)
    // безопасный режим (с замка, после пароля): выключить все сторонние плагины — встроенные остаются
    readonly property var userPluginsOn: allPlugins.filter(p => p.user && !p.disabled && !p.problem)
    function safeMode() {
        var ids = userPluginsOn.map(p => p.id)
        if (!ids.length) return
        Prefs.run(["disable-many", JSON.stringify(ids)])
        flash(String.fromCodePoint(0xF0431), Tr.t("Сторонние плагины выключены: ") + ids.length + Tr.t(" — вернуть в «Плагинах»"), Theme.warning)
        safeRefresh.restart()   // запись в config.json — по очереди; перечитать, когда допишется
    }
    Timer { id: safeRefresh; interval: 800; onTriggered: discover.running = true }
    function moveCategory(id, d) {
        Prefs.run(["move-category", id, String(d), JSON.stringify(categories.map(c => c.id))])
    }
    function openCategory(id) {   // хоткей категории: повторное нажатие закрывает панель
        if (!hasCategory(id)) return
        if (shown && category === id && query === "") { close(); return }
        if (shown) setCategory(id); else { settingsOpen = false; category = id; open() }   // не настройки, а раздел
    }
    function pick(i) { if (i >= 0 && i < categories.length) setCategory(categories[i].id) }
    function step(d) {
        if (categories.length === 0) return
        var cur = 0
        for (var i = 0; i < categories.length; i++) if (categories[i].id === category) cur = i
        pick((cur + d + categories.length) % categories.length)
    }
    function setProfile(name) {
        profProc.command = ["sh", "-c",
            'd="${XDG_STATE_HOME:-$HOME/.local/state}/glide-shell"; mkdir -p "$d"; printf %s "$1" > "$d/profile"',
            "sh", name]
        profProc.running = true
    }

    Component { id: procComp; Process { onExited: destroy() } }
    Timer { id: refreshTimer; interval: 300; onTriggered: root.refresh() }

    Process { id: profProc; onExited: discover.running = true }

    Process {
        id: ctxProc
        command: ["python3", Quickshell.shellDir + "/tools/qp-context.py"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.ctx = JSON.parse(text) }
                catch (e) { root.ctx = { window: null, selection: "", clipboard: "" } }
                root.query = ""
                win.clearSearchField()
                root.followCategory()
                root.shown = true
                root.opened()
            }
        }
    }

    Process {
        id: discover
        command: ["python3", Quickshell.shellDir + "/tools/qp-discover.py"]
        stdout: StdioCollector {
            onStreamFinished: root.applyDiscovery(text.trim(), true)
        }
    }
    // ответ qp-discover: из кэша при старте (fresh = false) или свежий
    function applyDiscovery(raw, fresh) {
        if (raw === root.pluginsRaw) { if (fresh) root.discovered = true; return }   // без изменений — ничего не перестраиваем
        try {
            var d = JSON.parse(raw)
            root.pluginsRaw = raw
            if (!Tr.ru) {   // названия категорий и плагинов, описания и подписи — на языке интерфейса
                d.categories = trData(d.categories); d.plugins = trData(d.plugins); d.allPlugins = trData(d.allPlugins || [])
            }
            root.profile = d.profile
            root.categories = d.categories
            root.plugins = d.plugins
            root.updateDaemons()
            root.allPlugins = d.allPlugins || []
            // один раз: сторонние плагины API 1, что стояли до v1.1, остаются одобренными (Permissions.migrateLegacy)
            Permissions.migrateLegacy("plugins", root.allPlugins.filter(p => p.user && !p.problem).map(p => ({ owner: p.id, m: p })))
            Permissions.migrateMessages()
            Prefs.data = d.panel || {}
            console.log("glide-shell: " + d.plugins.length + " plugins, " + d.categories.length + " categories"
                        + (fresh ? "" : Tr.t(" (кэш)")))
            if (!root.hasCategory(root.category))
                root.category = root.categories.length ? root.categories[0].id : ""
            if (fresh) { root.discovered = true; Prefs.saveCache(raw) }
        } catch (e) { console.warn("glide-shell: bad plugin list:", e) }
    }
    readonly property var trKeys: ["name", "description", "label", "placeholder", "empty", "title", "hint", "categoryName", "sub"]
    function trData(x) {   // перевод строк данных плагинов (Tr): только видимые поля, вглубь
        if (Array.isArray(x)) return x.map(trData)
        if (x && typeof x === "object") {
            var o = {}
            for (var k in x) o[k] = typeof x[k] === "string" && trKeys.indexOf(k) >= 0 ? Tr.t(x[k]) : trData(x[k])
            return o
        }
        return x
    }
    Connections {   // сменили язык — пересобрать данные плагинов с переводом
        target: Tr
        function onLangChanged() { var r = root.pluginsRaw; root.pluginsRaw = ""; if (r) root.applyDiscovery(r, false) }
        function onDictChanged() { var r = root.pluginsRaw; root.pluginsRaw = ""; if (r) root.applyDiscovery(r, false) }
    }
    property bool discovered: false   // свежий discover пришёл — оболочка готова (IPC ready, ExecStartPost службы)

    // Фоновые процессы плагинов (поле "daemon"); setpriv --pdeathsig — умирают вместе с оболочкой,
    // иначе каждый перезапуск оставлял копию (слежение за буфером писало историю по нескольку раз)
    // Модель меняется, только если поменялся сам набор демонов: discover идёт после каждой смены настройки,
    // и новый массив plugins пересоздавал бы все процессы (слежение за буфером терял копирования).
    property var daemons: []
    function updateDaemons() {
        var d = root.plugins.filter(p => p.daemon && Permissions.has(p.id, p, "exec")).map(p => ({ id: p.id, daemon: p.daemon, dir: p.dir }))
        if (JSON.stringify(d) !== JSON.stringify(daemons)) daemons = d
    }
    Instantiator {
        model: root.daemons
        delegate: Process {
            required property var modelData
            command: ["setpriv", "--pdeathsig", "TERM"].concat(root.expand(modelData.daemon, modelData.dir, ""))
            environment: ({ QP_DIR: modelData.dir })
            running: true
        }
    }

    Component.onCompleted: {
        Core.root = root   // для ApiScope (вместо прежнего api.shell)
        Core.confirms = confirms
        Core.schedules = schedules
        Core.clipwatch = clipwatch
        Core.wallpaper = wallpaper
        console.log("Glide Shell v2.9 (search, context, profiles, settings, ai, island, bar, controls) from " + Quickshell.shellDir)
        if (Prefs.cachedRaw) applyDiscovery(Prefs.cachedRaw.trim(), false)
        discover.running = true
        stateInit.running = true
    }

    IpcHandler {
        target: "panel"
        function toggle(): void { root.toggle() }
        function open(): void { root.open() }
        function close(): void { root.close() }
        function category(id: string): void { root.openCategory(id) }
        function profile(name: string): void { root.setProfile(name) }
        function settings(): void { root.settingsOpen = true; if (!root.shown) root.open() }
        function editDesktop(): void { root.editDesktop(!desktopWidgets.editing) }   // правка виджетов на рабочем столе
        function ready(): string { return root.discovered ? "yes" : "no" }   // служба ждёт его в ExecStartPost
        // обои-картинка: wallpaper next — следующая из папки, wallpaper ПУТЬ — показать файл; "" — текущая
        function wallpaper(arg: string): string {
            if (arg === "next") wallpaper.next()
            else if (arg !== "") wallpaper.show(arg)
            return wallpaper.current
        }
        // карточка установки плагина из архива в «Настройки» → «Плагины» (ставит человек кнопкой)
        function pluginInstall(path: string): void { root.settingsPage = "plugins"; root.settingsOpen = true; if (!root.shown) root.open(); root.pluginArchive = path }
        function settingsPage(id: string): void { root.settingsPage = id; root.settingsOpen = true; if (!root.shown) root.open() }
        function flash(text: string): void { root.flash("•", text, Prefs.accent) }
        function brightnessOsd(pct: int): void { root.brightnessOsd(pct) }
        function launcher(): void { root.openCategory("apps") }   // Mod+D
        function launch(id: string): string {   // запустить приложение по id .desktop (для клавиш niri из «Устройств»)
            var e = DesktopEntries.byId(id) || DesktopEntries.applications.values.find(x => x.id === id || x.id === id.replace(/\.desktop$/, ""))
            if (!e) return Tr.t("нет приложения ") + id
            root.launchApp(e); return "ok"
        }
        function trayMenu(id: string): string { return root.rightBar ? root.rightBar.openTrayMenu(id) : "" }
        function barTip(key: string): string {   // капля из капсулы бара (проверка): сначала справа, потом слева
            if (key === "") { for (var b of bars.instances) b.showTip(""); return "closed" }
            var r = root.rightBar ? root.rightBar.showTip(key) : ""
            return r === "ok" || !root.leftBar ? r : root.leftBar.showTip(key)
        }
        function dockMenu(key: string): string { return root.mainDock ? root.mainDock.menuFor(key) : "" }    // меню значка дока (проверка)
        function bellFly(): void { if (root.rightBar) root.rightBar.flyToBell() }                            // точка из острова в колокольчик (проверка)
        // поиск из скрипта (демо, хоткей с готовым запросом): открыть панель и вписать текст
        function search(text: string): void {   // панель открывается не сразу (снимок контекста) — запрос ждёт показа
            if (root.shown) { win.setSearch(text); return }
            root.pendingSearch = text; root.open()
        }
        // настройка на лету: pref accent '"#3b82f6"' — значение JSON (как в config.json)
        function pref(key: string, value: string): string {
            try { Prefs.set(key, JSON.parse(value)); return "ok" } catch (e) { return "bad JSON: " + value }
        }
        function welcome(mode: string): void {   // мастер первого запуска: "" — открыть, close — закрыть
            if (mode === "close") { root.welcomeOpen = false; return }
            root.close(); root.welcomeOpen = true
        }
        function preview(): string { root.togglePreview(); return root.previewPath }   // быстрый просмотр выбранного файла
        function archUpdates(what: string): string {   // check — проверить, upgrade — терминал с обновлением, "" — итог
            if (what === "check") { ArchUpdates.check(); return "ok" }
            if (what === "upgrade") { ArchUpdates.upgrade(); return "ok" }
            return JSON.stringify(ArchUpdates.st)
        }
        // от службы D-Bus org.glide.Shell (tools/glide-shell.py): base64 от JSON — qs ipc режет аргументы по запятым
        function dbus(payload: string): string { return root.fromDbus(payload) }
        function activityAct(id: string, what: string): string {   // как щелчок: what = click | action | close
            if (what === "action") Activities.act(id); else if (what === "close") Activities.end(id); else Activities.click(id)
            return JSON.stringify(Activities.list.map(a => a.id))
        }
        function peek(on: string): string { root.islandHover = on === "on"; return String(root.islandPeek) }   // раскрыть остров, как наведением
        // «живая активность» из скрипта: title "" — убрать; progress 0…1, меньше 0 — без прогресса
        function overlay(cmd: string): string {
            if (cmd === "toggle") overlayLayer.toggle()
            else if (cmd === "open") overlayLayer.open = true
            else if (cmd === "close") overlayLayer.open = false
            else if (cmd === "pin") Prefs.set("overlayPin", !Prefs.overlayPin)
            else return "toggle | open | close | pin"
            return overlayLayer.open ? "open" : "closed"
        }
        // автоматизация: list — правила и журнал; test ID — выполнить действия правила; resume — снять паузу;
        // emit ТИП APP — событие для проверки (appOpen org.telegram.desktop и т. п.)
        function automation(cmd: string, arg: string, arg2: string): string {
            if (cmd === "list") return JSON.stringify({ paused: automationEngine.paused, rules: automationEngine.rules, log: automationEngine.log })
            if (cmd === "test") { automationEngine.test(arg); return "ok" }
            if (cmd === "resume") { automationEngine.resume(); return "ok" }
            if (cmd === "emit") { automationEngine.emit(arg, { app: arg2 }); return "ok" }
            return "list | test ID | resume | emit TYPE APP"
        }
        function activity(id: string, title: string, progress: real): string {
            if (title === "") { Activities.end(id); return "ended" }
            Activities.update(id, { title: title, progress: progress, owner: "ipc" })
            return "ok"
        }
        function update(what: string): string {   // check — проверить (git fetch), shell | apps — обновить
            if (what === "check") { Updates.check(true); return "ok" }
            if (what === "shell" || what === "apps") { Updates.apply(what); return "ok" }
            return JSON.stringify(Updates.st)
        }
        function night(mode: string): string {   // ночной свет: on | off | auto | toggle | "" — вернуть режим
            if (mode === "toggle") NightLight.toggle()
            else if (["on", "off", "auto"].indexOf(mode) >= 0) NightLight.setMode(mode)
            return Prefs.night
        }
        function notifReply(text: string): string {   // проверка ответа: "" — раскрыть остров с полем, текст — отправить
            if (!Notifs.popup || !Notifs.popup.reply) return Tr.t("нет уведомления с ответом")
            if (text === "") { root.islandHover = true; root.replying = true; return "ok" }
            var ok = Notifs.sendReply(Notifs.popup, text); root.replying = false; root.islandHover = false
            return ok ? "sent" : "fail"
        }
        function notifClear(app: string): int { return Notifs.removeApp(app) }  // убрать уведомления приложения из истории   // меню значка трея; без ID — список
        // запись экрана: record [""|system|mic] — начать или остановить (для хоткея)
        function record(audio: string): void { Recorder.toggle(audio) }
        // одно окно по id niri (пусто — активное): запись идёт, пока не остановят (record) или окно не закроют
        function recordWindow(id: string, audio: string): string {
            if (Recorder.recording) { Recorder.stop(); return "stopped" }
            var w = id ? Number(id) : (Niri.focusedWindow ? Niri.focusedWindow.id : null)
            if (w === null || !Recorder.hasWindow) return Recorder.hasWindow ? "no window" : "no GStreamer: " + Recorder.windowMissing
            Recorder.startWindow(audio, w); return "ok"
        }
        function recordArea(audio: string): void { if (Recorder.recording) Recorder.stop(); else Recorder.start(audio, true) }
        function recordStatus(): string {
            return JSON.stringify({ recording: Recorder.recording, wfRecorder: Recorder.hasRecorder, slurp: Recorder.hasSlurp,
                                    selecting: Recorder.selecting, error: Recorder.error })
        }
        function confirm(answer: string): string {   // вопрос плагина (api.confirm): yes | no — ответить, "" — какой сейчас
            if (answer === "yes" || answer === "no") confirms.answer(answer === "yes")
            var q = confirms.current
            return q ? JSON.stringify({ name: q.name, text: q.text, queued: confirms.queue.length }) : "none"
        }
        function awake(mode: string): string {   // on | off | toggle | "" — вернуть состояние
            if (mode === "on") root.setAwake(true)
            else if (mode === "off") root.setAwake(false)
            else if (mode === "toggle") root.setAwake(!root.awake)
            return root.awake ? "on" : "off"
        }
    }

    // раньше острова: окно острова должно лечь поверх бара
    Variants {
        id: bars
        model: Prefs.monitorMode === "standard" ? [root.panelScreen].filter(s => !!s) : Quickshell.screens
        Bar { required property var modelData; screen: modelData; panel: root }
    }
    Island { id: islandWin; panel: root; screen: root.panelScreen }
    Variants {
        id: docks
        model: Prefs.dockAllScreens ? Quickshell.screens : [root.panelScreen].filter(s => !!s)
        Dock { required property var modelData; screen: modelData; panel: root }
    }
    // автоматизация: правила «когда → если → сделать» (Prefs.automations, вкладка «Автоматизация»)
    // оверлей поверх всего, и игр тоже (Overlay.qml): IPC panel overlay toggle|open|close|pin, клавиша — в «Поведении»
    Overlay { id: overlayLayer; root: root }
    function overlayOpen() { close(); overlayLayer.open = true }
    readonly property var automation: automationEngine   // для настроек
    Automation { id: automationEngine; root: root; locked: lockScreen.locked; lockScreen: lockScreen }
    LockScreen {
        id: lockScreen; panel: root
        onResumed: {   // после сна: часы острова сразу, погода — свежая (таймер Weather во сне стоял)
            root.clockNow = new Date()
            clockTick.interval = 1000; clockTick.restart()
            Weather.afterSleep()
        }
    }
    PolkitDialog {}   // окно пароля polkit (за флагом Prefs.polkit)
    Confirms { id: confirms }                                                // вопросы плагинов человеку (api.confirm)
    Schedules { id: schedules }                                              // напоминания плагинов (api.schedule)
    ClipWatch { id: clipwatch }                                              // смена буфера для плагинов (api.clipboard)
    Connections { target: lockScreen; function onResumed() { schedules.check() } }   // после сна — сразу
    ConfirmDialog { confirms: confirms; locked: lockScreen.locked }
    ThemeSync {}      // палитра «чёрный + акцент» для обоев (~/.cache/glide-shell/colors.json)
    Wallpaper { id: wallpaper; locked: lockScreen.locked }
    DesktopWidgets { id: desktopWidgets; panel: root }   // часы, погода, музыка… на рабочем столе (Prefs.widgets)
    readonly property var desk: desktopWidgets            // для настроек (свои виджеты)
    // Сторож: тикает раз в 0,5 с; если между тиками прошло больше 2 с, главный поток был занят — пишем в журнал,
    // что было открыто (так зависания оставляют след: journalctl --user -u glide-shell | grep «не отвечал»).
    // После сна такой разрыв — норма, его не считаем (часы прыгнули больше чем на минуту).
    property double lastTick: Date.now()
    Timer {
        running: true; repeat: true; interval: 500
        onTriggered: {
            var now = Date.now(), gap = now - root.lastTick
            root.lastTick = now
            if (gap > 2500 && gap < 60000)
                console.warn("glide-shell: интерфейс не отвечал " + Math.round(gap) + " мс (панель: " + (root.shown ? root.category : "закрыта")
                             + (root.settingsOpen ? Tr.t(", настройки ") + root.settingsPage : "") + Tr.t(", обои: ") + Prefs.wallMode
                             + (wallpaper.animated ? " " + wallpaper.kind : "") + ")")
        }
    }   // обои-картинка и цвета темы из неё (Prefs.wallMode === "image")
    readonly property var wall: wallpaper   // для настроек (список картинок, «следующая»)
    BtAgent {}        // агент Bluetooth: коды при сопряжении (пока адаптер включён)   // экран блокировки; IPC: lock lock|test|preview|status

    EdgeTrigger { id: edge; root: root }   // зона вызова у края (вид «рейка»)

    // --- Панель (Panel.qml) ---
    Panel { id: win; root: root }
}
