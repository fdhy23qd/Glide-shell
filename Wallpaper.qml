import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.UPower

// Обои Glide Shell (Prefs.wallMode === "image"): картинка, GIF или видео — файл или папка (Prefs.wallPath),
// смена по кругу раз в Prefs.wallEvery минут, плавная смена кадра; цвета темы — из картинки (Prefs.wallTheme).
// GIF и видео один раз перекодируются под экран (tools/glide-walls.py prepare: H.264, Prefs.wallFps, без звука)
// и играют по кругу в ОТДЕЛЬНОМ процессе (wallpaper-player/: без аппаратного декодера видео — десятки процентов
// ядра, и в одном процессе с баром интерфейс переставал отвечать); здесь — только неподвижный кадр под ним.
// Видео стоит, когда его не видно: окна закрыли монитор, экран заперт, от батареи (настройка).
// Пока обои свои, HTML-сцена webpaper остановлена; в режиме «сцена» — запущена с выбранной Prefs.wallScene.
Scope {
    id: wp
    property bool locked: false                     // экран заперт — анимация стоит (задаёт shell.qml)
    readonly property bool on: Prefs.wallMode === "image"
    readonly property string home: Quickshell.env("HOME")
    readonly property string src: Prefs.wallPath.replace(/^~(?=\/|$)/, home)
    readonly property string stateFile: (Quickshell.env("XDG_STATE_HOME") || home + "/.local/state") + "/glide-shell/wallpaper"
    readonly property string tool: Quickshell.shellDir + "/tools/glide-walls.py"

    property var files: []          // [{path, thumb, name, kind}] — из папки (или один файл)
    property string current: ""     // что на экране
    readonly property var entry: files.find(f => f.path === current) || null
    readonly property string kind: /\.gif$/i.test(current) ? "gif" : /\.(mp4|webm|mkv|mov|m4v)$/i.test(current) ? "video" : "image"
    readonly property bool animated: kind !== "image"
    readonly property bool onBattery: UPower.onBattery

    // ---- список: при включении, смене пути и по запросу (настройки) ----
    function rescan() { if (on) { lister.running = false; lister.running = true } }
    onSrcChanged: rescan()
    onOnChanged: { rescan(); scene() }
    Process {
        id: lister
        command: ["python3", "-I", wp.tool, "list", wp.src]
        stdout: StdioCollector {
            onStreamFinished: {
                try { wp.files = JSON.parse(text) } catch (e) { wp.files = [] }
                // прежние обои (из state) — если они ещё в списке; иначе — первые
                if (!wp.files.some(f => f.path === wp.current)) wp.current = wp.files.length ? wp.files[0].path : ""
                // при старте обои пришли из state раньше, чем всё было готово, — видео ещё не готовили
                if (wp.animated && wp.video === "" && !prep.running) wp.prepareAnim()
            }
        }
    }
    FileView {   // что было на экране — после перезапуска то же
        path: wp.stateFile
        printErrors: false
        onLoaded: if (!wp.current) wp.current = text().trim()
    }
    function show(path) { current = path }
    function next() {
        if (files.length < 2) return
        var i = files.findIndex(f => f.path === current)
        var j = i
        while (j === i) j = Math.floor(Math.random() * files.length)   // случайные, но не те же
        current = files[j].path
    }
    Timer {
        running: wp.on && Prefs.wallEvery > 0 && wp.files.length > 1
        interval: Math.max(1, Prefs.wallEvery) * 60000
        repeat: true
        onTriggered: wp.next()
    }
    onCurrentChanged: {
        if (!current) return
        saver.command = ["sh", "-c", 'mkdir -p "${1%/*}" && printf %s "$2" > "$1"', "sh", stateFile, current]
        saver.running = true
        if (on && Prefs.wallTheme) takeColors()
        prepareAnim()
    }
    Process { id: saver }

    // ---- GIF и видео: готовое к показу видео (перекодированное или исходное) ----
    property string video: ""       // file:// готового видео для current; пусто — ещё готовится (или картинка)
    readonly property int screenW: Math.max.apply(null, Quickshell.screens.map(s => s.width).concat([1]))
    readonly property int screenH: Math.max.apply(null, Quickshell.screens.map(s => s.height).concat([1]))
    function prepareAnim() {
        video = ""
        if (!on || !animated) return
        prep.running = false
        prep.file = current
        prep.command = ["python3", "-I", tool, "prepare", current, String(screenW), String(screenH), String(Prefs.wallFps)]
        prep.running = true
    }
    Connections { target: Prefs; function onWallFpsChanged() { wp.prepareAnim() } }
    Process {
        id: prep
        property string file: ""
        stdout: StdioCollector {
            onStreamFinished: {
                if (prep.file !== wp.current) return   // пока готовили, обои сменились
                var r
                try { r = JSON.parse(text) } catch (e) { return }
                if (r.file) wp.video = "file://" + r.file
                else console.warn("glide-shell: обои " + prep.file + " не удалось подготовить (ffmpeg)")
            }
        }
    }

    // ---- цвета темы: команда — явно при запуске (привязка к current пересчиталась бы уже после старта) ----
    function takeColors() {
        pal.running = false
        pal.file = current
        pal.command = ["python3", "-I", tool, "palette", current]
        pal.running = true
    }
    Process {
        id: pal
        property string file: ""
        stdout: StdioCollector {
            onStreamFinished: {
                var r
                try { r = JSON.parse(text) } catch (e) { return }
                if (pal.file !== wp.current) return   // пока считали, обои уже сменились
                console.log("glide-shell: обои " + pal.file.split("/").pop() + " → акцент " + r.accent + ", тон " + r.tone)
                if (r.accent && r.accent !== String(Prefs.accent).slice(0, 7)) Prefs.set("accent", r.accent)
                if (r.tone && r.tone !== Prefs.themeTone) Prefs.set("themeTone", r.tone)
            }
        }
    }
    Connections {   // включили «цвета из обоев» — сразу взять из текущих
        target: Prefs
        function onWallThemeChanged() { if (wp.on && Prefs.wallTheme && wp.current) wp.takeColors() }
    }

    // ---- видео (GIF и видео): проигрыватель — отдельный процесс; ему — что играть и где пауза ----
    // пауза: окна закрывают монитор на 90 % и больше, экран заперт, от батареи (настройка)
    readonly property var live: {
        var m = {}
        for (var s of Quickshell.screens)
            m[s.name] = !locked && !(onBattery && Prefs.wallBatteryPause) && Niri.coveredShare(s.name, s.width, s.height) < 0.9
        return m
    }
    readonly property bool playing: on && animated && video !== ""
    readonly property string playerState: JSON.stringify({ video: playing ? video : "", fit: Prefs.wallFit, live: live,
                                                           still: entry ? "file://" + entry.thumb : "" })
    onPlayerStateChanged: stateWrite.restart()
    Timer { id: stateWrite; interval: 150; onTriggered: playerFile.setText(wp.playerState) }
    FileView { id: playerFile; path: Quickshell.env("XDG_RUNTIME_DIR") + "/glide-shell-wallpaper.json"; printErrors: false }
    Process {
        id: player
        running: wp.playing
        // свой процесс, пониже приоритетом; умирает вместе с оболочкой
        command: ["setpriv", "--pdeathsig", "TERM", "nice", "-n", "5", "qs", "-p", Quickshell.shellDir + "/wallpaper-player"]
        onExited: if (wp.playing) playerRestart.restart()   // упал — поднять снова (не чаще раза в 5 с)
    }
    Timer { id: playerRestart; interval: 5000; onTriggered: if (wp.playing) player.running = true }

    // ---- HTML-сцена webpaper: остановлена, пока обои свои; сцена — выбранная (drop-in службы) или как в службе ----
    function scene() {
        Quickshell.execDetached(["sh", Quickshell.shellDir + "/tools/glide-scene.sh", on ? "stop" : "start", Prefs.wallScene])
    }
    Connections { target: Prefs; function onWallSceneChanged() { if (!wp.on) wp.scene() } }
    Component.onCompleted: { if (on) rescan(); scene() }

    // ---- окна: по одному на экран, слой Background — под всем ----
    Variants {
        model: wp.on ? Quickshell.screens : []
        PanelWindow {
            id: win
            required property var modelData
            screen: modelData
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Background
            WlrLayershell.namespace: "glide-wallpaper"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            color: Theme.background
            mask: Region {}

            readonly property int fill: Prefs.wallFit === "fit" ? Image.PreserveAspectFit : Image.PreserveAspectCrop

            // картинки — две по очереди: новая грузится в нижнюю и проявляется поверх старой.
            // У GIF и видео здесь их кадр (миниатюра) — виден, пока видео готовится и грузится
            readonly property string still: !wp.current ? "" : wp.kind === "image" ? "file://" + wp.current
                                             : wp.entry ? "file://" + wp.entry.thumb : ""
            property bool flip: false
            onStillChanged: {
                var back = flip ? a : b
                if (back.source.toString() !== still) back.source = still
            }
            Component.onCompleted: { a.source = still; a.opacity = 1 }
            function ready(img) {
                if (img.source.toString() !== still || img.status !== Image.Ready) return
                var front = flip ? b : a
                if (img === front) return
                img.z = 1; front.z = 0
                img.opacity = 0
                fade.target = img
                fade.restart()
                flip = !flip
            }
            NumberAnimation { id: fade; property: "opacity"; from: 0; to: 1; duration: Prefs.ms(700); easing.type: Easing.InOutQuad }
            Image {
                id: a
                anchors.fill: parent
                opacity: 0
                fillMode: win.fill
                sourceSize.width: win.width; sourceSize.height: win.height   // декодировать под экран, не 4K
                asynchronous: true
                cache: false
                onStatusChanged: win.ready(a)
            }
            Image {
                id: b
                anchors.fill: parent
                opacity: 0
                fillMode: win.fill
                sourceSize.width: win.width; sourceSize.height: win.height
                asynchronous: true
                cache: false
                onStatusChanged: win.ready(b)
            }
        }
    }
}
