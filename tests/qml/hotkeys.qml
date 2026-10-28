import QtQuick
import Quickshell

// api.hotkey (v2.12) на копии настроек niri ($GLIDE_NIRI_DIR): кривая и занятая клавиша — сразу «нет», без вопроса;
// «Не надо» — не ставится; «Поставить» — привязка в glide-settings.kdl, в list(); нажатие — только своему плагину;
// новая клавиша того же имени — старая убрана; remove — убрана. Файлы проверяет tests/test_qml.py.
ShellRoot {
    id: root
    function flash() {}
    QmlCheck { id: t }
    Confirms { id: confirms }
    Hotkeys { id: hotkeys }
    ApiScope { id: a; owner: "a"; manifest: ({ api: 2 }) }
    ApiScope { id: b; owner: "b"; manifest: ({ api: 2 }) }
    property var res: []
    property var pressedA: []
    property int pressedB: 0
    Connections { target: a; function onHotkeyPressed(n) { root.pressedA = root.pressedA.concat([n]) } }
    Connections { target: b; function onHotkeyPressed(n) { root.pressedB++ } }
    function rec(tag) { return (ok, why) => { root.res = root.res.concat([tag + ":" + ok + ":" + why]) } }

    Component.onCompleted: {
        Core.root = root; Core.confirms = confirms; Core.hotkeys = hotkeys
        Prefs.data = { pluginLock: false }
        Permissions.register(a, "a", "Плагин А", { api: 2 })
        Permissions.register(b, "b", "b", { api: 2 })
        a.hotkey.request("go", "W", "", rec("bare"))
        a.hotkey.request("bad name!", "Mod+W", "", rec("name"))
        t.then(300, () => {
            t.ok("кривые — сразу нет", root.res.join("|") === "bare:false:bad|name:false:bad", root.res)
            root.res = []
            a.hotkey.request("go", "Mod+T", "", rec("busy"))
        })
        t.then(2500, () => {
            t.ok("занятая — нет, без вопроса", root.res.join("|") === "busy:false:busy" && !confirms.current, root.res)
            root.res = []
            a.hotkey.request("go", "Mod+Shift+W", "Пуск", rec("deny"))
        })
        t.then(1500, () => {
            t.ok("вопрос — с именем из реестра", !!confirms.current && confirms.current.name === "Плагин А"
                 && confirms.current.text.indexOf("Mod+Shift+W") >= 0, confirms.current ? confirms.current.name + ": " + confirms.current.text : null)
            confirms.answer(false)
        })
        t.then(300, () => {
            t.ok("«Не надо» — не ставится", root.res.join("|") === "deny:false:denied", root.res)
            root.res = []
            a.hotkey.request("go", "Mod+Shift+W", "Пуск", rec("yes"))
        })
        t.then(1500, () => confirms.answer(true))
        t.then(3000, () => {
            t.ok("поставлена", root.res.join("|") === "yes:true:", root.res)
            t.ok("в списке", JSON.stringify(a.hotkey.list()) === JSON.stringify([{ name: "go", key: "Mod+Shift+W", title: "Пуск" }]), a.hotkey.list())
            t.ok("у чужого — пусто", b.hotkey.list().length === 0)
            hotkeys.press("a/go"); hotkeys.press("b/go"); hotkeys.press("a/../x"); hotkeys.press("nothing")
            t.ok("нажатие — своему", root.pressedA.join() === "go" && root.pressedB === 1, [root.pressedA, root.pressedB])
            root.res = []
            a.hotkey.request("go", "Mod+Shift+E", "", rec("move"))
        })
        t.then(1500, () => confirms.answer(true))
        t.then(3000, () => {
            t.ok("переставлена", root.res.join("|") === "move:true:" && a.hotkey.list().length === 1
                 && a.hotkey.list()[0].key === "Mod+Shift+E", [root.res, a.hotkey.list()])
            root.res = []
            a.hotkey.request("other", "Mod+Shift+E", "", rec("taken"))   // своя же, но под другим именем — занята
            b.hotkey.remove("go", rec("chremove"))                       // чужую не убрать
        })
        t.then(2500, () => {
            t.ok("своя под другим именем — занята, чужую не убрать", root.res.slice().sort().join("|") === "chremove:false:undefined|taken:false:busy", root.res)
            root.res = []
            a.hotkey.remove("go", rec("remove"))
        })
        t.then(3000, () => {
            t.ok("убрана", root.res.join("|") === "remove:true:undefined" && a.hotkey.list().length === 0, [root.res, a.hotkey.list()])
            t.done()
        })
    }
}
