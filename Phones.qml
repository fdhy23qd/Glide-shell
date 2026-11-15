pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Телефоны из двух источников, одним списком для бара, плагина «Телефон», автоматизации и api.kdeconnect:
//  · Glide Link — tools/glide-link.py watch (демон сам присылает изменения, без опроса);
//  · KDE Connect — tools/glide-kdeconnect.py watch (сигналы D-Bus kdeconnectd).
// У устройства поле backend ("glidelink" | "kdeconnect"); act() отдаёт действие нужному помощнику.
// Уведомления телефона приходят сами — оба демона шлют их на наш сервер уведомлений.
Singleton {
    id: ph
    property var linkDevices: []   // Glide Link: [{id, name, type, reachable, plugins, battery, charging, network, streams, …}]
    property var linkPairing: []   // запросы сопряжения: [{id, name, code, keyChanged}]
    property var linkFound: []     // найдены в сети, не сопряжены: [{id, name, address}]
    property var linkMe: ({})      // это устройство в Glide Link: {id, name, relay}
    property bool linkUp: false    // демон glide-link отвечает
    property string selectedId: "" // телефон, выбранный в плагине (если их несколько)
    property var kdeDevices: []    // KDE Connect: [{id, name, type, reachable, plugins, battery, charging, network, signal}]
    // сначала Glide Link: главным становится первое устройство на связи — значит, Glide Link, потом KDE Connect
    readonly property var devices: (Prefs.glidelink ? linkDevices : []).concat(Prefs.kdeconnect ? kdeDevices : [])
    readonly property var phone: {   // выбранный; иначе первое на связи; иначе первое сопряжённое
        for (var s of devices) if (s.id === selectedId) return s
        for (var d of devices) if (d.reachable) return d
        return devices.length ? devices[0] : null
    }
    readonly property bool available: (Prefs.kdeconnect || Prefs.glidelink) && devices.length > 0

    Process {
        id: linkWatch
        running: Prefs.glidelink && Prefs.warm
        stdinEnabled: true   // закрытый stdin — сигнал помощнику выйти
        command: ["setpriv", "--pdeathsig", "TERM", "python3", "-I", Quickshell.shellDir + "/tools/glide-link.py", "watch"]
        stdout: SplitParser { onRead: line => ph.linkState(line) }
        onExited: {   // демон не запущен или перезапустился
            ph.linkDevices = []; ph.linkPairing = []; ph.linkFound = []; ph.linkUp = false
            if (Prefs.glidelink) linkRestart.restart()
        }
    }
    Timer { id: linkRestart; interval: 10000; onTriggered: if (Prefs.glidelink) linkWatch.running = true }

    Process {
        id: kdeWatch
        running: Prefs.kdeconnect && Prefs.warm   // через несколько секунд после старта
        stdinEnabled: true
        command: ["setpriv", "--pdeathsig", "TERM", "python3", "-I", Quickshell.shellDir + "/tools/glide-kdeconnect.py", "watch"]
        stdout: SplitParser { onRead: line => { try { ph.kdeDevices = ph.tag(JSON.parse(line), "kdeconnect") } catch (e) {} } }
        onExited: if (Prefs.kdeconnect) kdeRestart.restart()   // kdeconnectd ещё не запустился — попробуем позже
    }
    Timer { id: kdeRestart; interval: 10000; onTriggered: if (Prefs.kdeconnect) kdeWatch.running = true }

    // уведомления ПК → телефон (Glide Link), если включено: кроме «не беспокоить» и зеркал самих телефонов
    Connections {
        target: Notifs
        function onReceived(e) { ph.forward(e) }
    }
    readonly property var mirrorApps: ["Glide Link", "KDE Connect", "kdeconnect", "kdeconnectd", "kdeconnect.daemon"]
    function forward(e) {
        if (!Prefs.glidelink || !Prefs.phoneNotifs || !ph.linkUp || Notifs.quiet) return false
        if (mirrorApps.indexOf(e.appName || "") >= 0) return false
        if (!ph.linkDevices.some(d => d.reachable && d.plugins.indexOf("notification") >= 0)) return false
        var plain = s => String(s || "").replace(/<[^>]*>/g, "")
        request({ cmd: "notify-phone", id: String(e.time) + ":" + (e.appName || ""), app: e.appName || "",
                  title: plain(e.summary), text: plain(e.body) })
        return true
    }

    function tag(list, backend) { return list.map(d => Object.assign({}, d, { backend: backend })) }
    function linkState(line) {
        try {
            var o = JSON.parse(line)
            ph.linkDevices = ph.tag(o.devices || [], "glidelink")
            ph.linkPairing = o.pairing || []
            ph.linkFound = o.discovered || []
            ph.linkMe = o.me || {}
            ph.linkUp = true
        } catch (e) {}
    }

    // команда демону Glide Link с ответом: cb({ok, error, …}) — SMS, файлы телефона, команды
    Component {
        id: callComp
        Process {
            id: callProc
            property var cb: null
            stdout: StdioCollector {
                onStreamFinished: {
                    var r
                    try { r = JSON.parse(text) } catch (e) { r = { ok: false, error: Tr.t("Glide Link не ответил") } }
                    if (callProc.cb) callProc.cb(r)
                    callProc.destroy()
                }
            }
        }
    }
    function request(req, cb) {
        var p = callComp.createObject(ph, { cb: cb || null,
            command: ["setpriv", "--pdeathsig", "TERM", "python3", "-I", Quickshell.shellDir + "/tools/glide-link.py", "call", JSON.stringify(req)] })
        p.running = true
    }
    function connectTo(address) {   // по IP: «192.168.0.4» или «192.168.0.4:17385»
        Quickshell.execDetached(["python3", "-I", Quickshell.shellDir + "/tools/glide-link.py", "connect", address])
    }
    function has(d, plugin) { return !!d && d.plugins.indexOf(plugin) >= 0 }
    function isLink(d) { return !!d && d.backend === "glidelink" }
    function streaming(d, what) { return isLink(d) && !!d.streams && !!d.streams[what] }

    // команда помощника для действия (отдельно — чтобы проверять в тестах без запуска)
    function command(d, action, text) {
        var tool = isLink(d) ? "/tools/glide-link.py" : "/tools/glide-kdeconnect.py"
        return ["python3", "-I", Quickshell.shellDir + tool, "act", d.id, action].concat(text ? [text] : [])
    }
    function act(d, action, text) {
        if (!d) return
        Quickshell.execDetached(command(d, action, text))
    }
    // значок устройства (MDI) и заряда
    function glyph(d) {
        if (!d) return String.fromCodePoint(0xF011C)
        // телефоны KDE Connect нередко называет «tablet» — для планшета и телефона один значок
        return String.fromCodePoint(d.type === "desktop" ? 0xF0379 : d.type === "laptop" ? 0xF0322 : 0xF011C)
    }
    function batteryGlyph(d) {
        if (!d || d.battery === undefined) return ""
        if (d.charging) return String.fromCodePoint(0xF0084)
        var i = Math.round(d.battery / 10)
        return String.fromCodePoint(i >= 10 ? 0xF0079 : i <= 0 ? 0xF008E : 0xF007A + i - 1)
    }
}
