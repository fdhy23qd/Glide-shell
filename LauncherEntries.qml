pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Значки и прогресс программ для дока — стандарт Unity LauncherEntry: программа шлёт по сессионной шине сигнал
// com.canonical.Unity.LauncherEntry.Update("application://<id>.desktop", {count, count-visible, progress,
// progress-visible, urgent}). Так уже умеют Telegram, Chromium/Firefox (загрузки), Steam, Thunderbird и другие.
// Слушает dbus-monitor (маленькая программа на C) — его вывод разбирается построчно; программа ушла с шины —
// её значки убираются. entries: id .desktop без «.desktop» → {count, progress, urgent} (count/progress — -1, если скрыты).
Singleton {
    id: le
    property var entries: ({})
    property var senders: ({})        // уникальное имя на шине → [id программ] (одна программа может говорить за несколько)
    readonly property bool active: Prefs.warm && Prefs.dock

    function apply(sender, uri, props) {
        var key = uri.replace(/^application:\/\//, "").replace(/\.desktop$/, "")
        if (!key) return
        var cur = Object.assign({ count: -1, progress: -1, urgent: false, _count: 0, _countOn: false, _prog: 0, _progOn: false },
                                entries[key] || {})
        if ("count" in props) cur._count = props.count
        if ("count-visible" in props) cur._countOn = props["count-visible"]
        if ("progress" in props) cur._prog = props.progress
        if ("progress-visible" in props) cur._progOn = props["progress-visible"]
        if ("urgent" in props) cur.urgent = props.urgent
        cur.count = cur._countOn && cur._count > 0 ? cur._count : -1
        cur.progress = cur._progOn ? Math.max(0, Math.min(1, cur._prog)) : -1
        var e = Object.assign({}, entries); e[key] = cur; entries = e
        if ((senders[sender] || []).indexOf(key) < 0) {
            var s = Object.assign({}, senders); s[sender] = (senders[sender] || []).concat([key]); senders = s
        }
    }
    function gone(sender) {
        var keys = senders[sender]
        if (!keys) return
        var e = Object.assign({}, entries)
        for (var k of keys) delete e[k]
        entries = e
        var s = Object.assign({}, senders); delete s[sender]; senders = s
    }

    // ---- разбор вывода dbus-monitor: заголовок «signal … sender=:1.45 … member=Update», дальше аргументы строками ----
    property var msg: null
    function line(l) {
        if (!l.startsWith(" ")) {   // новый заголовок
            var m = /^signal .*sender=(\S+).*member=(\w+)/.exec(l)
            msg = m ? { sender: m[1], member: m[2], strings: [], props: {}, key: "" } : null
            return
        }
        if (!msg) return
        var t = l.trim()
        var s = /^string "(.*)"$/.exec(t)
        if (s) {
            if (msg.member === "Update" && msg.strings.length === 0) msg.strings.push(s[1])   // адрес программы
            else if (msg.member === "Update") msg.key = s[1]                                  // имя свойства
            else msg.strings.push(s[1])
            if (msg.member === "NameOwnerChanged" && msg.strings.length === 3) {
                if (msg.strings[0].startsWith(":") && msg.strings[2] === "") gone(msg.strings[0])
                msg = null
            }
            return
        }
        var v = /^variant\s+(\w+)\s+(.*)$/.exec(t)
        if (v && msg.key) {
            var val = v[1] === "boolean" ? v[2] === "true" : v[1] === "string" ? v[2].replace(/^"|"$/g, "") : Number(v[2])
            msg.props[msg.key] = val
            msg.key = ""
            return
        }
        if (t === "]" && msg.member === "Update" && l.indexOf("   ]") === 0 && l.length - t.length === 3) {   // конец словаря
            apply(msg.sender, msg.strings[0] || "", msg.props)
            msg = null
        }
    }
    Process {
        running: le.active
        command: ["setpriv", "--pdeathsig", "TERM", "dbus-monitor", "--session",
                  "type='signal',interface='com.canonical.Unity.LauncherEntry',member='Update'",
                  "type='signal',sender='org.freedesktop.DBus',member='NameOwnerChanged'"]
        stdout: SplitParser { onRead: (l) => le.line(l) }
    }
}
