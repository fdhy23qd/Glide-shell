import QtQuick
import Quickshell

// api.notify с кнопками (v2.11): нажатая — сигнал notifyAction(id, кнопка) только своей части; чужое имя кнопки
// (не из списка) — молча; больше 5 ждущих — старое снимается; без кнопок — как раньше. Заглушка notify-send:
// заголовок «pick=X» — печатает X, «wait» — ждёт, аргументы — в журнал (проверяет tests/test_qml.py).
ShellRoot {
    id: root
    QmlCheck { id: t }
    ApiScope { id: a; owner: "a"; manifest: ({ api: 2 }) }
    ApiScope { id: b; owner: "b"; manifest: ({ api: 2 }) }
    property var got: []
    property int bGot: 0
    Connections { target: a; function onNotifyAction(id, act) { root.got = root.got.concat([id + ":" + act]) } }
    Connections { target: b; function onNotifyAction(id, act) { root.bGot++ } }
    readonly property var two: [{ id: "yes", label: "Да" }, { id: "no", label: "Нет" }]

    Component.onCompleted: {
        Prefs.data = { pluginLock: false }
        Permissions.register(a, "a", "a", { api: 2 })
        Permissions.register(b, "b", "b", { api: 2 })
        a.notify("pick=no", "текст", "", { id: "n1", actions: root.two })
        a.notify("pick=evil", "текст", "", { id: "n2", actions: root.two })           // не из списка
        a.notify("-A bad", "без кнопок")                                              // как раньше, через --
        a.notify("pick=default", "", "", { id: "n3", actions: [{ id: "default", label: "Открыть" }, { id: "bad id!", label: "x" }] })
        t.then(1500, () => {
            t.ok("нажатые — только из списка, своей части", root.got.slice().sort().join("|") === "n1:no|n3:default", root.got)
            t.ok("чужая часть не слышит", root.bGot === 0, root.bGot)
            for (var i = 0; i < 6; i++) a.notify("wait", "", "", { id: "w" + i, actions: root.two })
        })
        t.then(1500, () => {
            t.ok("ждущих не больше 5", a.notifyWaiting.length === 5, a.notifyWaiting.length)
            t.done()
        })
    }
}
