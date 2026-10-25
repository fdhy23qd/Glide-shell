pragma Singleton
import QtQuick
import Quickshell

// Ссылка на корень оболочки для ApiScope — вместо свойства api.shell: через него плагин дотягивался до всей
// оболочки (runRaw мимо разрешения «exec» и т. п.). Внутреннее; обращение из плагина ловит аудит (qp_audit.py).
Singleton {
    property var root: null

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
