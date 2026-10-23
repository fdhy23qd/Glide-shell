pragma Singleton
import QtQuick
import Quickshell

// Ссылка на корень оболочки для ApiScope — вместо свойства api.shell: через него плагин дотягивался до всей
// оболочки (runRaw мимо разрешения «exec» и т. п.). Внутреннее; обращение из плагина ловит аудит (qp_audit.py).
Singleton {
    property var root: null
}
