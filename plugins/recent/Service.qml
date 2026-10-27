import QtQuick
import Quickshell
import Quickshell.Io
import qs
import "kinds.js" as K

// Служба «Недавних»: держит список (recent.py) и отвечает в общем поиске — недавние файлы, имя которых подходит,
// выше обычного поиска файлов. Список обновляется, когда меняется recently-used.xbel.
QtObject {
    id: svc
    property var api
    property string pluginDir: ""
    property var list: []
    readonly property string xbel: (Quickshell.env("XDG_DATA_HOME") || Quickshell.env("HOME") + "/.local/share") + "/recently-used.xbel"
    // команда — явно при запуске: привязка к pluginDir пересчитывается позже обработчика onPluginDirChanged
    property Process rd: Process {
        stdout: StdioCollector { onStreamFinished: { try { svc.list = JSON.parse(text) } catch (e) {} } }
    }
    function reload() { if (!pluginDir || rd.running) return; rd.command = ["python3", "-I", pluginDir + "/recent.py"]; rd.running = true }
    property FileView watch: FileView {
        path: svc.xbel; watchChanges: true; printErrors: false; preload: false
        onFileChanged: again.restart()
    }
    property Timer again: Timer { interval: 1500; onTriggered: svc.reload() }   // пишут пачками
    onPluginDirChanged: reload()
    function open(path) { Quickshell.execDetached(["systemd-run", "--user", "--scope", "--collect", "--quiet", "xdg-open", path]) }
    property Connections act: Connections {
        target: svc.api; ignoreUnknownSignals: true
        function onSearchActivated(id) { svc.open(id) }
    }
    Component.onCompleted: if (api) api.search.provide(q => {
        var words = q.toLowerCase().split(/\s+/).filter(w => w)
        if (!words.length || q.trim().length < 2) return []
        var out = []
        for (var f of svc.list) {
            var n = f.name.toLowerCase()
            if (words.every(w => n.indexOf(w) >= 0)) out.push(f)
            if (out.length >= 3) break
        }
        return out.map(f => ({ id: f.path, title: f.name, sub: f.dir + Tr.t(" · недавний"), glyph: K.glyph(f.mime, f.name) }))
    })
}
