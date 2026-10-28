import QtQuick
import Quickshell

// События окон для плагинов (v2.10): открыто / изменилось / закрыто / фокус — только с разрешением «windows»;
// полный список при подключении — не «открылись», смена только раскладки — не «изменилось», фокус — по итогу.
ShellRoot {
    id: root
    QmlCheck { id: t }
    ApiScope { id: w; owner: "w"; manifest: ({ api: 2, permissions: ["windows"] }) }
    ApiScope { id: n; owner: "n"; manifest: ({ api: 2, permissions: ["windows"] }) }
    property var got: []
    property int nGot: 0
    Connections {
        target: w
        function onWindowOpened(x) { root.got = root.got.concat(["open " + x.id + " " + x.title]) }
        function onWindowChanged(x) { root.got = root.got.concat(["change " + x.id + " " + x.title]) }
        function onWindowClosed(x) { root.got = root.got.concat(["close " + x.id + " " + x.title]) }
        function onWindowFocused(x) { root.got = root.got.concat(["focus " + (x ? x.id : "none")]) }
    }
    Connections {
        target: n
        function onWindowOpened(x) { root.nGot++ }
        function onWindowFocused(x) { root.nGot++ }
        function onWindowClosed(x) { root.nGot++ }
    }
    function win(id, title, focused, layout) { return { id: id, title: title, app_id: "app", is_focused: !!focused, layout: layout || {} } }

    Component.onCompleted: {
        Core.root = root
        Prefs.data = { pluginLock: false }
        Permissions.register(w, "w", "w", { api: 2, permissions: ["windows"] })
        Permissions.register(n, "n", "n", { api: 2, permissions: ["windows"] })
        Niri.niriEvent({ WindowsChanged: { windows: [win(1, "один", true), win(2, "два")] } })
        t.then(100, () => {
            t.ok("список при подключении — без «открылось»", root.got.join("|") === "focus 1", root.got)
            root.got = []
            Niri.niriEvent({ WindowOpenedOrChanged: { window: win(3, "три", true) } })
            Niri.niriEvent({ WindowOpenedOrChanged: { window: win(3, "три", true, { pos: 1 }) } })   // только раскладка
            Niri.niriEvent({ WindowOpenedOrChanged: { window: win(3, "три — изменён", true) } })
        })
        t.then(100, () => {
            t.ok("открыто, фокус, заголовок", root.got.join("|") === "open 3 три|change 3 три — изменён|focus 3", root.got)
            root.got = []
            Niri.niriEvent({ WindowFocusChanged: { id: 2 } })
            Niri.niriEvent({ WindowClosed: { id: 3 } })
            Niri.niriEvent({ WindowClosed: { id: 99 } })      // неизвестное — молча
            Niri.niriEvent({ WindowFocusChanged: { id: null } })
        })
        t.then(100, () => {
            t.ok("фокус по итогу, закрыто", root.got.join("|") === "close 3 три — изменён|focus none", root.got)
            t.ok("без разрешения — ничего", root.nGot === 0, root.nGot)
            t.done()
        })
    }
}
