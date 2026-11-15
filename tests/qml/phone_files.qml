import QtQuick
import Quickshell
import "plugins/phone" as P

// Файлы телефона через Glide Link (v2.16): FilesView → tools/glide-link.py → поддельный демон (tests/test_qml.py):
// хранилища, папка, скачать файл (открывается через xdg-open — заглушка), вверх, нет разрешения.
ShellRoot {
    QmlCheck { id: t }
    Item {
        width: 400; height: 800
        P.FilesView { id: fv; width: 400; device: ({ id: "p1", backend: "glidelink" }) }
    }
    Component.onCompleted: {
        t.then(2500, () => {
            t.ok("хранилища", fv.entries.length === 1 && fv.entries[0].name === "Внутренняя память" && fv.path === "", fv.entries)
            fv.open(fv.entries[0])
        })
        t.then(2000, () => {
            t.ok("папка открыта", fv.path === "/storage/emulated/0" && fv.entries.map(e => e.name).join() === "DCIM,a.txt", fv.entries)
            fv.open(fv.entries[1])
        })
        t.then(2000, () => {
            t.ok("файл скачан, без ошибки", fv.busy === "" && fv.error === "", [fv.busy, fv.error])
            fv.up()
        })
        t.then(2000, () => {
            t.ok("вверх — снова хранилища", fv.path === "" && fv.entries.length === 1, fv.path)
            fv.open({ name: "Закрытая", path: "/storage/locked", dir: true })
        })
        t.then(2000, () => {
            t.ok("нет разрешения — понятная подсказка", fv.error.indexOf("Glide Link") >= 0, fv.error)
            t.done()
        })
    }
}
