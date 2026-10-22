pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Обновления Glide Shell и приложений Glide из git-папки, откуда их поставили (tools/glide-update.py).
// Раз в 6 ч (первый раз — через 3 мин после входа) git fetch; новая версия — одно уведомление. «Обновить» —
// git pull + install.sh в своём юните systemd: оболочка перезапустится, итог (update.json) покажет уже новая.
Singleton {
    id: up
    readonly property string tool: Quickshell.shellDir + "/tools/glide-update.py"
    readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/glide-shell"
    property var st: ({})
    property bool checking: false
    readonly property var shell: st.shell || ({})
    readonly property var apps: st.apps || ({})
    readonly property bool available: (shell.behind || 0) > 0 || (apps.behind || 0) > 0
    readonly property bool busy: !!shell.running || !!apps.running || applying

    property bool again: false   // попросили проверить, пока шла прежняя проверка — повторить после неё
    function check(fetch) {
        if (checking) { again = again || fetch; return }
        checking = true
        stat.command = ["python3", "-I", tool, "status"].concat(fetch ? ["--fetch"] : [])
        stat.running = true
    }
    Process {
        id: stat
        stdout: StdioCollector {
            onStreamFinished: {
                try { up.st = JSON.parse(text) } catch (e) {}
                up.checking = false
                up.notifyNew()
                if (up.again) { up.again = false; up.check(true) }
            }
        }
        onExited: up.checking = false
    }

    property bool applying: false
    function apply(name) {
        applying = true
        ap.command = ["python3", "-I", tool, "apply", name]
        ap.running = true
    }
    Process {
        id: ap
        stdout: StdioCollector {
            onStreamFinished: {
                var r = {}; try { r = JSON.parse(text) } catch (e) {}
                if (!r.ok) up.notify(Tr.t("Обновить не получилось"), r.error || "", "dialog-error")
                up.applying = false
                up.check(false)
            }
        }
        onExited: up.applying = false
    }

    function notify(title, body, icon) {
        Quickshell.execDetached(["notify-send", "-a", "Glide Shell", "-i", icon || "system-software-update", title, body])
    }
    // о новой версии — один раз (Prefs.updateNotified помнит, о какой уже сказали)
    function notifyNew() {
        var key = (shell.behind > 0 ? shell.latest : "") + "|" + (apps.behind > 0 ? apps.latest : "")
        if (key === "|" || key === Prefs.updateNotified) return
        Prefs.set("updateNotified", key)
        var what = shell.behind > 0 ? Tr.t("Доступна Glide Shell ") + shell.latest : Tr.t("Есть обновление приложений Glide")
        var list = (shell.behind > 0 ? shell.changes : apps.changes) || []
        notify(what, list.slice(0, 3).join("\n") + (list.length ? "\n" : "") + Tr.t("Настройки → Поведение → Обновления"))
    }

    // итог обновления: показать один раз (после обновления оболочки — уже новой версией)
    FileView {
        path: up.stateDir + "/update.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            var r = {}; try { r = JSON.parse(text()) } catch (e) { return }
            if (r.shown || !r.finished) return
            var name = r.component === "apps" ? Tr.t("Приложения Glide") : "Glide Shell"
            if (r.ok) up.notify(name + Tr.t(" обновлена") + (r.to ? " — " + r.to : ""), r.from && r.to ? r.from + " → " + r.to : "")
            else up.notify(name + Tr.t(": обновить не получилось"), r.error || "", "dialog-error")
            Quickshell.execDetached(["python3", "-I", up.tool, "ack"])
            up.check(false)
        }
    }

    Timer { running: Prefs.warm; interval: 1000; onTriggered: up.check(false) }        // без сети — что уже известно
    Timer { running: Prefs.updateCheck && Prefs.warm; interval: 180000; onTriggered: up.check(true) }
    Timer { running: Prefs.updateCheck; interval: 6 * 3600 * 1000; repeat: true; onTriggered: up.check(true) }
}
