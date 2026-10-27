import QtQuick
import Quickshell
import Quickshell.Io

// Буфер для плагинов (api.clipboard.listen, разрешение «clipboard»): wl-paste --watch, только пока кто-то слушает.
// Каждая смена текста — строкой base64 (переводы строк внутри не рвут разбор); пароли с пометкой менеджера паролей
// (x-kde-passwordManagerHint) и не текст — пропускаются, длиннее 20 000 байт — обрезаются.
QtObject {
    id: cw
    property var listeners: []            // объекты api
    readonly property string tool: Quickshell.env("GLIDE_WLPASTE") || "wl-paste"
    function listen(scope, on) {
        var rest = listeners.filter(x => x !== scope)
        listeners = on ? rest.concat([scope]) : rest
    }
    property Process watcher: Process {
        running: cw.listeners.length > 0
        command: ["setpriv", "--pdeathsig", "TERM", cw.tool, "--type", "text", "--watch", "sh", "-c",
                  cw.tool + ' -l 2>/dev/null | grep -q x-kde-passwordManagerHint && exit 0; head -c 20000 | base64 -w0; echo']
        stdout: SplitParser {
            onRead: line => {
                if (!line) return
                var text
                try { text = Qt.atob(line) } catch (e) { return }   // Qt 6: UTF-8 уже раскодирован
                for (var s of cw.listeners)
                    if (Permissions.allowed(s, "clipboard")) s.clipboardUpdated(text)
            }
        }
    }
}
