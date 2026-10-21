import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Pam

// Экран блокировки: ext-session-lock (WlSessionLock) и проверка пароля через PAM (/etc/pam.d/login —
// тот же стек, что у входа в систему, с faillock). Разблокирует только PamResult.Success.
//
// Режимы (mode):
//   lock    — настоящая блокировка;
//   test    — то же, но снимается сама через testSeconds: страховка на время проверки;
//   preview — тот же экран в обычном окне поверх всего, без блокировки: проверить пароль и вид.
//
// Защита от сбоев: пока заперто, режим лежит в $XDG_RUNTIME_DIR/glide-shell-lock. Если оболочка
// упадёт, niri оставит сессию запертой (пустой экран), а перезапущенная оболочка (из TTY:
// `qs -c glide-shell`) запрёт её снова — niri подменяет «мёртвый» замок новым — и снять её можно паролем.
//
// logind: `loginctl lock-session` (сигнал Lock) запирает экран; Unlock не слушаем — снять можно только
// паролем. Перед сном держим delay-блокировку сна, пока экран не заперт (Prefs.lockBeforeSleep).
Scope {
    id: locker
    required property var panel

    property string mode: ""
    readonly property bool locked: mode === "lock" || mode === "test"
    readonly property bool secure: sessionLock.secure
    readonly property string user: Quickshell.env("USER") || ""

    // ---- проверка пароля ----
    readonly property bool busy: pam.active
    property string error: ""          // текст под полем пароля
    property string pamInfo: ""        // сообщение PAM без запроса ввода (faillock и т. п.)
    property string buffer: ""         // пароль — только на время одной проверки
    property int responses: 0
    signal failed()                    // поле пароля трясётся и очищается

    // instant — без затемнения: перед сном, после падения, когда экран уже погашен
    function start(m, instant) {
        if (m !== "lock" && m !== "test" && m !== "preview") return
        if (unlocking) cancelUnlock()        // новый запрос во время ухода экрана — остаёмся запертыми
        if (mode === "lock") { if (instant && entering) lockNow(); return }
        if (locked && m !== "lock") return   // тест можно усилить до настоящего замка, ослабить замок — нет
        error = ""
        if (m === "test") testLeft = testSeconds
        var wasLocked = locked
        mode = m
        if (locked) {
            stateFile.setText(m + "\n")
            panel.close()
            if (wasLocked || instant || Prefs.anim <= 0) lockNow()
            else { entering = true; veilIn.restart(); enterTimer.restart() }   // экран темнеет, затем замок
        }
    }
    function lockNow() {
        enterTimer.stop()
        sessionLock.locked = true            // заслонка (entering) живёт, пока замок не подтверждён
    }

    // единственные пути к разблокировке: успешный PAM (finish → finishUnlock) и истёкший тестовый таймер
    function release() {
        pam.abort()
        enterTimer.stop()
        unlockTimer.stop()
        entering = false
        unlocking = false
        buffer = ""
        error = ""
        mode = ""
        sessionLock.locked = false
        stateFile.setText("")
    }

    // ---- переходы ----
    // Пока экран заперт, niri рисует только замок, поэтому разблокировка в два шага: содержимое замка
    // уходит (unlocking, LockView), затем замок снимается и над рабочим столом растворяется заслонка
    // того же цвета (revealing) — её окно создаётся заранее, ещё под замком, чтобы не мелькнул кадр.
    property bool entering: false        // заслонка темнеет перед замком
    property bool unlocking: false       // пароль принят, содержимое замка уходит
    property bool revealing: false       // замок снят, заслонка растворяется
    property bool previewFade: false     // в предпросмотре растворяется само его окно
    property real veil: 0                // непрозрачность заслонки
    readonly property bool veilOn: entering || ((unlocking || revealing) && !previewFade)

    // стиль ухода (Reveal.qml): выбирается при каждой разблокировке — «случайный» каждый раз новый
    readonly property var unlockStyles: ["rise", "iris", "curtains", "tiles", "zoom", "island"]
    property string revealStyle: "rise"
    readonly property int revealMs: ({ rise: 520, iris: 760, curtains: 700, tiles: 900, zoom: 620, island: 820 })[revealStyle] || 520
    function pickStyle() {
        if (Prefs.unlockStyle !== "random") return Prefs.unlockStyle
        var pool = unlockStyles.filter(x => x !== revealStyle)
        return pool[Math.floor(Math.random() * pool.length)]
    }
    function beginUnlock() {
        if (Prefs.anim <= 0) { finishUnlock(); return }
        revealStyle = pickStyle()
        previewFade = mode === "preview"
        veilOut.stop()
        veil = 1
        unlocking = true
        unlockTimer.restart()
    }
    function cancelUnlock() {
        unlockTimer.stop()
        unlocking = false
        previewFade = false
    }
    property bool finishing: false       // замок снимается после ухода — LockView не должен «возвращать» экран
    function finishUnlock() {
        var wasPreview = mode === "preview"
        finishing = true
        release()
        finishing = false
        if (Prefs.anim > 0) { revealing = true; veilOut.restart() }
        if (wasPreview) panel.flash("✓", Tr.t("Пароль принят — блокировка снимется так же"), Theme.success)
    }
    Timer {
        id: unlockTimer
        interval: Prefs.ms(380)
        // во время ухода пришёл сон — замок остаётся
        onTriggered: if (locker.unlocking && !locker.sleeping) locker.finishUnlock(); else locker.cancelUnlock()
    }
    Timer { id: enterTimer; interval: Prefs.ms(240) + 30; onTriggered: locker.lockNow() }
    NumberAnimation { id: veilIn; target: locker; property: "veil"; from: 0; to: 1; duration: Prefs.ms(240); easing.type: Easing.OutCubic }
    NumberAnimation {
        id: veilOut
        target: locker; property: "veil"; from: 1; to: 0
        duration: Prefs.ms(locker.revealMs); easing.type: locker.revealStyle === "rise" ? Easing.OutCubic : Easing.InOutCubic
        onStopped: { locker.revealing = false; locker.previewFade = false }
    }
    // страховка: заслонка не должна остаться на экране ни при каком раскладе
    Timer { running: locker.revealing; interval: 2000; onTriggered: { locker.revealing = false; locker.previewFade = false } }
    Timer { running: locker.entering && sessionLock.locked; interval: 2000; onTriggered: locker.entering = false }

    LazyLoader {
        active: locker.veilOn
        PanelWindow {
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            WlrLayershell.namespace: "glide-lock-veil"
            color: "transparent"
            mask: Region {}   // клики проходят сквозь
            // фигурное раскрытие рабочего стола (Reveal): заслонка — тот же фон, что у замка
            LockBackdrop { id: veilBg; anchors.fill: parent }
            Reveal {
                anchors.fill: parent
                cover: veilBg
                progress: 1 - locker.veil
                style: locker.revealStyle
                islandRect: locker.islandRect(width)
            }
        }
    }

    // где остров (для стиля «в остров»): по центру сверху, ширина — как у часов острова
    function islandRect(w) {
        var iw = panel && panel.clockW ? panel.clockW : 220
        var top = panel && panel.islandTop !== undefined ? panel.islandTop : 6
        return Qt.rect(w / 2 - iw / 2, top, iw, 32)
    }
    function closePreview() { if (mode === "preview") release() }   // Esc — только в предпросмотре

    function submit(text) {
        if (!mode || pam.active || unlocking || !text) return
        buffer = text
        responses = 0
        pamInfo = ""
        error = ""
        if (!pam.start()) {
            buffer = ""
            error = Tr.t("Не удалось запустить проверку пароля")
            failed()
            return
        }
        pamTimeout.restart()
    }

    function finish(ok, msg) {
        pamTimeout.stop()
        buffer = ""
        if (!mode || unlocking) return
        if (ok) { beginUnlock(); return }
        error = translate(pamInfo) || msg
        pamInfo = ""
        failed()
    }

    // сообщения pam_faillock приходят по-английски
    function translate(m) {
        if (!m) return ""
        if (/locked due to \d+ failed/i.test(m)) {
            var left = /(\d+) minutes? left/i.exec(m)
            return Tr.t("Слишком много неверных попыток — вход закрыт") + (left ? Tr.t(" ещё на ") + left[1] + Tr.t(" мин") : "")
        }
        return m
    }

    PamContext {
        id: pam
        config: "login"
        configDirectory: "/etc/pam.d"
        onMessageChanged: if (message && !responseRequired) locker.pamInfo = message
        onResponseRequiredChanged: {
            if (!responseRequired) return
            // обычно спрашивают один раз; лишние запросы (неожиданный модуль) не крутим бесконечно
            if (locker.buffer && locker.responses++ < 3) respond(locker.buffer)
            else abort()
        }
        onCompleted: result => locker.finish(result === PamResult.Success,
            result === PamResult.Failed ? Tr.t("Неверный пароль")
            : result === PamResult.MaxTries ? Tr.t("Слишком много попыток") : Tr.t("Ошибка проверки пароля"))
        onError: err => locker.finish(false, Tr.t("Ошибка PAM: ") + PamError.toString(err))
    }
    Timer {   // PAM завис (сеть, устройство) — не держим поле занятым вечно
        id: pamTimeout
        interval: 20000
        onTriggered: { pam.abort(); locker.finish(false, Tr.t("Проверка пароля не ответила — попробуйте ещё раз")) }
    }

    // ---- тестовая блокировка: снимается сама ----
    property int testSeconds: 60
    property int testLeft: 0
    Timer {
        running: locker.mode === "test"
        interval: 1000
        repeat: true
        onTriggered: if (--locker.testLeft <= 0 && !locker.unlocking) locker.beginUnlock()
    }

    // ---- часы (общие для всех экранов) ----
    property date now: new Date()
    Timer {
        id: lockClock
        running: locker.mode !== ""
        repeat: true
        interval: 1000
        triggeredOnStart: true
        onTriggered: {
            locker.now = new Date()
            interval = 60000 - locker.now.getSeconds() * 1000 - locker.now.getMilliseconds() + 20
        }
    }

    // ---- замок ----
    WlSessionLock {
        id: sessionLock
        // композитор отказал (например, экран уже запер DMS) — не делаем вид, что заперто
        onLockedChanged: if (!locked && locker.locked) {
            console.warn("glide-shell: блокировку не удалось поставить или её сняли извне")
            locker.entering = false
            locker.mode = ""
            stateFile.setText("")
        }
        WlSessionLockSurface {
            color: Theme.background
            LockView { anchors.fill: parent; lock: locker }
        }
    }

    // предпросмотр: тот же экран обычным окном, Esc закрывает; создаётся только на время показа
    LazyLoader {
        active: locker.mode === "preview" || locker.previewFade
        PanelWindow {
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: locker.mode ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            WlrLayershell.namespace: "glide-lock-preview"
            color: "transparent"
            LockView { anchors.fill: parent; lock: locker; backdrop: locker.mode ? 1 : locker.veil }
        }
    }

    // ---- состояние на случай падения/перезапуска ----
    property bool restored: false
    FileView {
        id: stateFile
        path: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/glide-shell-lock"
        printErrors: false
        onLoaded: {
            if (locker.restored) return
            locker.restored = true
            var m = text().trim()
            if (m === "lock" || m === "test") locker.start(m, true)
        }
        onLoadFailed: locker.restored = true
    }

    // ---- logind ----
    property string sessionPath: ""     // /org/freedesktop/login1/session/_33
    property bool sleeping: false       // между PrepareForSleep(true) и (false)
    Process {
        running: true
        command: ["busctl", "--system", "call", "org.freedesktop.login1", "/org/freedesktop/login1",
                  "org.freedesktop.login1.Manager", "GetSession", "s", "auto"]
        stdout: StdioCollector {
            onStreamFinished: { var m = /"([^"]+)"/.exec(text); if (m) locker.sessionPath = m[1] }
        }
    }
    // один постоянный процесс; строки вида «<путь>: <интерфейс>.<сигнал> (<аргументы>)»
    Process {
        id: logindWatch
        running: locker.sessionPath !== ""
        command: ["setpriv", "--pdeathsig", "TERM", "gdbus", "monitor", "--system", "--dest", "org.freedesktop.login1"]
        stdout: SplitParser { onRead: line => locker.logindEvent(line) }
        onExited: logindRestart.restart()
    }
    Timer { id: logindRestart; interval: 3000; onTriggered: logindWatch.running = true }
    function logindEvent(line) {
        var i = line.indexOf(": ")
        if (i < 0) return
        var path = line.slice(0, i), sig = line.slice(i + 2)
        if (path === sessionPath && sig.indexOf("org.freedesktop.login1.Session.Lock ") === 0)
            start("lock")
        else if (path === "/org/freedesktop/login1" && sig.indexOf("org.freedesktop.login1.Manager.PrepareForSleep ") === 0)
            sleeping = sig.indexOf("(true") >= 0
    }
    // таймеры Qt идут по монотонным часам, а во сне они стоят: после пробуждения часы ждали бы
    // «конца минуты», отсчитанной до сна, — обновляем сразу (остров и погода — через resumed)
    signal resumed()
    onSleepingChanged: {
        if (sleeping && (Prefs.lockBeforeSleep || (unlocking && locked))) start("lock", true)
        if (!sleeping) {
            if (lockClock.running) { lockClock.interval = 1000; lockClock.restart(); locker.now = new Date() }
            resumed()
        }
    }
    // logind ждёт с уходом в сон (до InhibitDelayMaxSec, 5 с), пока жив этот процесс; отпускаем,
    // как только композитор подтвердил, что все экраны закрыты замком
    Process {
        running: Prefs.lockBeforeSleep && !(locker.sleeping && locker.secure)
        command: ["setpriv", "--pdeathsig", "TERM", "systemd-inhibit", "--what=sleep", "--mode=delay",
                  "--who=Glide Shell", Tr.t("--why=Заблокировать экран перед сном"),
                  "setpriv", "--pdeathsig", "TERM", "sleep", "infinity"]
    }
    onSecureChanged: {
        if (secure) entering = false     // замок на экране — заслонка больше не нужна
        // LockedHint сессии: его видят loginctl и другие программы
        if (sessionPath) Quickshell.execDetached(["busctl", "--system", "call", "org.freedesktop.login1",
            sessionPath, "org.freedesktop.login1.Session", "SetLockedHint", "b", secure ? "true" : "false"])
    }

    // ---- бездействие (уважает «не засыпать» и другие idle-inhibit) ----
    IdleMonitor {
        enabled: Prefs.idleLock > 0 && !locker.locked
        timeout: Math.max(1, Prefs.idleLock) * 60
        respectInhibitors: true
        onIsIdleChanged: if (isIdle && enabled) locker.start("lock", locker.screenOff)
    }
    // гасим экран: при бездействии, а на экране блокировки — уже через минуту
    property bool screenOff: false
    IdleMonitor {
        enabled: locker.locked || Prefs.idleOff > 0
        timeout: locker.locked ? 60 : Math.max(1, Prefs.idleOff) * 60
        respectInhibitors: true
        onIsIdleChanged: {
            locker.screenOff = isIdle && enabled   // niri включает экран сам при любом вводе
            if (locker.screenOff) Quickshell.execDetached(["niri", "msg", "action", "power-off-monitors"])
        }
    }

    IpcHandler {
        target: "lock"
        function lock(): void { locker.start("lock") }
        function test(): void { locker.start("test") }        // снимется сама через 60 с
        function preview(): void { locker.start("preview") }  // без блокировки: проверить пароль
        function cancel(): void { locker.closePreview() }     // закрывает только предпросмотр
        // показать уход без пароля — ТОЛЬКО в предпросмотре (там экран не заперт); настоящий замок так не снять
        function previewUnlock(): string {
            if (locker.mode !== "preview" || locker.unlocking) return "only in preview"
            locker.beginUnlock()
            return locker.revealStyle
        }
        function status(): string { return locker.mode || "unlocked" }
    }
}
