import QtQuick
import Quickshell

// Prefs.set подряд (v2.9): все записи доходят до config.json по порядку — раньше вторая затирала первой command,
// пока running ещё не стал true, и правка терялась. Файл проверяет tests/test_qml.py.
ShellRoot {
    QmlCheck { id: t }
    property int saves: 0
    Connections { target: Prefs; function onSaved() { saves++ } }
    Component.onCompleted: {
        Prefs.set("lockBackground", "image")
        Prefs.set("lockDim", 0.25)
        Prefs.set("lockBlur", 64)
        Prefs.set("lockBlur", 0)
        Prefs.set("lockImage", "~/x")
        t.then(4000, () => { t.ok("saved пришёл", saves >= 1, saves); t.done() })
    }
}
