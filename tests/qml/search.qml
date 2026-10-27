import QtQuick
import Quickshell
import "plugins/calc/answers.js" as A
import "plugins/emoji/emoji.js" as E

// Провайдеры поиска (api.search, v2.5): только по разрешению «search», устаревшие ответы — прочь, поля проверены,
// выбор результата — буфер / ссылка / сигнал плагину; калькулятор, единицы, смайлики. Стенд: «s» — search, «n» — нет.
ShellRoot {
    id: root
    property bool shown: false
    property var raw: []
    property var opened: []
    function runRaw(argv, text) { raw = raw.concat([text]) }
    function openPath(p) { opened = opened.concat([p]) }
    function flash() {}
    signal pluginMessage(string from, string to, string name, var data, var sender)

    QmlCheck { id: t }
    SearchProviders { id: sp }
    ApiScope { id: s; owner: "s"; manifest: ({ api: 2, permissions: ["search"] }) }
    ApiScope { id: n; owner: "n"; manifest: ({ api: 2, permissions: ["search"] }) }
    ApiScope { id: r; owner: "r"; manifest: ({ api: 2, permissions: ["search"] }) }
    property int rCalls: 0
    property int nCalls: 0
    property var lateDone: null
    property string activated: ""
    Connections { target: s; function onSearchActivated(id) { root.activated = id } }
    Component { id: tmpScope; ApiScope { owner: "tmp"; manifest: ({ api: 2, permissions: ["search"] }) } }

    function near(a, b) { return a !== null && Math.abs(a - b) < 1e-4 * Math.max(1, Math.abs(b)) }

    Component.onCompleted: {
        Core.root = root
        Permissions.register(s, "s", "s", { api: 2, permissions: ["search"] })
        Permissions.register(n, "n", "n", { api: 2, permissions: ["search"] })
        Permissions.register(r, "r", "r", { api: 2, permissions: ["search"] })
        r.search.provide(q => { root.rCalls++; return [] })
        Permissions.revoke("r", { api: 2, permissions: ["search"] }, "search")   // забрали после регистрации
        t.ok("provide без разрешения — false", n.search.provide(q => { root.nCalls++; return [{ title: "n" }] }) === false)
        t.ok("provide с разрешением — true", s.search.provide((q, done) => {
            if (q === "медленно") { root.lateDone = done; return }
            if (q === "ошибка") throw "сломался"
            if (q === "много") return [1, 2, 3, 4, 5, 6, 7].map(i => ({ title: "r" + i }))
            return [{ title: "сверху", top: true, glyph: 0xF00EC, copy: "42" },
                    { title: "ссылка", url: "https://example.com" },
                    { title: "плохая ссылка", url: "file:///etc/passwd" },
                    { title: "", copy: "без заголовка" },
                    "не объект"]
        }))
        sp.query = "пример"
        t.then(300, () => {
            t.ok("без разрешения провайдер не зовут", root.nCalls === 0)
            t.ok("разрешение забрали — провайдера больше не зовут", root.rCalls === 0, root.rCalls)
            t.ok("мусор отброшен", sp.hits.items.length === 3, sp.hits.items.map(x => x.label))
            t.ok("top — отдельно", sp.top.length === 1 && sp.top[0].label === "сверху" && sp.rest.length === 2)
            t.ok("glyph — символ Nerd Font", sp.top[0].glyph === String.fromCodePoint(0xF00EC))
            var bad = sp.rest.find(x => x.label === "плохая ссылка")
            t.ok("ссылка не http — убрана", !!bad && bad.url === "")
            sp.activate(sp.top[0], root)
            t.ok("выбор: copy — в буфер", root.raw.length === 1 && root.raw[0] === "42", root.raw)
            sp.activate(sp.rest[0], root)
            t.ok("выбор: url — открыть", root.opened.length === 1 && root.opened[0] === "https://example.com")
            sp.activate(bad, root)
            t.ok("выбор: ни copy, ни url — сигнал плагину", root.opened.length === 1 && root.raw.length === 1)
            sp.query = "много"
        })
        t.then(250, () => {
            t.ok("не больше 5 от плагина", sp.hits.items.length === 5, sp.hits.items.length)
            sp.query = "ошибка"
        })
        t.then(250, () => {
            t.ok("ошибка провайдера — пусто, без падения", sp.hits.items.length === 0)
            sp.query = "медленно"
        })
        t.then(250, () => {
            var done = root.lateDone
            sp.query = "уже другое"
            done([{ title: "опоздал" }])
            t.ok("ответ на устаревший запрос — отброшен", !sp.hits.items.some(x => x.label === "опоздал"))
            var tmp = tmpScope.createObject(root)
            Permissions.register(tmp, "tmp", "tmp", { api: 2, permissions: ["search"] })
            var before = Core.searchProviders.length
            tmp.destroy()
            Qt.callLater(() => t.ok("часть плагина уничтожена — провайдера нет", Core.searchProviders.length === before
                                    && !Core.searchProviders.some(p => p.owner === "tmp"), Core.searchProviders.map(p => p.owner)))
        })
        t.then(200, () => {
            var c = A.calc
            t.ok("2+2*3", c("2+2*3").value === 8)
            t.ok("дробь с запятой", c("2,5*2").value === 5)
            t.ok("min(1,2) — запятая в функции", c("min(1,2)").value === 1)
            t.ok("-2^2 = -4", c("-2^2").value === -4)
            t.ok("sqrt, pi", near(c("sqrt(2)").value, Math.SQRT2) && near(c("pi*2").value, 2 * Math.PI))
            t.ok("10:2 и ×", c("10:2").value === 5 && c("3×4").value === 12)
            t.ok("не выражения — нет ответа", c("42") === null && c("привет") === null && c("firefox") === null && c("1+") === null)
            t.ok("деление на ноль, огромная степень — нет", c("10/0") === null && c("2^100000") === null)
            var u = A.units
            t.ok("5 км в милях", near(u("5 км в милях").value, 3.10686))
            t.ok("100 f в c", near(u("100 f в c").value, 37.7778))
            t.ok("1 гб в мб = 1024", u("1 гб в мб").value === 1024)
            t.ok("2 часа в минутах", u("2 часа в минутах").value === 120)
            t.ok("1 день в часах", u("1 день в часах").value === 24)
            t.ok("10 kg to lb", near(u("10 kg to lb").value, 22.0462))
            t.ok("разные величины — нет", u("5 км в кг") === null && u("5 км в км") === null && u("привет в мир") === null)
            t.ok("смайлик: огонь", E.find("огонь")[0][0] === "🔥" && E.find("fire")[0][0] === "🔥")
            t.ok("смайлик: точное слово", E.exact("огонь").some(e => e[0] === "🔥") && E.exact("ог").length === 0)
            t.done()
        })
    }
}
