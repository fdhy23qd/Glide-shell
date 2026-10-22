pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications

// Уведомления: сервер org.freedesktop.Notifications, всплывающее в острове и история для панели.
// Сервер — за флагом Prefs.notifications: у имени на шине один владелец, и пока работает DMS,
// он держит его сам (настройки → «Уведомления»).
// Запись истории: {key, n, appName, appIcon, desktopEntry, summary, body, image, urgency, time, actions}.
// n — живое уведомление (для действий); после закрытия — null, запись остаётся в истории.
Singleton {
    id: ns

    readonly property bool active: Prefs.notifications
    property var list: []            // новые сверху
    property var popup: null         // запись, которую сейчас показывает остров
    property bool replyLock: false   // в острове пишут ответ (shell.qml replying)
    property int unread: 0
    property bool hold: false        // курсор над уведомлением в острове — не прячем
    property int seq: 0
    readonly property int maxHistory: 50

    // ---- «не беспокоить»: всплывающих нет (кроме срочных), история пишется ----
    property bool dnd: false
    readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/glide-shell"
    FileView {
        id: dndFile
        path: ns.stateDir + "/dnd"
        printErrors: false
        onLoaded: ns.dnd = text().trim() === "1"
        onLoadFailed: dmsSession.reload()   // первый раз — берём состояние у DMS
    }
    FileView {
        id: dmsSession
        path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/DankMaterialShell/session.json"
        preload: false
        printErrors: false
        onLoaded: { try { ns.setDnd(JSON.parse(text()).doNotDisturb === true) } catch (e) {} }
    }
    function setDnd(on) {
        dnd = on
        dndFile.setText(on ? "1\n" : "0\n")
        if (on && popup && popup.urgency !== NotificationUrgency.Critical) popup = null
    }

    // «тишина» = вручную, по расписанию (Prefs.dndFrom..dndTo, часы) или пока идёт демонстрация экрана
    property bool night: false
    readonly property bool casting: Prefs.dndCasting && Niri.casts.length > 0
    readonly property bool quiet: dnd || night || casting
    readonly property string quietReason: dnd ? Tr.t("вручную") : casting ? Tr.t("идёт демонстрация экрана") : night ? Tr.t("по расписанию") : ""
    function checkNight() {
        if (!Prefs.dndSchedule) { night = false; return }
        var h = new Date().getHours(), a = Prefs.dndFrom, b = Prefs.dndTo
        night = a > b ? (h >= a || h < b) : (h >= a && h < b)   // 23→8 переходит через полночь
    }
    Timer { running: true; repeat: true; interval: 60000; triggeredOnStart: true; onTriggered: ns.checkNight() }
    Connections { target: Prefs; function onDataChanged() { ns.checkNight() } }
    onQuietChanged: if (quiet && popup && popup.urgency !== NotificationUrgency.Critical) hidePopup()

    LazyLoader {
        active: ns.active
        NotificationServer {
            keepOnReload: false
            actionsSupported: true
            bodySupported: true
            bodyMarkupSupported: true      // <b>, <i>, <u>, <a> — рисуем как StyledText
            bodyHyperlinksSupported: true
            imageSupported: true
            persistenceSupported: true
            inlineReplySupported: true     // ответ прямо из острова (Telegram, KDE Connect…)
            onNotification: n => ns.add(n)
        }
    }

    // Тело — StyledText: <img src="http…"> подгрузил бы картинку из сети (пиксель слежения) — вырезаем
    function safeBody(s) { return (s || "").replace(/<img\b[^>]*>/gi, "") }
    // Ссылки из уведомлений — только в браузер/почту: file:, .desktop и свои схемы приложений не открываем
    function openLink(link) {
        if (/^(https?:|mailto:)/i.test(link)) Qt.openUrlExternally(link)
        else console.warn("glide-shell: ссылка из уведомления не открыта:", link)
    }
    function snapshot(n) {
        return n.actions.filter(a => a.identifier !== "default" && a.identifier !== "inline-reply").map(a => ({ id: a.identifier, text: a.text }))
    }
    function add(n) {
        n.tracked = true
        var e = {
            key: ++seq, n: n, time: Date.now(),
            appName: n.appName || "", appIcon: n.appIcon || "", desktopEntry: n.desktopEntry || "",
            summary: n.summary || "", body: safeBody(n.body), image: n.image || "",
            urgency: n.urgency, actions: snapshot(n),
            hasDefault: n.actions.some(a => a.identifier === "default"),
            reply: !!n.hasInlineReply, replyHint: n.inlineReplyPlaceholder || ""
        }
        // приложение обновило уведомление (прогресс, новое сообщение в той же беседе)
        var update = function () {
            e.summary = n.summary || ""; e.body = safeBody(n.body); e.image = n.image || ""
            e.actions = ns.snapshot(n)
            ns.touch()
            if (ns.popup === e) ns.popupChanged()
        }
        n.summaryChanged.connect(update)
        n.bodyChanged.connect(update)
        n.closed.connect(function (reason) {
            e.n = null
            e.actions = []
            e.hasDefault = false
            e.reply = false
            if (reason === NotificationCloseReason.CloseRequested) ns.drop(e)   // приложение отозвало
            else ns.touch()
        })

        var l = [e].concat(list)
        while (l.length > maxHistory) {
            var old = l.pop()
            if (old.unread) { old.unread = false; unread = Math.max(0, unread - 1) }   // ушло из истории — счётчик тоже
            if (old.n) old.n.dismiss()
        }
        list = l
        if (!n.transient) { e.unread = true; unread++ }
        show(e)
    }
    function touch() { list = list.slice() }   // перерисовать историю после изменения записей

    function show(e) {
        var critical = e.urgency === NotificationUrgency.Critical
        if ((quiet || replyLock) && !critical) return   // пишут ответ — новое не вытесняет (оно в истории)
        if (!critical && Prefs.notifMuted.indexOf(e.appName || "") >= 0) return   // приложение без всплывашек — только история
        popup = e
        if (critical) { popupTimer.stop(); return }   // срочное висит, пока не закроют
        var t = e.n && e.n.expireTimeout > 0 ? e.n.expireTimeout * 1000 : 6000
        popupTimer.interval = Math.max(3000, Math.min(12000, t))
        popupTimer.restart()
    }
    Timer {
        id: popupTimer
        onTriggered: if (ns.hold) restart(); else ns.popup = null
    }
    function hidePopup() { popupTimer.stop(); popup = null }

    // ---- действия ----
    function invoke(e, id) {
        if (e && e.n) for (var a of e.n.actions) if (a.identifier === id) { a.invoke(); break }
        if (popup === e) hidePopup()
    }
    // ответ из острова: приложение получит текст (NotificationReplied), уведомление закрывается
    function sendReply(e, text) {
        if (!e || !e.n || !e.reply || !text.trim()) return false
        e.n.sendInlineReply(text)
        if (e.unread) { e.unread = false; unread = Math.max(0, unread - 1) }
        if (popup === e) hidePopup()
        return true
    }
    // клик по уведомлению: действие по умолчанию, иначе — окно приложения; false — нечего делать
    function activate(e) {
        if (!e) return false
        if (e.hasDefault && e.n) { invoke(e, "default"); return true }
        var ids = [e.desktopEntry, e.appName].filter(x => x).map(x => x.toLowerCase())
        for (var id in Niri.windows) {
            var w = Niri.windows[id], app = (w.app_id || "").toLowerCase()
            if (app && ids.some(x => app === x || app.endsWith("." + x) || x.endsWith("." + app))) {
                Niri.focusWindow(w.id)
                if (popup === e) hidePopup()
                return true
            }
        }
        return false
    }
    function drop(e) {
        if (popup === e) hidePopup()
        if (e.unread) { e.unread = false; unread = Math.max(0, unread - 1) }   // отозванное или закрытое — уже не непрочитано
        list = list.filter(x => x !== e)
    }
    function remove(e) {   // пользователь закрыл крестиком
        if (e.n) e.n.dismiss()
        drop(e)
    }
    // ---- история на диске: переживает перезапуск оболочки (Prefs.notifKeep) ----
    // ~/.local/state/glide-shell/notifications.json, права 0600 (в уведомлениях бывают личные сообщения).
    // Пишется не чаще раза в секунду; живое уведомление (n) и действия не сохраняются, картинка — только файл.
    readonly property string historyFile: stateDir + "/notifications.json"
    property bool restored: false
    onListChanged: if (restored) saveTimer.restart()
    Timer { id: saveTimer; interval: 1000; onTriggered: ns.saveHistory() }
    function saveHistory() {
        if (!Prefs.notifKeep) { saver.write(""); return }
        var plain = list.map(e => ({ key: e.key, time: e.time, appName: e.appName, appIcon: e.appIcon,
                                     desktopEntry: e.desktopEntry, summary: e.summary, body: e.body,
                                     image: /^(\/|file:)/.test(e.image || "") ? e.image : "",
                                     urgency: e.urgency, unread: !!e.unread }))
        saver.write(JSON.stringify(plain))
    }
    Process {
        id: saver
        property string pending: ""
        property bool dirty: false
        function write(t) { pending = t; dirty = true; if (!running) flush() }
        function flush() {
            if (!dirty) return
            dirty = false
            command = ["sh", "-c", 'umask 077; mkdir -p "${1%/*}"; if [ -z "$2" ]; then rm -f "$1"; else printf %s "$2" > "$1.tmp" && mv "$1.tmp" "$1"; fi',
                       "sh", ns.historyFile, pending]
            running = true
        }
        onExited: flush()
    }
    FileView {
        path: ns.historyFile
        printErrors: false
        onLoaded: {
            var old = []
            try { old = JSON.parse(text()) } catch (e) {}
            if (!Prefs.notifKeep) old = []
            var seen = {}
            for (var e of ns.list) seen[e.key] = true
            var got = old.filter(x => x && !seen[x.key]).map(x => Object.assign(x, { n: null, actions: [], hasDefault: false, reply: false }))
            ns.list = ns.list.concat(got).slice(0, ns.maxHistory)
            ns.unread = ns.list.filter(x => x.unread).length
            ns.seq = Math.max(ns.seq, Math.max.apply(null, ns.list.map(x => x.key).concat([0])))
            ns.restored = true
        }
        onLoadFailed: ns.restored = true
    }
    Connections { target: Prefs; function onNotifKeepChanged() { ns.saveHistory() } }

    function clear() {
        for (var e of list) if (e.n) e.n.dismiss()
        list = []
        hidePopup()
        unread = 0
    }
    function removeApp(app) {   // убрать из истории все уведомления приложения (IPC notifClear — после проверок)
        var n = 0
        for (var e of list.slice()) if (e.appName === app) { remove(e); n++ }
        return n
    }
    function markRead() { for (var e of list) e.unread = false; unread = 0 }

    // значок: картинка из уведомления, иначе значок приложения (путь, file://, имя из темы или .desktop)
    function iconFor(e) {
        if (!e) return ""
        if (e.image) return e.image
        var i = e.appIcon
        if (i.startsWith("/")) return "file://" + i
        if (i.indexOf("://") > 0) return i
        return (i && Quickshell.iconPath(i, true)) || Niri.iconFor(e.desktopEntry || e.appName.toLowerCase())
    }
    function ago(t) {
        var s = Math.floor((Date.now() - t) / 1000)
        if (s < 60) return Tr.t("сейчас")
        if (s < 3600) return Math.floor(s / 60) + Tr.t(" мин")
        if (s < 86400) return Math.floor(s / 3600) + Tr.t(" ч")
        return Qt.formatDateTime(new Date(t), "dd.MM HH:mm")
    }
}
