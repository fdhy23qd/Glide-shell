pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// KDE Connect: сопряжённые устройства из kdeconnectd (tools/glide-kdeconnect.py watch — по сигналам D-Bus,
// без опроса) и действия: найти, пинг, буфер, текст/ссылка, файлы на телефон, файлы телефона, SMS.
// Уведомления телефона приходят сами — kdeconnectd шлёт их на наш сервер уведомлений.
Singleton {
    id: kc
    property var devices: []      // [{id, name, type, reachable, plugins, battery, charging, network, signal}]
    readonly property var phone: {   // главное устройство: первое на связи, иначе первое сопряжённое
        for (var d of devices) if (d.reachable) return d
        return devices.length ? devices[0] : null
    }
    readonly property bool available: Prefs.kdeconnect && devices.length > 0

    Process {
        id: watcher
        running: Prefs.kdeconnect && Prefs.warm   // через несколько секунд после старта
        stdinEnabled: true   // закрытый stdin — сигнал помощнику выйти
        command: ["setpriv", "--pdeathsig", "TERM", "python3", "-I", Quickshell.shellDir + "/tools/glide-kdeconnect.py", "watch"]
        stdout: SplitParser { onRead: line => { try { kc.devices = JSON.parse(line) } catch (e) {} } }
        onExited: if (Prefs.kdeconnect) restart.restart()   // kdeconnectd ещё не запустился — попробуем позже
    }
    Timer { id: restart; interval: 10000; onTriggered: if (Prefs.kdeconnect) watcher.running = true }

    function has(d, plugin) { return !!d && d.plugins.indexOf(plugin) >= 0 }
    function act(d, action, text) {
        if (!d) return
        Quickshell.execDetached(["python3", "-I", Quickshell.shellDir + "/tools/glide-kdeconnect.py", "act", d.id, action]
                                .concat(text ? [text] : []))
    }
    // значок устройства (MDI) и сети
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
