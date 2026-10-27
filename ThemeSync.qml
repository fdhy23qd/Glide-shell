import QtQuick
import Quickshell
import Quickshell.Io

// Палитра Glide для других программ (сейчас — обои webpaper): «чёрный + акцент» — фон и текст
// как у amoledNoir (чёрный, белый, серые), цветные только оттенки акцента. Формат — как у DMS
// (colors.dark, dank16), файл ~/.cache/glide-shell/colors.json; пишется при каждой смене акцента.
// Настройка выключена — файл удаляется, и обои возвращаются к палитре DMS.
Scope {
    id: ts
    readonly property bool on: Prefs.themeWallpaper
    readonly property string file: (Quickshell.env("XDG_CACHE_HOME") || Quickshell.env("HOME") + "/.cache") + "/glide-shell/colors.json"

    function shade(c, toward, t) { return Qt.tint(c, Qt.rgba(toward, toward, toward, t)).toString() }   // к белому (1) или чёрному (0)
    readonly property string palette: {
        var a = Prefs.accent
        var light = shade(a, 1, 0.45), dark = shade(a, 0, 0.65)
        var c = {
            background: "#000000", surface: "#000000", on_background: "#ffffff", on_surface: "#ffffff",
            primary: a.toString(), secondary: "#a3a3a3", tertiary: light,
            outline: "#333333", primary_container: dark
        }
        return JSON.stringify({ source: "glide-shell", mode: "dark", colors: { dark: c },
                                dank16: { color13: { dark: light, "default": light } } }, null, 2) + "\n"
    }

    function sync() {
        writer.command = on
            ? ["sh", "-c", 'mkdir -p "${1%/*}" && printf %s "$2" > "$1.tmp" && mv -f "$1.tmp" "$1"', "sh", file, palette]
            : ["rm", "-f", file]
        writer.running = true
    }
    onPaletteChanged: debounce.restart()
    onOnChanged: debounce.restart()
    Timer { id: debounce; interval: 300; onTriggered: if (writer.running) restart(); else ts.sync() }
    Component.onCompleted: { debounce.restart(); appsDebounce.restart() }
    Process { id: writer }

    // ---- светлая/тёмная схема и акцент — приложениям: gsettings (GTK4/libadwaita, браузеры и Qt через портал) ----
    readonly property string scheme: Theme.isLight ? "prefer-light" : "prefer-dark"
    // акцент GNOME — ближайший из девяти по оттенку (серые — slate)
    readonly property string gnomeAccent: {
        var c = Prefs.accent
        if (c.hsvSaturation < 0.2) return "slate"
        var h = c.hsvHue * 360
        var hues = [["red", 0], ["orange", 28], ["yellow", 50], ["green", 135], ["teal", 175], ["blue", 215], ["purple", 270], ["pink", 330], ["red", 360]]
        var best = "blue", d = 999
        for (var x of hues) { var dd = Math.abs(h - x[1]); if (dd < d) { d = dd; best = x[0] } }
        return best
    }
    function syncApps() {
        if (!Prefs.themeApps) return
        var cmd = "gsettings set org.gnome.desktop.interface color-scheme " + scheme
                + "; gsettings set org.gnome.desktop.interface accent-color " + gnomeAccent + " 2>/dev/null"
        if (Prefs.themeGtk3)
            cmd += "; t=$(gsettings get org.gnome.desktop.interface gtk-theme); case $t in \"'Adwaita'\"|\"'Adwaita-dark'\") gsettings set org.gnome.desktop.interface gtk-theme "
                 + (Theme.isLight ? "Adwaita" : "Adwaita-dark") + ";; esac"
        appsProc.command = ["sh", "-c", cmd]
        appsProc.running = false; appsProc.running = true
    }
    Process { id: appsProc }
    // рамка фокуса niri — акцентом Glide (Prefs.niriAccent): при смене акцента перекрасить
    JobQueue { id: niriProc }   // по очереди: убитая посреди записи правка не откатывала конфиг niri
    function syncNiri() {
        if (!Prefs.niriAccent) return
        var c = Prefs.accent.toString()
        niriProc.add(["python3", "-I", Quickshell.shellDir + "/tools/glide-niri.py", "set-look",
                      JSON.stringify({ ring: { color: c }, border: { color: c } })])
    }
    Timer { id: niriDebounce; interval: 600; onTriggered: ts.syncNiri() }
    Connections { target: Prefs; function onAccentChanged() { niriDebounce.restart() } function onNiriAccentChanged() { niriDebounce.restart() } }
    Timer { id: appsDebounce; interval: 400; onTriggered: ts.syncApps() }
    onSchemeChanged: appsDebounce.restart()
    onGnomeAccentChanged: appsDebounce.restart()
    Connections { target: Prefs; function onThemeAppsChanged() { appsDebounce.restart() } function onThemeGtk3Changed() { appsDebounce.restart() } }
}
