import QtQuick
import Quickshell

// v2.8: разрешение «до перезапуска», api.confirm (очередь), api.schedule (вовремя, опоздало, ждёт живую часть),
// api.pickFile / saveFile (поддельный помощник), api.clipboard.listen (поддельный wl-paste). Стенд: «c» — clipboard.
ShellRoot {
    id: root
    property bool shown: false
    function flash() {}
    QmlCheck { id: t }
    Confirms { id: confirms }
    Schedules { id: schedules }
    ClipWatch { id: clipwatch }
    ApiScope { id: s; owner: "s"; manifest: ({ api: 2, permissions: ["exec", "network"] }) }
    ApiScope { id: c; owner: "c"; manifest: ({ api: 2, permissions: ["clipboard"] }) }
    ApiScope { id: n; owner: "n"; manifest: ({ api: 2, permissions: ["clipboard"] }) }
    Component { id: ghostComp; ApiScope { owner: "ghost"; manifest: ({ api: 2 }) } }
    property var got: []
    property var clips: []
    property var nclips: []
    Connections { target: s; function onScheduled(id, data, late) { root.got = root.got.concat([[id, data, late]]) } }
    Connections { target: c; function onClipboardUpdated(text) { root.clips = root.clips.concat([text]) } }
    Connections { target: n; function onClipboardUpdated(text) { root.nclips = root.nclips.concat([text]) } }
    property var ghostGot: []
    property var answers: []

    Component.onCompleted: {
        Core.root = root
        Core.confirms = confirms; Core.schedules = schedules; Core.clipwatch = clipwatch
        Prefs.data = { pluginLock: false }
        Permissions.register(s, "s", "s", { api: 2, permissions: ["exec", "network"] })
        Permissions.register(c, "c", "c", { api: 2, permissions: ["clipboard"] })
        Permissions.register(n, "n", "n", { api: 2, permissions: ["clipboard"] })

        // ---- «до перезапуска»
        t.ok("без выдачи — нет", !s.can("network"))
        Permissions.ask("s", "s", { api: 2, permissions: ["exec", "network"] }, "network", "")
        Permissions.confirm("", true)
        t.ok("до перезапуска — выдано", s.can("network") && !s.can("exec"))
        t.ok("в файл не попало", !Permissions.grants.s)
        Permissions.revoke("s", { api: 2, permissions: ["exec", "network"] }, "network")
        t.ok("забрали — нет", !s.can("network"))

        // ---- вопросы
        t.ok("первый вопрос — в очереди", s.confirm("Удалить заметку?", { yes: "Удалить" }, ok => root.answers = root.answers.concat([["s1", ok]])))
        t.ok("второй от той же части — нет", s.confirm("Ещё?", ok => root.answers = root.answers.concat([["s2", ok]])) === false)
        t.ok("имя — из реестра", confirms.current && confirms.current.name === "s" && confirms.current.yes === "Удалить")
        c.confirm("x".repeat(900), ok => root.answers = root.answers.concat([["c1", ok]]))
        t.ok("текст обрезан до 500", confirms.queue[1].text.length === 500)
        confirms.answer(true)
        confirms.dropScope(c)

        // ---- напоминания: s — вовремя; ghost — срок прошёл, пока частей нет
        t.ok("schedule.after", s.schedule.after("tea", 300, { text: "чай" }))
        t.ok("плохая дата — нет", s.schedule.at("bad", "не дата") === false)
        schedules.set("ghost", "old", Date.now() - 120000, { n: 1 })
        t.ok("list", s.schedule.list().length === 1 && s.schedule.list()[0].id === "tea")

        // ---- буфер: без разрешения нельзя, с разрешением — слушать
        t.ok("listen без разрешения — нет", n.clipboard.listen(true) === false)
        t.ok("listen с разрешением", c.clipboard.listen(true) === true)

        // ---- выбор файла
        s.pickFile({ title: "Открыть", read: true }, (paths, texts) => {
            t.ok("pickFile: пути и текст", paths && paths[0] === "/tmp/выбран.txt" && texts && texts[0] === "содержимое", [paths, texts])
        })
        t.ok("второе окно сразу — нет", s.pickFile({}, () => {}) === false)

        t.then(1500, () => {
            var ans = root.answers.map(a => a.join(":")).sort().join(",")   // отказ второму — через callLater, порядок не важен
            t.ok("ответы на вопросы дошли", ans === "s1:true,s2:false", root.answers)
            t.ok("снятый вопрос — без ответа", !root.answers.some(a => a[0] === "c1") && confirms.queue.length === 0)
            t.ok("напоминание вовремя", root.got.length === 1 && root.got[0][0] === "tea" && root.got[0][1].text === "чай" && root.got[0][2] === false, root.got)
            t.ok("без живой части — ждёт", schedules.list.some(x => x.owner === "ghost"))
            var g = ghostComp.createObject(root)
            g.scheduled.connect((id, data, late) => root.ghostGot = root.ghostGot.concat([[id, late]]))
            Permissions.register(g, "ghost", "ghost", { api: 2 })
            t.ok("буфер: смены пришли", JSON.stringify(root.clips) === JSON.stringify(["привет\nмир", "второй"]), root.clips)
            t.ok("без разрешения — ничего", root.nclips.length === 0)
            s.saveFile("заметки.txt", "текст для сохранения", path => t.ok("saveFile: путь", path === "/tmp/куда.txt", path))
        })
        t.then(1200, () => {
            t.ok("появилась часть — опоздавшее пришло с late", JSON.stringify(root.ghostGot) === JSON.stringify([["old", true]]), root.ghostGot)
            Permissions.revoke("c", { api: 2, permissions: ["clipboard"] }, "clipboard")
            t.ok("забрали «Буфер» — слушатель снят", clipwatch.listeners.length === 0)
        })
        t.then(800, () => {
            t.ok("wl-paste остановлен", !clipwatch.watcher.running)
            t.done()
        })
    }
}
