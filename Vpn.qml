pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Туннели для щита в баре: поднятые интерфейсы tun/tap и WireGuard. Без опроса — `ip monitor link address`
// будит перечитывание (`ip -j -d addr`), пачку событий схлопывает таймер. ZeroTier — постоянная локальная
// сеть, а не выход «наружу»: в подсказке есть, но щит из-за него не загорается.
Singleton {
    id: vpn
    property var tunnels: []      // [{name, kind, addr, lan}] — lan: true у ZeroTier
    readonly property var active: tunnels.filter(t => !t.lan)
    readonly property bool on: active.length > 0
    readonly property bool wanted: Prefs.barShows("vpn") && Prefs.warm

    function label(ifname, kind) {
        if (/^throne/.test(ifname)) return "Throne"
        if (/^zt/.test(ifname)) return "ZeroTier"
        if (/^tailscale/.test(ifname)) return "Tailscale"
        if (/^(nekoray|nekobox)/.test(ifname)) return "NekoBox"
        if (/^(proton|pvpn)/.test(ifname)) return "Proton VPN"
        if (/^(amn|amnezia)/.test(ifname)) return "AmneziaVPN"
        if (kind === "wireguard") return "WireGuard · " + ifname
        return "VPN · " + ifname
    }
    function parse(text) {
        var out = []
        try {
            for (var l of JSON.parse(text)) {
                var kind = l.linkinfo ? l.linkinfo.info_kind : ""
                if (kind !== "tun" && kind !== "wireguard") continue
                if (l.flags.indexOf("UP") < 0 || l.flags.indexOf("LOWER_UP") < 0) continue
                var a = (l.addr_info || []).find(x => x.family === "inet") || (l.addr_info || [])[0]
                out.push({ name: label(l.ifname, kind), kind: kind, addr: a ? a.local : "", lan: /^zt/.test(l.ifname) })
            }
        } catch (e) { return }
        if (JSON.stringify(out) !== JSON.stringify(tunnels)) tunnels = out
    }

    Process {
        running: vpn.wanted
        command: ["setpriv", "--pdeathsig", "TERM", "ip", "monitor", "link", "address"]
        stdout: SplitParser { onRead: settle.restart() }
        onRunningChanged: if (running) settle.restart(); else vpn.tunnels = []
    }
    Timer { id: settle; interval: 400; onTriggered: { reader.running = false; reader.running = true } }
    Process {
        id: reader
        command: ["ip", "-j", "-d", "addr"]
        stdout: StdioCollector { onStreamFinished: vpn.parse(text) }
    }
}
