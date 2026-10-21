import QtQuick

// Пример своего виджета Glide Shell. Получает:
//   api — now (дата, раз в минуту), k (масштаб), tint/sub (цвета текста), accent, theme (Theme), iconFont,
//         weather (Weather), player (MPRIS или null), cpu, mem, run(argv), openUrl(url)
//   cfg — значения настроек из widget.json (title, date, showHours, style)
// Размер — implicitWidth/implicitHeight корневого элемента.
Column {
    property var api
    property var cfg
    readonly property real k: api ? api.k : 1
    readonly property var target: new Date((cfg && cfg.date ? cfg.date : "2027-01-01") + "T00:00:00")
    readonly property real msLeft: api ? Math.max(0, target - api.now) : 0
    readonly property int days: Math.floor(msLeft / 86400000)
    readonly property int hours: Math.floor(msLeft % 86400000 / 3600000)
    readonly property bool line: cfg && cfg.style === "line"
    spacing: 2 * k

    Text {
        visible: !parent.line
        text: parent.days + (cfg && cfg.showHours ? " д " + parent.hours + " ч" : "")
        color: api ? api.accent : "white"
        font.pixelSize: Math.round(64 * parent.k); font.weight: Font.Light
    }
    Text {
        text: parent.line ? (cfg && cfg.title || "") + ": " + parent.days + " дн." + (cfg && cfg.showHours ? " " + parent.hours + " ч" : "")
                          : (cfg && cfg.title) || ""
        color: api ? (parent.line ? api.tint : api.sub) : "white"
        font.pixelSize: Math.round((parent.line ? 22 : 18) * parent.k)
    }
}
