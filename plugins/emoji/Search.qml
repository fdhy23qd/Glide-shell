import QtQuick
import qs
import "emoji.js" as E

// Служба «Смайликов»: в общем поиске «:огонь» — смайлики сверху; просто «огонь» — до трёх, ниже приложений.
QtObject {
    property var api
    Component.onCompleted: if (api) api.search.provide(q => {
        var t = q.trim(), colon = t[0] === ":"
        var list = colon ? E.find(t.slice(1), 5) : E.exact(t)
        return list.map(e => ({ id: e[0], title: api.lang === "en" ? e[2] : e[1],
                                sub: Tr.t("Смайлик — Enter, в буфер"), glyph: e[0], copy: e[0], top: colon }))   // glyph-строка — символ
    })
}
