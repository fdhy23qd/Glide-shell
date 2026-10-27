import QtQuick
import Quickshell
import Quickshell.Io

// Ядро: разрешения из резервной копии и правка в обход (v2.3), повторная регистрация api (v2.2), очередь
// JobQueue (v2.3), история уведомлений — запись больше 128 КБ и номера при восстановлении (v2.2).
// Стенд кладёт: permissions.json (пусто) и permissions.json.import (x: exec), notifications.json (номера 1–3).
ShellRoot {
    QmlCheck { id: t }
    ApiScope { id: p; owner: "p"; manifest: ({ api: 2, permissions: [] }) }
    JobQueue { id: q; property var out: []; onFinished: (s) => out = out.concat([s.trim()]) }
    property int tamperCount: 0
    Connections { target: Permissions; function onTampered() { tamperCount++ } }
    FileView { id: permFile; path: Permissions.path; blockLoading: true; printErrors: false }
    Process { id: tamper; command: ["sh", "-c", "printf '%s' '{\"plugins\":{\"evil\":{\"api\":2,\"granted\":[\"exec\"]}}}' > \"$1\"", "sh", Permissions.path] }

    Component.onCompleted: {
        // уведомление пришло раньше, чем загрузилась история: номер 1 — как у старой записи
        Notifs.list = [{ key: ++Notifs.seq, time: Date.now(), appName: "новое", summary: "новое", body: "", urgency: 1, unread: true, n: null, actions: [] }]
        for (var i = 1; i <= 4; i++) q.add(["sh", "-c", "sleep 0.1; echo $1", "sh", String(i)])

        t.then(800, () => {
            t.ok("разрешения из .import подхвачены", !!Permissions.grants.x && Permissions.grants.x.granted.indexOf("exec") >= 0, Permissions.grants)
            t.ok("подхват — без «правки в обход»", tamperCount === 0, tamperCount)
            permFile.reload()
            t.ok("permissions.json переписан", permFile.text().indexOf('"x"') >= 0)
            t.ok("очередь: все по порядку", JSON.stringify(q.out) === JSON.stringify(["1", "2", "3", "4"]), q.out)
            var keys = Notifs.list.map(e => e.key)
            t.ok("история: старые записи не пропали", Notifs.list.length === 4, Notifs.list.map(e => e.summary))
            t.ok("история: номера уникальны", new Set(keys).size === keys.length, keys)
            // повторная регистрация того же объекта: новые permissions действуют, trusted не появляется
            Permissions.register(p, "p", "p", { api: 2, permissions: [] })
            Permissions.register(p, "p", "p", { api: 2, permissions: ["exec"], trusted: true })
            t.ok("перерегистрация: новые permissions", Permissions.requested(p.spec).indexOf("exec") >= 0)
            t.ok("перерегистрация: trusted не получить", p.spec.trusted === false)
            Permissions.register(p, "чужой", "x", {})
            t.ok("чужой id тому же api — отказ", p.me === "p")
            // отказ на «разрешить всё» — без «*» в файле
            Permissions.askAll("p", "p", { api: 1 })
            Permissions.deny()
            t.ok("отказ «всё» не пишет «*»", JSON.stringify(Permissions.grants).indexOf('"*"') < 0)
            // большая история — через stdin
            var big = "я".repeat(4000), l = []
            for (var i = 0; i < 50; i++) l.push({ key: 100 + i, time: 0, appName: "a", summary: "s" + i, body: big, urgency: 1, n: null, actions: [] })
            Notifs.list = l
            Notifs.saveHistory()
            tamper.running = true
        })
        t.then(1500, () => {
            t.ok("правка в обход отменена", !Permissions.grants.evil && tamperCount === 1, [Object.keys(Permissions.grants), tamperCount])
            permFile.reload()
            t.ok("в файле правки в обход не осталось", permFile.text().indexOf("evil") < 0)
            t.done()
        })
    }
}
