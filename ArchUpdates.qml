pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Обновления Arch Linux: tools/glide-archupdates.py (свежие базы — в свою папку, система не меняется).
// Проверка раз в 3 ч (первая — через 2 мин после входа), итог — state/archupdates.json; в баре — число.
// «Обновить» — терминал с yay/paru -Syu или sudo pacman -Syu в своём юните systemd, потом проверка снова.
Singleton {
    id: au
    readonly property string tool: Quickshell.shellDir + "/tools/glide-archupdates.py"
    readonly property string stateFile: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/glide-shell/archupdates.json"
    property var st: ({})
    readonly property bool supported: st.supported !== false
    readonly property int count: Prefs.archUpdates && st.count ? st.count : 0
    readonly property var repo: st.repo || []
    readonly property var aur: st.aur || []
    readonly property bool checking: chk.running

    function check() { if (!chk.running && Prefs.archUpdates) chk.running = true }
    function upgrade() {
        Quickshell.execDetached(["systemd-run", "--user", "--collect", "--quiet", "--unit=glide-archupgrade-" + Date.now(),
                                 "python3", "-I", tool, "upgrade"])
    }
    Process { id: chk; command: ["python3", "-I", au.tool, "check"] }
    FileView {   // итог проверки (и после обновления в терминале)
        path: au.stateFile
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: { try { au.st = JSON.parse(text()) } catch (e) {} }
    }
    Timer { running: Prefs.archUpdates && Prefs.warm; interval: 120000; onTriggered: au.check() }
    Timer { running: Prefs.archUpdates; interval: 3 * 3600 * 1000; repeat: true; onTriggered: au.check() }
}
