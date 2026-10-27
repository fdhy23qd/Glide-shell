import QtQuick
import Quickshell

// Результаты плагинов в общем поиске (api.search.provide, разрешение «search»). Опрос — с паузой после ввода:
// провайдеру — запрос и done(); ответ на устаревший запрос отбрасывается. Провайдер, который бросил ошибку или
// вернул мусор, просто молчит. От каждого — не больше 5 результатов, поля — проверенные (docs/API.md, «Поиск»).
QtObject {
    id: sp
    property string query: ""
    property var hits: ({ q: "", items: [] })       // items — уже проверенные, в порядке опроса
    readonly property var top: hits.q === query ? hits.items.filter(x => x.top) : []
    readonly property var rest: hits.q === query ? hits.items.filter(x => !x.top) : []
    property var byOwner: ({})

    onQueryChanged: { byOwner = {}; hits = { q: query, items: [] }; ask.restart() }
    property Timer ask: Timer { interval: 80; onTriggered: sp.run(sp.query) }

    function run(q) {
        if (q.trim().length < 1) return
        for (var p of Core.searchProviders) {
            if (!Permissions.allowed(p.scope, "search")) continue
            let prov = p
            var done = items => sp.accept(prov, q, items)
            try {
                var r = prov.fn(q, done)
                if (Array.isArray(r)) done(r)
            } catch (e) {
                console.warn("glide-shell: поиск плагина " + prov.owner + ": " + e)
            }
        }
    }
    function str(v, n) { return typeof v === "string" ? v.slice(0, n) : typeof v === "number" ? String(v).slice(0, n) : "" }
    function clean(prov, x) {
        if (!x || typeof x !== "object") return null
        var title = str(x.title, 200)
        if (!title) return null
        var glyph = typeof x.glyph === "number" && x.glyph > 0 && x.glyph < 0x110000 ? String.fromCodePoint(x.glyph) : ""
        var symbol = typeof x.glyph === "string" ? x.glyph.slice(0, 8) : ""   // смайлик, буква — обычным шрифтом
        var url = str(x.url, 2000)
        return { kind: "plugin", label: title, sub: str(x.sub, 120), glyph: glyph, symbol: symbol,
                 icon: str(x.icon, 120), copy: typeof x.copy === "string" ? x.copy.slice(0, 100000) : "",
                 url: /^(https?:|mailto:)/i.test(url) ? url : "", id: str(x.id, 200), top: x.top === true,
                 owner: prov.owner, scope: prov.scope }
    }
    function accept(prov, q, items) {
        if (q !== query || !Array.isArray(items)) return
        var got = items.slice(0, 5).map(x => clean(prov, x)).filter(x => x)
        var b = Object.assign({}, byOwner)
        b[prov.owner] = got
        byOwner = b
        var all = []
        for (var k in b) all = all.concat(b[k])
        hits = { q: q, items: all }
    }
    // выбрали результат плагина: текст — в буфер, ссылка — открыть, иначе — сигнал плагину. true — панель закрыть
    function activate(r, shell) {
        if (r.copy !== "") {
            shell.runRaw(["sh", "-c", 'printf %s "$QP_TEXT" | wl-copy'], r.copy, "")
            shell.flash(String.fromCodePoint(0xF018F), Tr.t("Скопировано: ") + (r.copy.length > 40 ? r.copy.slice(0, 40) + "…" : r.copy), Theme.success)
        } else if (r.url !== "") {
            shell.openPath(r.url)
        } else if (r.scope) {
            r.scope.searchActivated(r.id)
        }
        return true
    }
}
