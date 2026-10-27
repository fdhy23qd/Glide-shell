import QtQuick

// Помощник сценариев tests/qml: ok() печатает строку, которую разбирает tests/test_qml.py; done() — итог и выход.
// Шаги — по очереди с паузами (then): многое в оболочке асинхронно (процессы, файлы).
QtObject {
    id: c
    property int fails: 0
    property var queue: []
    function ok(name, cond, detail) {
        console.warn("QMLTEST|" + (cond ? "PASS" : "FAIL") + "|" + name + "|" + (detail === undefined ? "" : JSON.stringify(detail)))
        if (!cond) fails++
    }
    function done() { console.warn("QMLTEST|DONE|" + fails + "|"); Qt.quit() }
    // then(ms, fn): выполнить fn через ms после предыдущего шага
    function then(ms, fn) { queue = queue.concat([{ ms: ms, fn: fn }]); if (queue.length === 1) tick.start() }
    property Timer tick: Timer {
        interval: c.queue.length ? c.queue[0].ms : 0
        onTriggered: {
            var s = c.queue[0]
            try { s.fn() } catch (e) { c.ok("исключение в шаге", false, String(e)) }
            c.queue = c.queue.slice(1)
            if (c.queue.length) { interval = c.queue[0].ms; start() }
        }
    }
}
