import QtQuick
import Quickshell.Io

// Команды, которые пишут файлы (настройки niri, клавиши, автозапуск), — строго по одной, по очереди.
// Перезапуск «running = false; running = true» убивал прежнюю посреди записи: быстрые правки терялись,
// а убитая между записью и проверкой (niri validate) не откатывала файл. add(argv) — в очередь,
// finished(out) — вывод каждой команды. Занятость — свой флаг busy: running становится true не сразу, и
// несколько add подряд затирали бы command друг другу. Следующая — когда у прежней и процесс вышел, и вывод дочитан.
Process {
    id: q
    property var jobs: []
    property bool busy: false
    property bool exitedOne: false
    property bool readOne: false
    signal finished(string out)
    function add(argv) { jobs = jobs.concat([argv]); next() }
    function next() {
        if (busy || !jobs.length) return
        busy = true
        exitedOne = readOne = false
        command = jobs[0]
        jobs = jobs.slice(1)
        running = true
    }
    function step() { if (exitedOne && readOne) { busy = false; Qt.callLater(next) } }
    stdout: StdioCollector { onStreamFinished: { q.readOne = true; q.finished(text); q.step() } }
    onExited: { exitedOne = true; step() }
}
