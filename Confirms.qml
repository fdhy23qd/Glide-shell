import QtQuick

// Вопросы плагинов человеку (api.confirm): очередь, окно — ConfirmDialog.qml. От части плагина — один вопрос за раз,
// всего в очереди — не больше 5; лишний сразу получает «нет». Имя спрашивающего — из реестра разрешений (подделать
// нельзя), текст — простой, до 500 знаков. Часть плагина уничтожена — её вопросы снимаются без ответа.
QtObject {
    id: cf
    property var queue: []                // [{scope, name, text, yes, no, cb}]
    readonly property var current: queue.length ? queue[0] : null
    function ask(scope, name, text, opts, cb) {
        if (typeof opts === "function") { cb = opts; opts = {} }
        opts = opts || {}
        if (queue.some(x => x.scope === scope) || queue.length >= 5) {
            if (cb) Qt.callLater(() => { try { cb(false) } catch (e) {} })
            return false
        }
        queue = queue.concat([{ scope: scope, name: String(name || "?").slice(0, 60), text: String(text || "").slice(0, 500),
                                yes: String(opts.yes || "").slice(0, 30), no: String(opts.no || "").slice(0, 30), cb: cb || null }])
        return true
    }
    function answer(yes) {
        var c = current
        if (!c) return
        queue = queue.slice(1)
        try { if (c.cb) c.cb(yes === true) } catch (e) { console.warn("glide-shell: api.confirm: " + e) }
    }
    function dropScope(scope) { queue = queue.filter(x => x.scope !== scope) }
}
