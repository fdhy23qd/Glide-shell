import QtQuick
import "answers.js" as A

// Служба калькулятора: ответ прямо в общем поиске — выражение («2+2*3», «sqrt(2)») и перевод единиц
// («5 км в милях», «100 f в c»). Enter — результат в буфер. Разбор — answers.js (без eval).
QtObject {
    id: s
    property var api
    Component.onCompleted: if (api) api.search.provide(q => {
        var out = []
        var c = A.calc(q)
        if (c) out.push({ id: "calc", title: c.text, sub: q.trim() + " =", glyph: 0xF00EC, copy: c.text, top: true })
        var u = A.units(q, api.lang)
        if (u) out.push({ id: "units", title: u.to, sub: u.from + " =", glyph: 0xF046D, copy: u.text, top: true })
        return out
    })
}
