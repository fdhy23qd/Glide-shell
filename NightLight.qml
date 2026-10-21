pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Ночной свет: тёплый экран через wlsunset (wlr-gamma-control, niri его поддерживает). «Всегда» — нижняя и
// верхняя температура почти равны; «по солнцу» — восход и закат из погоды (без неё 07:00–21:00), переход 30 мин.
// При выходе wlsunset (и при падении оболочки — pdeathsig) niri сам возвращает обычную гамму.
Singleton {
    id: nl
    readonly property string mode: Prefs.night
    readonly property bool on: mode !== "off"
    property bool available: false                 // есть ли wlsunset: проверка при старте и при каждом включении
    property bool pendingToggle: false              // щёлкнули, пока не знали — решить после проверки
    signal missing()                                // включают, а wlsunset нет (плитка покажет подсказку)
    readonly property string bin: Quickshell.env("GLIDE_WLSUNSET") || "wlsunset"
    readonly property var wx: Weather.data && !Weather.data.error ? Weather.data : null
    readonly property string sunrise: wx && /^\d\d:\d\d$/.test(wx.sunrise) ? wx.sunrise : "07:00"
    readonly property string sunset: wx && /^\d\d:\d\d$/.test(wx.sunset) ? wx.sunset : "21:00"
    readonly property var args: mode === "on" ? ["-t", String(Prefs.nightTemp), "-T", String(Prefs.nightTemp + 1)]
        : ["-t", String(Prefs.nightTemp), "-T", "6500", "-S", sunrise, "-s", sunset, "-d", "1800"]

    function setMode(m) {
        Prefs.set("night", m)
        if (m !== "off") { Prefs.set("nightLast", m); if (!available) recheck() }
    }
    // wlsunset могли поставить, пока оболочка работала — перед включением проверяем заново
    function toggle() {
        if (on || available) { setMode(on ? "off" : Prefs.nightLast); return }
        pendingToggle = true
        recheck()
    }
    function recheck() { checker.running = false; checker.running = true }

    Process {
        id: checker
        running: true
        command: ["sh", "-c", "command -v \"$1\" >/dev/null", "sh", nl.bin]
        onExited: (code) => {
            nl.available = code === 0
            if (!nl.pendingToggle) return
            nl.pendingToggle = false
            if (nl.available) nl.setMode(Prefs.nightLast); else nl.missing()
        }
    }
    Process {
        id: proc
        running: nl.on && nl.available
        command: ["setpriv", "--pdeathsig", "TERM", nl.bin].concat(nl.args)
        stderr: SplitParser { onRead: (l) => console.warn("wlsunset: " + l) }
    }
    // другие параметры — перезапустить (Process не перечитывает command на ходу)
    onArgsChanged: if (proc.running) { proc.running = false; restart.restart() }
    Timer { id: restart; interval: 150; onTriggered: proc.running = Qt.binding(() => nl.on && nl.available) }
}
