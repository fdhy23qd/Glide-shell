pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire

// Запись экрана через wf-recorder (wlr-screencopy — niri его умеет): весь экран или область (slurp),
// без звука, со звуком системы (монитор выхода) или с микрофоном. Видео — в ~/Видео/Записи экрана.
// Остров показывает запись строкой с таймером и кнопкой «стоп». Остановка — SIGINT: wf-recorder
// дописывает файл; если оболочка упадёт, сигнал придёт сам (setpriv --pdeathsig INT).
Singleton {
    id: rec
    property bool hasRecorder: false
    property bool hasSlurp: false
    readonly property bool recording: proc.running
    readonly property bool selecting: slurp.running   // идёт выбор области
    property double startedAt: 0
    property int elapsed: 0
    property string file: ""
    property string error: ""
    signal finished(string file, bool ok)

    Process {   // что установлено — один раз при запуске и при каждом открытии плагина
        id: probe
        running: true
        command: ["sh", "-c", "command -v wf-recorder >/dev/null && echo rec; command -v slurp >/dev/null && echo slurp; true"]
        stdout: StdioCollector {
            onStreamFinished: { rec.hasRecorder = text.indexOf("rec") >= 0; rec.hasSlurp = text.indexOf("slurp") >= 0 }
        }
    }
    function check() { if (!probe.running) probe.running = true }

    readonly property string dir: (Quickshell.env("XDG_VIDEOS_DIR") || Quickshell.env("HOME") + "/Видео") + "/Записи экрана"
    function output() {   // выбранный монитор (Prefs.recOutput, если подключён) или тот, где фокус:
        // без -o wf-recorder при нескольких мониторах спрашивает в терминале
        if (Prefs.recOutput && Quickshell.screens.some(sc => sc.name === Prefs.recOutput)) return Prefs.recOutput
        for (var w of Niri.workspaces) if (w.is_focused) return w.output
        return ""
    }

    // audio: "" | "system" | "mic"; area: true — сначала выбрать область
    property var pending: null
    function start(audio, area) {
        if (recording || !hasRecorder) return
        error = ""
        pending = { audio: audio || "" }
        // выбор области — когда панель уже закрылась: её полноэкранное окно (затемнение, захват
        // клавиатуры) ещё лежит поверх и перехватывает мышь у slurp
        if (area && hasSlurp) slurpDelay.restart()
        else launch("")
    }
    Timer { id: slurpDelay; interval: 400; onTriggered: slurp.running = true }
    Process {
        id: slurp
        // stdin — /dev/null: если stdin не терминал, slurp ждёт из него готовые прямоугольники (до конца ввода),
        // а Process держит его открытым — выбор так и не появлялся
        command: ["setpriv", "--pdeathsig", "TERM", "sh", "-c", "exec slurp < /dev/null"]
        stdout: StdioCollector {
            onStreamFinished: { var g = text.trim(); if (g) rec.launch(g); else rec.pending = null }   // Esc — отмена
        }
        stderr: StdioCollector { onStreamFinished: if (text.trim()) console.warn("glide-shell slurp:", text.trim()) }
    }
    function launch(geometry) {
        var args = []
        var out = output()
        if (geometry) args.push("-g", geometry)
        else if (out) args.push("-o", out)
        var a = pending ? pending.audio : ""
        if (a === "system" && Pipewire.defaultAudioSink) args.push("--audio=" + Pipewire.defaultAudioSink.name + ".monitor")
        else if (a === "mic" && Pipewire.defaultAudioSource) args.push("--audio=" + Pipewire.defaultAudioSource.name)
        pending = null
        file = dir + "/Запись " + Qt.formatDateTime(new Date(), "yyyy-MM-dd HH-mm-ss") + ".mp4"
        proc.command = ["setpriv", "--pdeathsig", "INT", "sh", "-c",
                        'mkdir -p "${1%/*}" && f=$1 && shift && exec wf-recorder -y -f "$f" "$@"', "sh", file].concat(args)
        startedAt = Date.now()
        elapsed = 0
        proc.running = true
    }
    function stop() { if (recording) proc.signal(2) }   // SIGINT — wf-recorder закрывает файл как надо
    function toggle(audio) { if (recording) stop(); else start(audio, false) }

    Process {
        id: proc
        stderr: StdioCollector { id: err }
        onExited: (code, status) => {
            var ok = Date.now() - rec.startedAt > 1000 && code === 0   // по SIGINT wf-recorder выходит с 0
            if (!ok) rec.error = (err.text.trim().split("\n").pop() || Tr.t("wf-recorder завершился с кодом ") + code)
            rec.finished(rec.file, ok)
        }
    }
    Timer {
        running: rec.recording
        interval: 1000; repeat: true
        onTriggered: rec.elapsed = Math.floor((Date.now() - rec.startedAt) / 1000)
    }
    function fmt(s) { return Math.floor(s / 60) + ":" + ("0" + (s % 60)).slice(-2) }
}
