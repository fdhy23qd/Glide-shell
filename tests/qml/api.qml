import QtQuick
import Quickshell
import Quickshell.Io

// API плагинов: права только по разрешениям, без обходов (v2.2). Разрешения — в permissions.json стенда:
// «t» — только windows, «e» — только exec, «ai» — встроенный (trusted).
ShellRoot {
    id: root
    property bool shown: false
    property var handoff: ({ to: "ai", text: "ВЫДЕЛЕНИЕ", prompt: "" })
    property var launched: []
    property var raw: []
    function launchApp(e) { launched = launched.concat([String(e.id)]) }
    function runRaw(argv, text, dir) { raw = raw.concat([argv.join(" ")]) }
    function flash() {}
    function close() {}
    readonly property QtObject api: QtObject {
        function takeHandoff(id) { var h = root.handoff; if (!h || h.to !== id) return null; root.handoff = null; return h }
    }
    signal pluginMessage(string from, string to, string name, var data, var sender)

    QmlCheck { id: t }
    ApiScope { id: win; owner: "t"; manifest: ({ api: 2, permissions: ["windows"] }) }
    ApiScope { id: ex; owner: "e"; manifest: ({ api: 2, permissions: ["exec"] }) }
    ApiScope { id: ai; owner: "ai"; manifest: ({ api: 1, trusted: true }) }

    Component.onCompleted: {
        Core.root = root
        Permissions.register(win, "t", "t", { api: 2, permissions: ["windows"] })
        Permissions.register(ex, "e", "e", { api: 2, permissions: ["exec"] })
        Permissions.register(ai, "ai", "ai", { api: 1, trusted: true })

        t.then(300, () => {
            t.ok("права по реестру", win.can("windows") && !win.can("exec") && ex.can("exec") && !ex.can("windows") && ai.can("exec"))
            // launchApp: только приложение из .desktop по id, поддельный command — нет
            win.launchApp({ id: "nope", command: ["sh", "-c", "touch /tmp/glide-qmltest-pwned"] })
            win.launchApp({ id: "glidetest", command: ["evil"] })
            win.launchApp("glidetest.desktop")
            t.ok("launchApp — только .desktop по id", JSON.stringify(root.launched) === JSON.stringify(["glidetest", "glidetest"]), root.launched)
            // niri: без windows — null; spawn — только с exec; ключ перед именем не прячет spawn
            t.ok("api.niri без разрешения — null", ex.niri === null)
            t.ok("api.niri — обёртка, не Niri", !!win.niri && win.niri !== Niri && typeof win.niri.windows === "object")
            t.ok("spawn без exec — отказ", win.niri.action(["spawn", "touch", "/tmp/x"]) === false)
            t.ok("spawn-sh без exec — отказ", win.niri.action(["spawn-sh", "x"]) === false)
            t.ok("«--» перед spawn — отказ", win.niri.action(["--", "spawn", "x"]) === false)
            t.ok("quit без exec — отказ", win.niri.action(["quit"]) === false)
            t.ok("обычное действие — да", win.niri.action(["focus-workspace", "2"]) === true)
            // handoff: только своё
            t.ok("чужой handoff не виден", win.handoff === null && win.takeHandoff("ai") === null)
            t.ok("свой handoff виден", !!ai.handoff && ai.handoff.text === "ВЫДЕЛЕНИЕ")
            var h = ai.takeHandoff("другое")
            t.ok("takeHandoff — своё, id не важен", !!h && h.text === "ВЫДЕЛЕНИЕ" && root.handoff === null)
            // без разрешений — ничего
            win.copy("x"); win.run(["true"], "")
            t.ok("copy/run без разрешений — не запускаются", root.raw.length === 0, root.raw)
            win.setPref("accent", "#ff0000")
            t.ok("setPref без system — нет", Prefs.data.accent === undefined)
            win.setPref("pluginLock", false)
            t.ok("contextText без clipboard — пусто", win.contextText === "")
            // exec: без разрешения -1, с разрешением — работает
            win.exec(["echo", "нет"], (code) => t.ok("exec без разрешения — -1", code === -1, code))
            ex.exec(["echo", "привет"], { timeout: 5000 }, (code, out) => t.ok("exec с разрешением", code === 0 && out.trim() === "привет", [code, out]))
            ex.exec(["glide-нет-такой-программы"], (code) => t.ok("exec: нет программы — -1", code === -1, code))
            // своё хранилище и файлы
            win.storage.set("k", { n: 1 })
            t.ok("storage", win.storage.get("k", null).n === 1 && win.storage.keys().indexOf("k") >= 0)
            win.files.write("note.txt", "текст", (ok) => {
                t.ok("files.write", ok)
                win.files.read("note.txt", (txt) => t.ok("files.read", txt === "текст", txt))
            })
            win.files.write("../наружу.txt", "x", (ok) => t.ok("files: путь наружу — отказ", ok === false))
        })
        t.then(1500, () => t.done())   // что дошло до niri — проверяет test_qml.py по журналу заглушки
    }
}
