.pragma library
// Быстрые ответы для общего поиска (Search.qml): выражение и перевод единиц. Без eval — свой разбор, как в calc.py:
// + - * / % ^ (степень), скобки, sqrt sin cos tan log ln exp abs round floor ceil min max, pi, e; «2,5» — дробь.

// ---------------------------------------------------------------- выражение
var FUNCS = {
    sqrt: Math.sqrt, sin: Math.sin, cos: Math.cos, tan: Math.tan, log: Math.log10, lg: Math.log10, ln: Math.log,
    log2: Math.log2, exp: Math.exp, abs: Math.abs, round: Math.round, floor: Math.floor, ceil: Math.ceil,
    min: Math.min, max: Math.max
}
var CONSTS = { pi: Math.PI, "π": Math.PI, e: Math.E }

function tokens(s) {
    var out = [], i = 0, parens = []   // parens: true — скобка функции (в ней «,» — разделитель, а не дробь)
    s = s.replace(/[×·]/g, "*").replace(/[÷:]/g, "/").replace(/−/g, "-").replace(/\*\*/g, "^")
    while (i < s.length) {
        var c = s[i]
        if (c === " ") { i++; continue }
        var m = /^\d+(?:[.,]\d+)?/.exec(s.slice(i))
        if (m) {
            var num = m[0]
            if (num.indexOf(",") >= 0 && parens.length && parens[parens.length - 1]) num = /^\d+/.exec(num)[0]   // min(1,2)
            out.push({ t: "n", v: parseFloat(num.replace(",", ".")) })
            i += num.length
            continue
        }
        m = /^[a-zπ][a-z0-9]*/i.exec(s.slice(i))
        if (m) { out.push({ t: "w", v: m[0].toLowerCase() }); i += m[0].length; continue }
        if ("+-*/%^(),".indexOf(c) >= 0) {
            if (c === "(") parens.push(out.length > 0 && out[out.length - 1].t === "w")
            if (c === ")") parens.pop()
            out.push({ t: c })
            i++
            continue
        }
        return null
    }
    return out
}

function parse(toks) {
    var i = 0
    function peek() { return toks[i] ? toks[i].t : "" }
    function expr() {
        var v = term()
        while (peek() === "+" || peek() === "-") { var op = toks[i++].t; var r = term(); v = op === "+" ? v + r : v - r }
        return v
    }
    function term() {
        var v = unary()
        while (peek() === "*" || peek() === "/" || peek() === "%") {
            var op = toks[i++].t, r = unary()
            v = op === "*" ? v * r : op === "/" ? v / r : v % r
        }
        return v
    }
    function unary() {
        if (peek() === "-") { i++; return -unary() }
        if (peek() === "+") { i++; return unary() }
        return power()
    }
    function power() {
        var b = primary()
        if (peek() !== "^") return b
        i++
        var x = unary()
        if (Math.abs(x) > 1000) throw "big"
        return Math.pow(b, x)
    }
    function primary() {
        var tk = toks[i++]
        if (!tk) throw "end"
        if (tk.t === "n") return tk.v
        if (tk.t === "(") { var v = expr(); if (toks[i++].t !== ")") throw ")"; return v }
        if (tk.t === "w") {
            if (CONSTS[tk.v] !== undefined && peek() !== "(") return CONSTS[tk.v]
            var f = FUNCS[tk.v]
            if (!f || toks[i++].t !== "(") throw "name"
            var args = [expr()]
            while (peek() === ",") { i++; args.push(expr()) }
            if (!toks[i] || toks[i++].t !== ")") throw ")"
            return f.apply(null, args)
        }
        throw "token"
    }
    var v = expr()
    if (i !== toks.length) throw "tail"
    return v
}

function fmt(v) {
    if (Number.isInteger(v) && Math.abs(v) < 1e15) return String(v)
    if (Math.abs(v) >= 1e15 || (v !== 0 && Math.abs(v) < 1e-9)) return v.toExponential(10).replace(/\.?0+e/, "e")
    return String(parseFloat(v.toPrecision(12)))
}

// {value, text} или null: только если это действительно выражение (есть действие или функция), а не число или слово
function calc(q) {
    var s = q.trim()
    if (s.length < 2 || s.length > 200) return null
    if (s[0] === "=") s = s.slice(1)
    var toks = tokens(s)
    if (!toks || !toks.length) return null
    var ops = toks.some(t => "+-*/%^".indexOf(t.t) >= 0 && t !== toks[0]) || toks.some(t => t.t === "w" && FUNCS[t.v])
    if (!ops) return null
    if (toks.some(t => t.t === "w" && !FUNCS[t.v] && CONSTS[t.v] === undefined)) return null   // слова — это не выражение
    try {
        var v = parse(toks)
        if (typeof v !== "number" || !isFinite(v)) return null
        return { value: v, text: fmt(v) }
    } catch (e) {
        return null
    }
}

// ---------------------------------------------------------------- единицы
// [единица, во что переводить (множитель к базовой), короткое имя ru, en, основы и слова для узнавания]
var UNITS = {
    length: [["m", 1, "м", "m", ["м", "m", "meter", "meters", "metre", "metres"], ["метр"]],
             ["km", 1000, "км", "km", ["км", "km", "kilometer", "kilometers"], ["километр"]],
             ["cm", 0.01, "см", "cm", ["см", "cm"], ["сантиметр"]],
             ["mm", 0.001, "мм", "mm", ["мм", "mm"], ["миллиметр"]],
             ["mi", 1609.344, "миль", "mi", ["mi", "mile", "miles"], ["мил"]],
             ["ft", 0.3048, "фт", "ft", ["фт", "ft", "foot", "feet"], ["фут"]],
             ["in", 0.0254, "дюйм.", "in", ["inch", "inches", "\""], ["дюйм"]],
             ["yd", 0.9144, "ярд.", "yd", ["yd", "yard", "yards"], ["ярд"]]],
    mass: [["kg", 1, "кг", "kg", ["кг", "kg", "kilogram", "kilograms"], ["килограмм"]],
           ["g", 0.001, "г", "g", ["г", "g", "gram", "grams", "гр"], ["грамм"]],
           ["mg", 1e-6, "мг", "mg", ["мг", "mg"], ["миллиграмм"]],
           ["t", 1000, "т", "t", ["т", "t", "ton", "tons", "tonne", "tonnes"], ["тонн"]],
           ["lb", 0.45359237, "фунт.", "lb", ["lb", "lbs", "pound", "pounds"], ["фунт"]],
           ["oz", 0.028349523125, "унц.", "oz", ["oz", "ounce", "ounces"], ["унци"]]],
    time: [["s", 1, "с", "s", ["с", "s", "сек", "sec", "second", "seconds"], ["секунд"]],
           ["min", 60, "мин", "min", ["мин", "min", "minute", "minutes"], ["минут"]],
           ["h", 3600, "ч", "h", ["ч", "h", "hour", "hours", "час", "часа", "часов", "часах", "часы"], []],
           ["d", 86400, "сут.", "d", ["d", "day", "days", "день", "дня", "дней", "днях", "сутки", "суток", "сутках"], []],
           ["wk", 604800, "нед.", "wk", ["week", "weeks", "нед"], ["недел"]]],
    data: [["B", 1, "Б", "B", ["б", "b", "byte", "bytes"], ["байт"]],
           ["KiB", 1024, "КиБ", "KiB", ["кб", "kb", "kib", "кбайт"], ["килобайт"]],
           ["MiB", 1048576, "МиБ", "MiB", ["мб", "mb", "mib", "мбайт"], ["мегабайт"]],
           ["GiB", 1073741824, "ГиБ", "GiB", ["гб", "gb", "gib", "гбайт"], ["гигабайт"]],
           ["TiB", 1099511627776, "ТиБ", "TiB", ["тб", "tb", "tib", "тбайт"], ["терабайт"]]],
    speed: [["kmh", 1 / 3.6, "км/ч", "km/h", ["км/ч", "km/h", "kmh", "kph"], []],
            ["ms", 1, "м/с", "m/s", ["м/с", "m/s"], []],
            ["mph", 0.44704, "миль/ч", "mph", ["mph", "миль/ч"], []]],
    volume: [["l", 1, "л", "l", ["л", "l", "liter", "liters", "litre", "litres"], ["литр"]],
             ["ml", 0.001, "мл", "ml", ["мл", "ml"], ["миллилитр"]],
             ["gal", 3.785411784, "гал.", "gal", ["gal", "gallon", "gallons"], ["галлон"]]],
    temp: [["C", 0, "°C", "°C", ["c", "с", "°c", "°с", "celsius"], ["цельси"]],
           ["F", 0, "°F", "°F", ["f", "°f", "fahrenheit"], ["фаренгейт"]],
           ["K", 0, "K", "K", ["k", "к", "kelvin"], ["кельвин"]]]
}
var ENDINGS = ["", "а", "ы", "ов", "ах", "ам", "и", "ей", "й", "я", "ях", "е", "у", "ю", "ь", "ой", "ями"]

function unitOf(word) {
    var w = word.toLowerCase().replace(/\.$/, "").trim()
    for (var dim in UNITS) for (var u of UNITS[dim]) {
        if (u[4].indexOf(w) >= 0) return { dim: dim, u: u }
        for (var stem of u[5]) if (w.indexOf(stem) === 0 && ENDINGS.indexOf(w.slice(stem.length)) >= 0) return { dim: dim, u: u }
    }
    return null
}
function toBase(dim, u, v) { return dim !== "temp" ? v * u[1] : u[0] === "C" ? v : u[0] === "F" ? (v - 32) * 5 / 9 : v - 273.15 }
function fromBase(dim, u, v) { return dim !== "temp" ? v / u[1] : u[0] === "C" ? v : u[0] === "F" ? v * 9 / 5 + 32 : v + 273.15 }
function round6(v) { return String(parseFloat(v.toPrecision(6))) }

// «5 км в милях», «100 f to c», «2,5 гб в мб» → {value, text, from, to} или null
function units(q, lang) {
    var m = /^\s*(-?\d+(?:[.,]\d+)?)\s*(.+?)\s+(?:в|во|на|in|to|into|->|=)\s+(.+?)\s*\??$/i.exec(q)
    if (!m) return null
    var a = unitOf(m[2]), b = unitOf(m[3])
    if (!a || !b || a.dim !== b.dim || a.u === b.u) return null
    var v = parseFloat(m[1].replace(",", "."))
    var r = fromBase(b.dim, b.u, toBase(a.dim, a.u, v))
    if (!isFinite(r)) return null
    var i = lang === "en" ? 3 : 2
    return { value: r, text: round6(r), from: round6(v) + " " + a.u[i], to: round6(r) + " " + b.u[i] }
}
