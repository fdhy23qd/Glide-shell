import QtQuick
import Quickshell
import "plugins/phone" as P

// Плагин «Телефон» (v2.16) с телефоном Glide Link: команды ПК для кнопок телефона — список и добавление через
// поддельный демон (tests/test_qml.py); кнопки Glide Link видны, кнопки KDE Connect (SFTP) — нет.
ShellRoot {
    QmlCheck { id: t }
    Item {
        width: 420; height: 1400
        P.Phone { id: ph; width: 420 }
    }
    Component.onCompleted: {
        Phones.linkDevices = [{ id: "p1", name: "Pixel", type: "phone", backend: "glidelink", reachable: true,
                                plugins: ["runcommand", "files", "sms", "share"], streams: {}, battery: 50 }]
        t.then(2500, () => {
            t.ok("главный — телефон Glide Link", ph.link && ph.d.id === "p1", ph.d)
            t.ok("команды загружены", ph.commands.length === 1 && ph.commands[0].name === "Заблокировать", ph.commands)
            ph.addCommand("  Сон ", " systemctl suspend ")
        })
        t.then(2000, () => {
            t.ok("после добавления список перечитан", ph.commands.length === 2, ph.commands)
            ph.addCommand("", "x")   // пустое название — ничего не отправляется
            t.done()
        })
    }
}
