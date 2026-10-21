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
    Component.onCompleted: debounce.restart()
    Process { id: writer }
}
