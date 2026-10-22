import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import Quickshell.Services.UPower

// API для QML-плагинов и своих виджетов, версия 1 (описание — docs/API.md). Свой объект у каждого плагина и
// виджета: хранилище, настройки и уведомления — от его имени. Прежние поля (run, flash, copy, theme…) — как были.
QtObject {
    id: api

    required property var shell             // корень оболочки (shell.qml)
    property string owner: ""               // id плагина или «widget:<id>»
    property string ownerName: owner        // имя — в уведомлениях
    property var manifest: ({})             // plugin.json / widget.json (поле settings — схема настроек)
    readonly property int version: 1

    // ---------- прежнее (плагины) ----------
    readonly property bool shown: shell.shown
    readonly property string contextText: shell.contextText    // выделение или буфер в момент вызова
    readonly property var handoff: shell.handoff
    readonly property color accent: Prefs.accent
    readonly property color accentText: Theme.accentText
    readonly property var appCounts: shell.appCounts
    function launchApp(entry) { shell.launchApp(entry) }
    readonly property bool awake: shell.awake
    readonly property var powerTimer: shell.powerTimer
    property var now: shell.now                               // у виджета — дата (DeskWidget задаёт свою)
    readonly property var notifs: Notifs
    readonly property var weather: Weather
    readonly property var recorder: Recorder
    readonly property var kdeconnect: KdeConnect
    readonly property var theme: Theme
    readonly property string iconFont: Prefs.iconFont
    function setPref(key, value) { Prefs.set(key, value) }
    function setAwake(on) { shell.setAwake(on) }
    function run(argv, text) { shell.runRaw(argv, text || "", "") }
    function close() { shell.close() }
    function openCategory(id) { shell.openCategory(id) }
    function copy(text) { shell.runRaw(["sh", "-c", 'printf %s "$QP_TEXT" | wl-copy'], text, "") }
    function flash(icon, text, color) { shell.flash(icon, text, color) }
    function openUrl(url) { Qt.openUrlExternally(url) }
    function takeHandoff(id) { return shell.api.takeHandoff(id) }

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
    readonly property var niri: Niri                                         // windows, workspaces, focused…, action(…)
    readonly property var players: Mpris.players.values                     // все плееры MPRIS
    readonly property var player: shell.musicPlayer || players[0] || null  // тот, что сейчас играл последним
    readonly property var battery: {                                        // {present, percent, charging}
        var d = UPower.displayDevice
        return { present: !!d && d.isLaptopBattery, percent: d ? Math.round(d.percentage * 100) : 0,
                 charging: !!d && d.state === UPowerDeviceState.Charging }
    }
    readonly property real volume: shell.sink && shell.sink.audio ? shell.sink.audio.volume : 0
    readonly property bool muted: shell.sink && shell.sink.audio ? shell.sink.audio.muted : false
    function setVolume(v) { if (shell.sink && shell.sink.audio) shell.sink.audio.volume = Math.max(0, Math.min(1.5, v)) }
    function setMuted(on) { if (shell.sink && shell.sink.audio) shell.sink.audio.muted = on }
    readonly property bool dnd: Notifs.quiet

    // ---------- уведомление от имени плагина ----------
    function notify(title, body, icon) {
        Quickshell.execDetached(["notify-send", "-a", ownerName || "Glide Shell", "-i", icon || "dialog-information",
                                 String(title || ""), String(body || "")])
    }

    // ---------- «живые активности» в острове (Activities.qml): id — свой, внутри плагина ----------
    // props: {title, subtitle, icon, progress (0…1, меньше 0 — без процента), color, actionLabel, onClick, onAction}
    readonly property QtObject activity: QtObject {
        function start(id, props) { return Activities.start(api.owner + "/" + id, Object.assign({ owner: api.owner }, props || {})) }
        function update(id, props) { return Activities.update(api.owner + "/" + id, Object.assign({ owner: api.owner }, props || {})) }
        function end(id) { Activities.end(api.owner + "/" + id) }
    }

    // ---------- хранилище: свой JSON в ~/.local/state/glide-shell/plugin-<id>.json ----------
    property var stored: ({})
    readonly property string storeFile: owner ? (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state")
                                                + "/glide-shell/plugin-" + owner.replace(/[^\w.-]/g, "_") + ".json" : ""
    readonly property QtObject storage: QtObject {
        readonly property var all: api.stored
        function get(key, def) { return api.stored[key] !== undefined ? api.stored[key] : def }
        function set(key, value) { var c = Object.assign({}, api.stored); c[key] = value; api.stored = c; api.saveLater.restart() }
        function remove(key) { var c = Object.assign({}, api.stored); delete c[key]; api.stored = c; api.saveLater.restart() }
    }
    property FileView storeView: FileView {
        path: api.storeFile
        printErrors: false
        blockLoading: true
        atomicWrites: true
        watchChanges: true                  // раздел плагина и его элемент бара — разные объекты, файл один
        onFileChanged: reload()
        onLoaded: { try { api.stored = JSON.parse(text()) || {} } catch (e) { api.stored = {} } }
    }
    property Timer saveLater: Timer { interval: 300; onTriggered: api.storeView.setText(JSON.stringify(api.stored)) }

    // ---------- настройки из манифеста («settings»: [{key, type, label, default, options}]) ----------
    // значения — в config.json (panel.pluginSettings[id]): попадают в резервную копию; меняются во вкладке «Плагины»
    readonly property var settings: {
        var saved = (Prefs.pluginSettings || {})[owner] || {}, out = {}
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
    function setSetting(key, value) { Prefs.setPluginSetting(owner, key, value) }

    // ---------- события ----------
    signal opened()                    // панель открылась
    signal closed()                    // … закрылась
    signal themeUpdated()              // акцент, тон или светлая/тёмная тема (не themeChanged: так зовётся смена свойства theme)
    signal notification(var entry)     // пришло уведомление: {appName, summary, body, urgency, time}
    property Connections shellConn: Connections {
        target: api.shell
        function onShownChanged() { if (api.shell.shown) api.opened(); else api.closed() }
    }
    property Connections themeConn: Connections {
        target: Theme
        function onIsLightChanged() { api.themeUpdated() }
        function onAccentChanged() { api.themeUpdated() }
        function onBackgroundChanged() { api.themeUpdated() }
    }
    property Connections notifsConn: Connections {
        target: Notifs
        function onReceived(entry) { api.notification(entry) }
    }
}
