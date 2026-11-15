import QtQuick
import Quickshell
import "plugins/phone" as P

// SMS Glide Link (v2.16): окно SmsView через настоящий tools/glide-link.py и поддельный демон (tests/test_qml.py
// поднимает его на $XDG_RUNTIME_DIR/glide-link.sock): диалоги, переписка, отправка, перечитывание по sms_rev.
ShellRoot {
    QmlCheck { id: t }
    property var dev: ({ id: "p1", name: "Pixel", backend: "glidelink", sms_rev: 0 })
    Item {
        width: 400; height: 800
        P.SmsView { id: sv; width: 400; device: dev }
    }
    Component.onCompleted: {
        t.then(2500, () => {
            t.ok("диалоги пришли", sv.conversations.length === 2 && sv.error === "", [sv.conversations.length, sv.error])
            t.ok("контакт и непрочитанное", sv.conversations[0].contact === "Мама" && sv.conversations[0].read === false, sv.conversations[0])
            sv.open(sv.conversations[0])
        })
        t.then(2000, () => {
            t.ok("переписка", sv.mode === "thread" && sv.messages.length === 2 && sv.messages[1].outgoing === true, sv.messages)
            sv.send(sv.thread.address, "Уже еду", null)
        })
        t.then(2000, () => {
            t.ok("отправлено и добавлено в переписку", !sv.sending && sv.error === "" && sv.messages.length === 3
                 && sv.messages[2].body === "Уже еду", [sv.error, sv.messages.length])
            dev = Object.assign({}, dev, { sms_rev: 1 })   // пришло новое SMS — переписка перечитывается
        })
        t.then(2000, () => {
            t.ok("по sms_rev переписка перечитана", sv.messages.length === 2, sv.messages.length)
            t.done()
        })
    }
}
