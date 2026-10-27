import QtQuick
import Quickshell

// «Недавние» (plugins/recent/Service.qml): служба читает историю (GLIDE_RECENT_XBEL) и отвечает в общем поиске.
ShellRoot {
    id: root
    property bool shown: false
    property var opened: []
    function flash() {}
    QmlCheck { id: t }
    SearchProviders { id: sp }
    ApiScope { id: api; owner: "recent"; manifest: ({ api: 1, trusted: true }) }
    Loader { id: ld; active: false; source: Quickshell.shellDir + "/plugins/recent/Service.qml" }
    Component.onCompleted: {
        Core.root = root
        Permissions.register(api, "recent", "Недавние", { api: 1, trusted: true })
        ld.setSource(Quickshell.shellDir + "/plugins/recent/Service.qml", { api: api })
        ld.active = true
        t.then(100, () => {
            t.ok("служба загрузилась", ld.status === Loader.Ready, ld.status)
            if (ld.item) ld.item.pluginDir = Quickshell.shellDir + "/plugins/recent"
        })
        t.then(1500, () => {
            t.ok("список прочитан", ld.item && ld.item.list.length === 2, ld.item ? ld.item.list.map(f => f.name) : null)
            sp.query = "отчёт"
        })
        t.then(400, () => {
            t.ok("в поиске — недавний файл", sp.rest.length === 1 && sp.rest[0].label === "отчёт.pdf", sp.hits.items.map(x => x.label))
            t.ok("id — путь", sp.rest.length === 1 && sp.rest[0].id.indexOf("/отчёт.pdf") > 0)
            t.done()
        })
    }
}
