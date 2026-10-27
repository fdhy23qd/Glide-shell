import QtQuick
import Quickshell

// Съёмные диски (Drives.qml, v2.6) с поддельным помощником (GLIDE_DRIVES_TOOL) и notify-send: вставленное до запуска —
// без уведомлений; новое — подключается и сообщает с кнопками; зашифрованное — не подключается; без «подключать сами» —
// кнопка «Подключить»; извлечь и ошибка отключения. Помощник выдаёт список по шагам (файл-указатель STEP).
ShellRoot {
    id: root
    property var flashes: []
    function flash(icon, text) { flashes = flashes.concat([text]) }
    QmlCheck { id: t }
    property var results: []
    Connections { target: Drives; function onDone(id, action, ok, error) { root.results = root.results.concat([[id, action, ok, error]]) } }
    Component.onCompleted: {
        Core.root = root
        Prefs.warm = true
        t.then(1500, () => {
            t.ok("вставленное до запуска — в списке", Drives.list.length === 1 && Drives.list[0].id === "A", Drives.list.map(d => d.id))
        })
        t.then(2500, () => {   // помощник выдал B (новая, не подключена) и C (зашифрованная)
            t.ok("новые — в списке", Drives.list.length === 3, Drives.list.map(d => d.id))
            Prefs.data = { drivesAutomount: false }
        })
        t.then(2500, () => {   // D — уже без «подключать сами»
            Drives.eject(Drives.list.find(d => d.id === "A"))
            Drives.unmount({ id: "busy", label: "Занятый" })
        })
        t.then(1500, () => {
            t.ok("извлечь — ок", root.results.some(r => r[0] === "A" && r[1] === "eject" && r[2]), root.results)
            t.ok("ошибка отключения — с причиной", root.results.some(r => r[0] === "busy" && !r[2] && r[3] === "занято"), root.results)
            t.ok("вспышки об итогах", root.flashes.some(f => f.indexOf("Можно вынимать") === 0) && root.flashes.some(f => f.indexOf("Не отключился: занято") === 0), root.flashes)
            t.ok("занятость снята", Object.keys(Drives.busy).length === 0, Drives.busy)
            t.done()
        })
    }
}
