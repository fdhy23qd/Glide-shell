import QtQuick
import Quickshell
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower

// Автоматизация: правила «когда → (если) → сделать» из Prefs.automations (config.json — попадают в резервную копию).
// Правило: {id, name, on, when: {type, app, at, days, percent}, only: {from, to, power}, then: [{type, …}]}.
// События — из того, что оболочка и так знает (окна niri, KDE Connect, UPower, замок, запись/демонстрация, VPN, часы);
// своих процессов и опроса нет, кроме таймера раз в минуту для правил «в заданное время».
// Защита от зацикливания: правило — не чаще раза в 2 с; одно правило больше 6 раз за минуту или все больше 20 раз
// за 10 с — пауза до перезапуска
// или до «Продолжить» в настройках (правило «запустить X» при «открыто X» и т. п.).
Item {
    id: auto
    required property var root           // корень оболочки: запуск приложений, «не засыпать», вспышки
    property bool locked: false           // экран заперт (lockScreen.locked)
    property var lockScreen: null         // его сигнал resumed — после сна

    readonly property var rules: Array.isArray(Prefs.automations) ? Prefs.automations : []
    property bool paused: false
    property var log: []                  // последние срабатывания: [{time, name, ok, detail}] — видно в настройках
    signal fired(string id)

    // ---------- что умеет ----------
    // when: события; поле params — какие параметры спросить в редакторе
    readonly property var triggers: [
        { type: "appOpen", label: Tr.t("Открыто приложение"), params: ["app"] },
        { type: "appClose", label: Tr.t("Закрыто приложение"), params: ["app"] },
        { type: "appFocus", label: Tr.t("Переключился на приложение"), params: ["app"] },
        { type: "time", label: Tr.t("Время"), params: ["at", "days"] },
        { type: "phoneOn", label: Tr.t("Телефон подключился"), params: [] },
        { type: "phoneOff", label: Tr.t("Телефон отключился"), params: [] },
        { type: "powerAc", label: Tr.t("Зарядка подключена"), params: [] },
        { type: "powerBattery", label: Tr.t("Работа от батареи"), params: [] },
        { type: "batteryBelow", label: Tr.t("Заряд ниже"), params: ["percent"] },
        { type: "locked", label: Tr.t("Экран заблокирован"), params: [] },
        { type: "unlocked", label: Tr.t("Экран разблокирован"), params: [] },
        { type: "captureOn", label: Tr.t("Началась запись или демонстрация"), params: [] },
        { type: "captureOff", label: Tr.t("Запись или демонстрация закончилась"), params: [] },
        { type: "vpnOn", label: Tr.t("VPN подключён"), params: [] },
        { type: "vpnOff", label: Tr.t("VPN отключён"), params: [] },
        { type: "start", label: Tr.t("Запуск оболочки"), params: [] }
    ]
    readonly property var actions: [
        { type: "dnd", label: Tr.t("«Не беспокоить»"), params: ["switch"] },
        { type: "launch", label: Tr.t("Запустить приложение"), params: ["app"] },
        { type: "close", label: Tr.t("Закрыть приложение"), params: ["app"] },
        { type: "awake", label: Tr.t("«Не засыпать»"), params: ["switch"] },
        { type: "night", label: Tr.t("Ночной свет"), params: ["switch"] },
        { type: "volume", label: Tr.t("Громкость"), params: ["percent"] },
        { type: "mute", label: Tr.t("Звук"), params: ["switch"] },
        { type: "notify", label: Tr.t("Уведомление"), params: ["text"] },
        { type: "flash", label: Tr.t("Вспышка в острове"), params: ["text"] },
        { type: "run", label: Tr.t("Команда"), params: ["cmd"] },
        { type: "niri", label: Tr.t("Действие niri"), params: ["cmd"] },
        { type: "wait", label: Tr.t("Подождать"), params: ["seconds"] }
    ]
    function triggerOf(t) { return triggers.find(x => x.type === t) || null }
    function actionOf(t) { return actions.find(x => x.type === t) || null }

    // ---------- правила: правка (настройки) ----------
    function save(list) { Prefs.set("automations", list) }
    function newId() { return "r" + Date.now().toString(36) }
    function add() {
        var r = { id: newId(), name: Tr.t("Новое правило"), on: true, when: { type: "appOpen", app: "" }, only: {}, then: [] }
        save(rules.concat([r]))
        return r.id
    }
    function update(id, patch) { save(rules.map(r => r.id === id ? Object.assign({}, r, patch) : r)) }
    function remove(id) { save(rules.filter(r => r.id !== id)) }
    function resume() { paused = false; burst = []; history = {} }

    // ---------- проверка «если» ----------
    function minutes(s) { var m = /^(\d{1,2}):(\d{2})$/.exec(String(s || "")); return m ? Number(m[1]) * 60 + Number(m[2]) : -1 }
    function allowed(r) {
        var o = r.only || {}
        if (o.power === "ac" && UPower.onBattery) return false
        if (o.power === "battery" && !UPower.onBattery) return false
        var a = minutes(o.from), b = minutes(o.to)
        if (a >= 0 && b >= 0 && a !== b) {
            var d = new Date(), n = d.getHours() * 60 + d.getMinutes()
            if (a < b ? (n < a || n >= b) : (n < a && n >= b)) return false   // 23:00→07:00 — через полночь
        }
        return true
    }

    // ---------- срабатывание ----------
    property var lastFire: ({})            // id → время, не чаще раза в 2 с
    property var burst: []                 // времена срабатываний за последние 10 с
    property var history: ({})             // id → времена срабатываний за минуту
    function emit(type, data) {
        if (paused || !Prefs.warm) return
        for (var r of rules) {
            if (!r.on || !r.when || r.when.type !== type) continue
            if ((type === "appOpen" || type === "appClose" || type === "appFocus") && !sameApp(r.when.app, data.app)) continue
            if (type === "batteryBelow" && !(data.prev >= Number(r.when.percent) && data.now < Number(r.when.percent))) continue
            if (!allowed(r)) continue
            var now = Date.now()
            if (now - (lastFire[r.id] || 0) < 2000) continue
            var lf = Object.assign({}, lastFire); lf[r.id] = now; lastFire = lf
            burst = burst.filter(t => now - t < 10000).concat([now])
            var h = Object.assign({}, history); h[r.id] = (h[r.id] || []).filter(t => now - t < 60000).concat([now]); history = h
            // по кругу: все правила вместе — больше 20 раз за 10 с; одно правило — больше 6 раз за минуту
            // («открыт X → запустить X» с паузой в 2 с иначе плодил бы окна бесконечно)
            if (burst.length > 20 || h[r.id].length > 6) {
                paused = true
                note(r, false, Tr.t("автоматизация на паузе: правила срабатывают по кругу"))
                root.flash("!", Tr.t("Автоматизация на паузе: правила срабатывают по кругу"), Theme.error)
                return
            }
            note(r, true, "")
            fired(r.id)
            steps(r, r.then || [], 0)
        }
    }
    // app_id из niri сравниваем без регистра; в правиле можно указать и id .desktop (org.telegram.desktop.desktop)
    function sameApp(want, got) {
        var w = String(want || "").toLowerCase().replace(/\.desktop$/, ""), g = String(got || "").toLowerCase()
        return w !== "" && w === g
    }
    function note(r, ok, detail) {
        log = [{ time: Date.now(), name: r.name || r.id, ok: ok, detail: detail }].concat(log).slice(0, 20)
    }

    // действия по очереди; «подождать» откладывает остальные
    function steps(r, list, i) {
        for (; i < list.length; i++) {
            var a = list[i]
            if (a.type === "wait") {
                var ms = Math.max(0, Math.min(3600, Number(a.seconds) || 0)) * 1000
                var t = waitTimer.createObject(auto, { interval: Math.max(1, ms) })
                var next = i + 1
                t.triggered.connect(function () { t.destroy(); if (!auto.paused) auto.steps(r, list, next) })
                t.start()
                return
            }
            try { act(a) } catch (e) { note(r, false, String(e)) }
        }
    }
    Component { id: waitTimer; Timer {} }

    function sw(v, cur) { return v === "toggle" ? !cur : v === "on" }
    function act(a) {
        switch (a.type) {
        case "dnd": Notifs.setDnd(sw(a.value, Notifs.dnd)); break
        case "awake": root.setAwake(sw(a.value, root.awake)); break
        case "night": NightLight.setMode(sw(a.value, NightLight.on) ? Prefs.nightLast : "off"); break
        case "mute": if (Pipewire.defaultAudioSink && Pipewire.defaultAudioSink.audio) Pipewire.defaultAudioSink.audio.muted = !sw(a.value, !Pipewire.defaultAudioSink.audio.muted); break
        case "volume":
            if (Pipewire.defaultAudioSink && Pipewire.defaultAudioSink.audio)
                Pipewire.defaultAudioSink.audio.volume = Math.max(0, Math.min(100, Number(a.percent) || 0)) / 100
            break
        case "launch": {
            var id = String(a.app || "").replace(/\.desktop$/, "")
            var e = DesktopEntries.byId(id) || DesktopEntries.applications.values.find(x => x.id === id)
                    || DesktopEntries.heuristicLookup(id)
            if (e) root.launchApp(e)
            else throw Tr.t("нет приложения ") + a.app
            break
        }
        case "close":
            for (var k in Niri.windows) if (sameApp(a.app, Niri.windows[k].app_id)) Niri.closeWindow(Niri.windows[k].id)
            break
        case "notify":
            Quickshell.execDetached(["notify-send", "-a", Tr.t("Автоматизация"), "-i", "dialog-information", Tr.t("Автоматизация"), String(a.text || "")])
            break
        case "flash": root.flash("•", String(a.text || ""), Prefs.accent); break
        case "run":   // своей scope-группой, как приложения: переживёт перезапуск оболочки, не держит её группу
            if (String(a.cmd || "").trim())
                Quickshell.execDetached(["systemd-run", "--user", "--scope", "--collect", "--quiet",
                                         "--working-directory=" + Quickshell.env("HOME"), "sh", "-c", String(a.cmd)])
            break
        case "niri": {
            var args = String(a.cmd || "").trim().split(/\s+/).filter(x => x)
            if (args.length) Niri.action(args)
            break
        }
        }
    }
    // проверка из настроек и IPC: выполнить действия правила сейчас, без условий
    function test(id) { var r = rules.find(x => x.id === id); if (r) { note(r, true, Tr.t("проверка")); steps(r, r.then || [], 0) } }

    // ---------- источники событий ----------
    // окна: какие приложения открыты (по app_id); первая загрузка списка — без событий
    property var apps: ({})
    property bool appsReady: false
    Connections {
        target: Niri
        function onWindowsChanged() {
            var cur = {}
            for (var k in Niri.windows) { var id = Niri.windows[k].app_id; if (id) cur[id] = true }
            if (auto.appsReady) {
                for (var a in cur) if (!auto.apps[a]) auto.emit("appOpen", { app: a })
                for (var b in auto.apps) if (!cur[b]) auto.emit("appClose", { app: b })
            }
            auto.apps = cur
        }
        function onFocusedWindowChanged() {
            var w = Niri.focusedWindow
            if (w && w.app_id && w.app_id !== auto.lastFocus) { auto.lastFocus = w.app_id; auto.emit("appFocus", { app: w.app_id }) }
        }
    }
    property string lastFocus: ""
    // события начинаются, когда оболочка прогрелась (Prefs.warm): иначе при входе «открылись» бы все приложения
    Connections {
        target: Prefs
        function onWarmChanged() {
            if (!Prefs.warm) return
            auto.appsReady = true
            auto.emit("start", {})
        }
    }

    // телефон: первый список устройств (помощник KDE Connect стартует позже оболочки) — только точка отсчёта
    property bool phoneSeen: false
    property bool phoneWas: false
    Connections {
        target: KdeConnect
        function onDevicesChanged() {
            var on = KdeConnect.devices.some(d => d.reachable)
            if (auto.phoneSeen && on !== auto.phoneWas) auto.emit(on ? "phoneOn" : "phoneOff", {})
            auto.phoneSeen = true
            auto.phoneWas = on
        }
    }
    readonly property bool onBattery: UPower.onBattery
    onOnBatteryChanged: emit(onBattery ? "powerBattery" : "powerAc", {})
    readonly property real percent: UPower.displayDevice && UPower.displayDevice.isLaptopBattery ? Math.round(UPower.displayDevice.percentage * 100) : -1
    property real lastPercent: -1
    onPercentChanged: {
        if (percent >= 0 && lastPercent >= 0 && UPower.onBattery) emit("batteryBelow", { prev: lastPercent, now: percent })
        lastPercent = percent
    }
    onLockedChanged: emit(locked ? "locked" : "unlocked", {})
    readonly property bool capturing: Notifs.capturing
    onCapturingChanged: emit(capturing ? "captureOn" : "captureOff", {})
    readonly property bool vpn: Vpn.on
    onVpnChanged: emit(vpn ? "vpnOn" : "vpnOff", {})

    // время: проверка в начале каждой минуты; после сна — сразу (часы Qt отстают на время сна)
    property int lastMinute: -1
    function tick() {
        var d = new Date(), m = d.getHours() * 60 + d.getMinutes()
        clock.interval = (60 - d.getSeconds()) * 1000 - d.getMilliseconds() + 50
        clock.restart()
        if (m === lastMinute) return
        lastMinute = m
        var day = d.getDay() === 0 ? 7 : d.getDay()   // 1 — понедельник … 7 — воскресенье
        for (var r of rules) {
            if (!r.on || !r.when || r.when.type !== "time" || minutes(r.when.at) !== m) continue
            var days = r.when.days && typeof r.when.days.length === "number" ? Array.prototype.slice.call(r.when.days) : []
            if (days.length && days.indexOf(day) < 0) continue
            emitOne(r)
        }
    }
    function emitOne(r) {   // время: правило одно, а emit ищет все с этим типом — сравнение минут уже сделано
        if (paused || !Prefs.warm || !allowed(r)) return
        note(r, true, "")
        fired(r.id)
        steps(r, r.then || [], 0)
    }
    Timer { id: clock; running: auto.rules.some(r => r.on && r.when && r.when.type === "time"); onTriggered: auto.tick() }
    onRulesChanged: if (clock.running) tick()
    Connections { target: auto.lockScreen; ignoreUnknownSignals: true; function onResumed() { auto.tick() } }
}
