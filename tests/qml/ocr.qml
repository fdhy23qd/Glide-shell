import QtQuick
import Quickshell
import Quickshell.Io

// Текст с экрана (Ocr.qml, v2.13) с поддельным помощником $GLIDE_OCR_TOOL (ответ берёт из файла $OCR_ANSWER):
// распознано — в буфер (runRaw) и вспышка; отмена — молча; пусто — предупреждение; нет программ — уведомление
// (notify-send — заглушка, журнал проверяет tests/test_qml.py); пока идёт — второй запуск не начинается.
ShellRoot {
    id: root
    QmlCheck { id: t }
    property var raw: []
    property var flashes: []
    property int closes: 0
    function close() { closes++ }
    function flash(icon, text, color) { flashes = flashes.concat([text]) }
    function runRaw(argv, text) { raw = raw.concat([text]) }
    Ocr { id: ocr; shell: root }
    readonly property string answerFile: Quickshell.env("OCR_ANSWER")
    function answer(obj) { ans.setText(JSON.stringify(obj)) }
    FileView { id: ans; path: root.answerFile; printErrors: false }

    Component.onCompleted: {
        answer({ ok: true, text: "Привет,\n  мир", langs: "rus+eng" })
        t.then(300, () => {
            t.ok("запуск", ocr.start() && root.closes === 1)
            t.ok("второй, пока идёт, — нет", !ocr.start())
        })
        t.then(2500, () => {
            t.ok("текст — в буфер", root.raw.join("|") === "Привет,\n  мир", root.raw)
            t.ok("вспышка с началом текста", root.flashes.length === 1 && root.flashes[0].indexOf("Привет, мир") >= 0, root.flashes)
            root.raw = []; root.flashes = []
            answer({ ok: false, cancelled: true })
        })
        t.then(300, () => ocr.start())
        t.then(2500, () => {
            t.ok("отмена — молча", root.raw.length === 0 && root.flashes.length === 0, root.flashes)
            answer({ ok: true, text: "  \n " })
        })
        t.then(300, () => ocr.start())
        t.then(2500, () => {
            t.ok("пусто — предупреждение, не в буфер", root.raw.length === 0 && root.flashes.length === 1, root.flashes)
            root.flashes = []
            answer({ ok: false, missing: ["grim", "tesseract"], install: "sudo pacman -S grim tesseract" })
        })
        t.then(300, () => ocr.start())
        t.then(2500, () => {
            t.ok("нет программ — без вспышки (уведомление)", root.flashes.length === 0, root.flashes)
            t.done()
        })
    }
}
