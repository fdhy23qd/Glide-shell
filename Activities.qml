pragma Singleton
import QtQuick
import Quickshell

// «Живые активности» — строки в острове от плагинов и приложений: загрузка, сборка, отсчёт. У каждой — id, значок,
// название, подпись, прогресс (0…1; меньше 0 — без прогресса, бегущая полоска) и необязательная кнопка.
// Показывается самая свежая; при наведении — «ещё N». Источники: api.activity (плагины), IPC и D-Bus (приложения).
Singleton {
    id: acts
    property var list: []                        // новые — первыми
    readonly property var top: list.length ? list[0] : null
    signal clicked(string id)                    // щелчок по строке
    signal action(string id)                     // кнопка активности (props.actionLabel)
    signal ended(string id)

    function find(id) { return list.findIndex(a => a.id === id) }
    // props: {title, subtitle, icon (символ значка), progress, color, actionLabel, onClick (функция), onAction, owner}
    function start(id, props) {
        var a = Object.assign({ id: id, title: "", subtitle: "", icon: "", progress: -1, color: "", actionLabel: "",
                                ts: Date.now() }, props || {})
        list = [a].concat(list.filter(x => x.id !== id))
        return id
    }
    function update(id, props) {
        var i = find(id)
        if (i < 0) return start(id, props)
        var l = list.slice()
        l[i] = Object.assign({}, l[i], props || {}, { ts: Date.now() })
        list = l
        return id
    }
    function end(id) {
        if (find(id) < 0) return
        list = list.filter(x => x.id !== id)
        ended(id)
    }
    function endOwner(owner) { for (var a of list.filter(x => x.owner === owner)) end(a.id) }
    function click(id) {
        var a = list[find(id)]
        if (!a) return
        if (typeof a.onClick === "function") a.onClick()
        clicked(id)
    }
    function act(id) {
        var a = list[find(id)]
        if (!a) return
        if (typeof a.onAction === "function") a.onAction()
        action(id)
    }
}
