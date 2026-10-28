import QtQuick
import Quickshell
import Quickshell.Io

// Текст с экрана (IPC panel ocr, кнопка в плагине «Скриншот»): tools/glide-ocr.py — выделить область, снять (grim),
// распознать (tesseract); текст — в буфер и вспышкой в острове. Нет программ — уведомление, что поставить.
QtObject {
    id: ocr
    required property var shell
    readonly property string tool: Quickshell.env("GLIDE_OCR_TOOL") || Quickshell.shellDir + "/tools/glide-ocr.py"
    readonly property bool busy: proc.running
    signal done(var result)           // для сценария tests/qml/ocr.qml

    property Process proc: Process {
        command: ["setpriv", "--pdeathsig", "TERM", "python3", "-I", ocr.tool]
        stdout: StdioCollector { onStreamFinished: ocr.got(text) }
    }
    function start() {
        if (proc.running) return false
        shell.close()                 // панель не должна попасть в выделение
        proc.running = true
        return true
    }
    function got(out) {
        var r
        try { r = JSON.parse(out) } catch (e) { r = { ok: false, error: "glide-ocr.py: " + String(out).trim().slice(0, 200) } }
        done(r)
        if (r.cancelled) return
        if (r.missing && r.missing.length) {
            Quickshell.execDetached(["notify-send", "-a", "Glide Shell", "-i", "dialog-warning", "--",
                                     Tr.t("Текст с экрана: нужны программы"),
                                     Tr.t("Не хватает: ") + r.missing.join(", ") + "\n" + (r.install || "")])
            return
        }
        if (!r.ok) { shell.flash(String.fromCodePoint(0xF0026), Tr.t("Не распознать: ") + String(r.error || "?").slice(0, 120), Theme.error); return }
        var text = String(r.text || "")
        if (!text.trim()) { shell.flash(String.fromCodePoint(0xF0026), Tr.t("Текста не нашлось"), Theme.warning); return }
        shell.runRaw(["sh", "-c", 'printf %s "$QP_TEXT" | wl-copy'], text, "")
        var one = text.replace(/\s+/g, " ").trim()
        shell.flash(String.fromCodePoint(0xF018F), Tr.t("Текст скопирован: ") + (one.length > 40 ? one.slice(0, 40) + "…" : one), Theme.success)
    }
}
