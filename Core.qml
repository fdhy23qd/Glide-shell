pragma Singleton
import QtQuick
import Quickshell

// Ссылка на корень оболочки для ApiScope — вместо свойства api.shell: через него плагин дотягивался до всей
// оболочки (runRaw мимо разрешения «exec» и т. п.). Внутреннее; обращение из плагина ловит аудит (qp_audit.py).
Singleton {
    property var root: null
    property var confirms: null   // вопросы плагинов человеку (Confirms.qml, окно — ConfirmDialog.qml)
    property var schedules: null  // напоминания плагинов (Schedules.qml)
    property var clipwatch: null  // смена буфера для плагинов (ClipWatch.qml)
    property var hotkeys: null    // глобальные клавиши плагинов (Hotkeys.qml)
    property var wallpaper: null  // обои рабочего стола (Wallpaper.qml) — для фона замка «как обои»

    // провайдеры поиска (api.search.provide): [{scope, owner, fn}] — у части плагина один; опрашивает SearchProviders.qml
    property var searchProviders: []
    function setSearch(scope, owner, fn) {
        var rest = searchProviders.filter(x => x.scope !== scope)
        searchProviders = typeof fn === "function" ? rest.concat([{ scope: scope, owner: owner, fn: fn }]) : rest
    }

    // фон острова картинкой от плагина (api.island.backdrop): {owner, src, mode, dim} или null; один на всех —
    // побеждает последний задавший, снять может только он. Только локальный файл-картинка: без сети — остров не
    // должен ничего тянуть из интернета (счётчики просмотров и т. п.). Путь может нести ?запрос — чтобы перечитать файл.
    property var islandBackdrop: null
    function setBackdrop(owner, src, opts) {
        if (src === "" || src === null || src === undefined) {
            if (islandBackdrop && islandBackdrop.owner === owner) islandBackdrop = null
            return true
        }
        var s = String(src).trim()
        if (s.length > 4096) return false
        var path = s.indexOf("file://") === 0 ? s.slice(7) : s
        var q = path.indexOf("?")
        var bare = q >= 0 ? path.slice(0, q) : path
        if (bare.charAt(0) !== "/" || bare.indexOf("/../") >= 0 || !/\.(png|jpe?g|webp|bmp)$/i.test(bare)) return false
        var o = opts || {}
        var dim = Number(o.dim)
        islandBackdrop = {
            owner: owner, src: "file://" + path,
            mode: o.mode === "fill" ? "fill" : "screen",
            dim: isNaN(dim) || o.dim === undefined || o.dim === null ? 0.35 : Math.max(0, Math.min(0.8, dim))
        }
        return true
    }

    // цвета плагинов для острова (api.island.tint): [{owner, color}] в порядке, в каком их задали; у плагина — один
    property var islandTints: []
    function setTint(owner, c) {
        var rest = islandTints.filter(t => t.owner !== owner)
        if (c === "" || c === null || c === undefined) { islandTints = rest; return true }
        var s = String(c).trim()
        if (!/^#([0-9a-f]{3}|[0-9a-f]{6}|[0-9a-f]{8})$/i.test(s) && !/^[a-z]+$/i.test(s)) return false
        var col
        try { col = Qt.color(s) } catch (e) { return false }
        if (!col || col.valid === false) return false
        islandTints = rest.concat([{ owner: owner, color: Qt.rgba(col.r, col.g, col.b, 1) }])   // без прозрачности
        return true
    }
}
