import QtQuick
import Quickshell.Io

// Process, который собирает stdout и отдаёт его в onDone(text).
Process {
    id: p
    property var argv: []
    signal done(string t)
    command: argv
    stdout: StdioCollector { onStreamFinished: p.done(text) }
}
