import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Greetd

// Glide — экран входа для greetd. Запускается внутри своего niri (glide-greeter → niri -c niri.kdl →
// qs -p этой папки): часы и фон как у замка Glide Shell, пользователь, пароль, выбор сеанса, раскладка,
// питание. Разговор с greetd — Quickshell.Services.Greetd: createSession → (authMessage → respond)… →
// readyToLaunch → launch(сеанс) и выход; niri выходит следом, greetd запускает сеанс.
// Проверка без настоящего входа: GLIDE_GREETER_TEST=1 (и tools/fake-greetd.py вместо greetd) — Esc закрывает.
ShellRoot {
    id: g

    readonly property bool test: Quickshell.env("GLIDE_GREETER_TEST") === "1"
    readonly property string cacheDir: Quickshell.env("GLIDE_GREETER_CACHE") || "/var/cache/glide-greeter"

    // ---------- пользователи (/etc/passwd: обычные, с оболочкой входа) ----------
    property var users: []                 // [{name, full, home}]
    FileView {
        path: "/etc/passwd"
        onLoaded: {
            var out = []
            for (var l of text().split("\n")) {
                var f = l.split(":")
                if (f.length < 7) continue
                var uid = +f[2]
                if (uid < 1000 || uid >= 60000 || /(nologin|false)$/.test(f[6])) continue
                out.push({ name: f[0], full: f[4].split(",")[0], home: f[5] })
            }
            g.users = out
            g.pickRemembered()
        }
    }
    property int userIdx: 0
    readonly property var user: users[userIdx] || null
    onUserChanged: Look.home = user ? user.home : ""
    function nextUser(d) { if (users.length > 1) { userIdx = (userIdx + d + users.length) % users.length; resetAuth() } }

    // ---------- сеансы (/usr/share/wayland-sessions) ----------
    property var sessions: []              // [{name, exec, desktop}]
    Process {
        running: true
        command: ["sh", "-c", 'for f in /usr/share/wayland-sessions/*.desktop; do [ -f "$f" ] || continue; '
                  + 'n=$(grep -m1 "^Name=" "$f" | cut -d= -f2-); e=$(grep -m1 "^Exec=" "$f" | cut -d= -f2-); '
                  + 'd=$(grep -m1 "^DesktopNames=" "$f" | cut -d= -f2- | cut -d";" -f1); '
                  + 'printf "%s\\t%s\\t%s\\n" "$n" "$e" "$d"; done']
        stdout: StdioCollector {
            onStreamFinished: {
                var out = []
                for (var l of text.split("\n")) {
                    var f = l.split("\t")
                    if (f.length >= 2 && f[1]) out.push({ name: f[0] || f[1], exec: f[1], desktop: f[2] || "" })
                }
                // niri — первым: это сеанс Glide Shell
                out.sort((a, b) => (b.exec.indexOf("niri") >= 0) - (a.exec.indexOf("niri") >= 0))
                g.sessions = out
                g.pickRemembered()
            }
        }
    }
    property int sessionIdx: 0
    readonly property var session: sessions[sessionIdx] || null
    function nextSession() { if (sessions.length > 1) sessionIdx = (sessionIdx + 1) % sessions.length }

    // ---------- память: кто и в какой сеанс входил последним ----------
    property var memory: ({})
    FileView {
        id: memFile
        path: g.cacheDir + "/memory.json"
        printErrors: false
        onLoaded: { try { g.memory = JSON.parse(text()) } catch (e) { g.memory = {} } g.pickRemembered() }
        onLoadFailed: g.pickRemembered()
    }
    function pickRemembered() {
        var u = users.findIndex(x => x.name === memory.user)
        if (u >= 0) userIdx = u
        var s = sessions.findIndex(x => x.exec === memory.session)
        if (s >= 0) sessionIdx = s
        Look.home = user ? user.home : ""
    }
    function remember() {
        if (test) return
        memFile.setText(JSON.stringify({ user: user ? user.name : "", session: session ? session.exec : "" }))
    }

    // ---------- вход: greetd ----------
    property string error: ""
    property bool busy: false              // ждём greetd
    property bool done: false              // пароль принят — экран уходит, дальше запуск сеанса
    property string pending: ""            // введённое: отдаётся на первый вопрос PAM
    property string prompt: ""             // второй вопрос (код 2FA и т.п.) — поле ждёт ответа на него
    property bool promptEcho: false
    signal failed()

    function submit(text) {
        if (busy || done || !user) return
        if (prompt !== "") {               // ответ на дополнительный вопрос PAM
            busy = true; prompt = ""
            Greetd.respond(text)
            return
        }
        if (!text) return
        error = ""
        busy = true
        pending = text
        // после неудачной попытки сессия у greetd уже закрыта — отменять нечего (лишняя отмена — ошибка)
        if (Greetd.state === GreetdState.ReadyToLaunch) Greetd.cancelSession()
        Greetd.createSession(user.name)
    }
    function resetAuth() {
        if (Greetd.state !== GreetdState.Inactive) Greetd.cancelSession()
        busy = false; prompt = ""; pending = ""; error = ""
    }
    Connections {
        target: Greetd
        function onAuthMessage(message, isError, responseRequired, echoResponse) {
            if (!responseRequired) {       // сообщение PAM (например, «осталось попыток»)
                if (message) g.error = message
                return
            }
            if (g.pending !== "") {         // первый вопрос — пароль, он уже введён
                var p = g.pending
                g.pending = ""
                Greetd.respond(p)
            } else {                        // следующий вопрос — ждём ответа в поле
                g.busy = false
                g.prompt = message || "Код"
                g.promptEcho = echoResponse
            }
        }
        function onAuthFailure(message) {
            g.busy = false; g.pending = ""; g.prompt = ""
            g.error = "Неверный пароль"
            g.failed()
        }
        function onError(message) {
            g.busy = false; g.pending = ""; g.prompt = ""
            g.error = "Ошибка входа: " + message
            g.failed()
        }
        function onReadyToLaunch() {
            g.revealStyle = g.pickStyle()
            g.busy = false
            g.done = true
            g.remember()
            launchTimer.start()            // сначала экран уходит (анимация), потом — сеанс
        }
    }
    // стиль ухода после пароля (Reveal.qml): фон уходит в чёрный, дальше — чёрная консоль и рабочий стол
    property string revealStyle: "rise"
    readonly property int revealMs: ({ rise: 520, iris: 760, curtains: 700, tiles: 900, zoom: 620, island: 820 })[revealStyle] || 520
    function pickStyle() {
        if (Look.unlockStyle !== "random") return Look.unlockStyle
        var pool = ["rise", "iris", "curtains", "tiles", "zoom", "island"]
        return pool[Math.floor(Math.random() * pool.length)]
    }
    Timer {
        id: launchTimer
        interval: Math.max(50, Look.ms(140 + g.revealMs))
        onTriggered: {
            var s = g.session
            var cmd = s ? s.exec.split(/\s+/).filter(x => x) : ["niri-session"]
            // перед сеансом — стереть консоль VT и спрятать курсор (glide-session, ставит greeter/install.sh)
            cmd = ["/usr/local/bin/glide-session"].concat(cmd)
            var env = ["XDG_SESSION_TYPE=wayland"]
            if (s && s.desktop) env.push("XDG_CURRENT_DESKTOP=" + s.desktop, "XDG_SESSION_DESKTOP=" + s.desktop)
            if (g.test) console.log("glide-greeter: запуск " + JSON.stringify(cmd) + " " + JSON.stringify(env))
            Greetd.launch(cmd, env, true)   // Quickshell выходит сам, niri — следом (см. niri.kdl)
        }
    }

    // ---------- часы ----------
    property date now: new Date()
    Timer {
        running: true; repeat: true; interval: 1000; triggeredOnStart: true
        onTriggered: { g.now = new Date(); interval = 60000 - g.now.getSeconds() * 1000 - g.now.getMilliseconds() + 20 }
    }

    // ---------- раскладка (niri этого экрана входа) и Caps Lock ----------
    property var layouts: []
    property int layoutIdx: 0
    Process {
        running: true
        command: ["niri", "msg", "--json", "event-stream"]
        stdout: SplitParser {
            onRead: line => {
                try {
                    var e = JSON.parse(line)
                    if (e.KeyboardLayoutsChanged) {
                        g.layouts = e.KeyboardLayoutsChanged.keyboard_layouts.names
                        g.layoutIdx = e.KeyboardLayoutsChanged.keyboard_layouts.current_idx
                    } else if (e.KeyboardLayoutSwitched) g.layoutIdx = e.KeyboardLayoutSwitched.idx
                } catch (x) {}
            }
        }
    }
    readonly property string layoutShort: {
        var n = layouts[layoutIdx] || ""
        var first = n.split(/[\s(]/)[0]
        var known = { English: "EN", Russian: "RU", Ukrainian: "UA", Belarusian: "BY", German: "DE" }
        return known[first] || first.slice(0, 2).toUpperCase()
    }
    function switchLayout() { Quickshell.execDetached(["niri", "msg", "action", "switch-layout", "next"]) }
    property bool capsLock: false
    Process {   // события Caps Lock нет: читаем светодиод встроенными командами bash, без порождения процессов
        running: true
        command: ["bash", "-c", 'exec 3<> <(:); p=; while :; do s=0; for f in /sys/class/leds/*::capslock/brightness; do '
                  + '[ -r "$f" ] && read -r v < "$f" && [ "$v" != 0 ] && s=1; done; '
                  + '[ "$s" != "$p" ] && { echo "$s"; p=$s; }; read -t 0.4 -u 3; done']
        stdout: SplitParser { onRead: line => g.capsLock = line.trim() === "1" }
    }

    // проверка без клавиатуры: GLIDE_GREETER_AUTOTYPE="неверный,glide" — по очереди вводит ответы раз в 1,5 с
    property var autotype: test ? (Quickshell.env("GLIDE_GREETER_AUTOTYPE") || "").split(",").filter(x => x) : []
    Timer {
        running: g.autotype.length > 0 && !g.done
        interval: 1500; repeat: true
        onTriggered: { if (g.busy) return; var a = g.autotype.slice(); g.submit(a.shift()); g.autotype = a }
    }

    // ---------- питание ----------
    function power(action) {   // suspend | reboot | poweroff — logind разрешает активному сеансу на месте
        if (test) { error = "Проверка: «" + action + "» не выполняется"; return }
        Quickshell.execDetached(["systemctl", action])
    }

    // ---------- окна: по одному на экран, ввод — на первом ----------
    Variants {
        model: Quickshell.screens
        PanelWindow {
            required property var modelData
            screen: modelData
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "glide-greeter"
            WlrLayershell.keyboardFocus: modelData === Quickshell.screens[0] ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            color: "black"   // под уходящим фоном — чёрный, как консоль после выхода
            LoginView { anchors.fill: parent; login: g; primary: modelData === Quickshell.screens[0] }
        }
    }
}
