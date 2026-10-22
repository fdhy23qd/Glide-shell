import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Services.UPower
import Quickshell.Services.SystemTray
import Quickshell.Bluetooth

// Верхний бар из плавающих капсул: слева — питание, воркспейсы niri и активное окно,
// справа — раскладка, CPU/RAM, буфер, уведомления (DMS), батарея, центр управления и трей.
// Центр занимает остров (Island.qml): он отдельным окном лежит поверх бара на той же высоте.
PanelWindow {
    id: bar
    required property var panel
    readonly property var p: panel

    visible: p.barOn
    anchors { top: true; left: true; right: true }
    implicitHeight: p.barHeight
    exclusionMode: ExclusionMode.Auto   // окна начинаются под баром
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    WlrLayershell.namespace: "glide-bar"
    color: "transparent"
    mask: Region { item: leftCap.visible ? leftCap : null; Region { item: rightCap.visible ? rightCap : null } }

    function run(argv) { p.runRaw(argv, "", "") }
    function openPlugin(id) {   // открыть категорию плагина
        var pl = p.pluginById(id)
        if (pl) p.openCategory(pl.categories[0])
    }
    function nf(code) { return String.fromCodePoint(code) }   // значок из JetBrainsMono Nerd Font

    // ---------- niri (общий модуль Niri.qml: бар и док читают один поток событий) ----------
    readonly property var workspaces: Niri.workspaces
    readonly property var windows: Niri.windows
    readonly property var focusedId: Niri.focusedId
    readonly property var layouts: Niri.layouts
    readonly property int layoutIdx: Niri.layoutIdx

    // несколько мониторов: бар показывает свои воркспейсы и окно своего монитора
    readonly property string outName: screen ? screen.name : ""
    readonly property bool multi: Quickshell.screens.length > 1
    // режим мониторов: что этот бар показывает (см. Prefs.monitorMode)
    readonly property string mode: Prefs.monitorMode
    readonly property bool isMain: !multi || screen === p.panelScreen
    readonly property bool showLeft: !multi || mode === "mirror" || (mode === "unite" ? screen === p.leftmostScreen : isMain)
    readonly property bool showRight: !multi || mode === "mirror" || (mode === "unite" ? screen === p.rightmostScreen : isMain)
    // «продолжение»: на соседнем мониторе — капсула с его столами и окном, со стороны, где он стоит
    readonly property string extSide: multi && mode === "extend" && !isMain && p.panelScreen
                                      ? (screen.x < p.panelScreen.x ? "left" : "right") : ""
    // чьи столы и окно: в «продолжении» — свои, в одном баре на всё («объединение», «стандарт») — монитора в фокусе
    readonly property string wsOut: mode === "extend" || mode === "mirror" ? outName : Niri.focusedOutput
    readonly property var myWorkspaces: multi ? workspaces.filter(w => w.output === wsOut) : workspaces
    readonly property var focusedWindow: {
        if (!multi) return focusedId !== null && windows[focusedId] ? windows[focusedId] : null
        var a = myWorkspaces.find(w => w.is_active)
        return a && a.active_window_id !== null && windows[a.active_window_id] ? windows[a.active_window_id] : null
    }
    // действие niri над воркспейсами этого монитора: сначала фокус на него (номера столов — свои у монитора)
    function wsAction(args) {
        if (!multi || !wsOut) { run(["niri", "msg", "action"].concat(args)); return }
        run(["sh", "-c", 'o=$1; shift; niri msg action focus-monitor "$o"; exec niri msg action "$@"', "sh", wsOut].concat(args))
    }
    // как в DMS: только занятые воркспейсы и текущий
    // Воркспейсы — ListModel, который правится на месте и только при реальных изменениях:
    // смена заголовка окна (частое событие) ничего не пересобирает, а смена текущего
    // воркспейса плавно перекрашивает пилюли вместо пересоздания
    readonly property string wsSig: JSON.stringify(
        (Prefs.barAllWorkspaces ? myWorkspaces : myWorkspaces.filter(w => w.is_active || w.is_focused || appsOn(w.id).length > 0))
        .map(w => ({ wsId: w.id, idx: w.idx, cur: !!w.is_active, urgent: !!w.is_urgent, apps: appsOn(w.id).join("|") })))
    property int wsCur: -1   // строка текущего воркспейса в wsList — к ней едет пилюля
    onWsSigChanged: {
        var arr = JSON.parse(wsSig)
        for (var i = 0; i < arr.length; i++) {
            if (i < wsList.count) wsList.set(i, arr[i]); else wsList.append(arr[i])
        }
        if (wsList.count > arr.length) wsList.remove(arr.length, wsList.count - arr.length)
        wsCur = arr.findIndex(w => w.cur)
    }
    ListModel { id: wsList }

    function appsOn(wsId) {   // приложения воркспейса слева направо, без повторов, не больше трёх
        var ws = []
        for (var id in windows) if (windows[id].workspace_id === wsId) ws.push(windows[id])
        ws.sort((a, b) => {
            var pa = a.layout && a.layout.pos_in_scrolling_layout, pb = b.layout && b.layout.pos_in_scrolling_layout
            return (pa ? pa[0] : 99) - (pb ? pb[0] : 99)
        })
        var out = []
        for (var w of ws) if (w.app_id && out.indexOf(w.app_id) < 0) out.push(w.app_id)
        return out.slice(0, 3)
    }
    function iconFor(appId) { return Niri.iconFor(appId) }
    readonly property string layoutShort: {
        var n = layouts[layoutIdx] || ""
        var first = n.split(/[\s(]/)[0]
        var known = { English: "EN", Russian: "RU", Ukrainian: "UA", Belarusian: "BY", German: "DE",
                      French: "FR", Spanish: "ES", Polish: "PL", Kazakh: "KZ" }
        return known[first] || first.slice(0, 2).toUpperCase()
    }

    // ---------- CPU и память ----------
    property real cpu: 0
    property real mem: 0
    property var cpuPrev: null
    function parseStats(t) {
        var lines = t.split("\n")
        var c = lines[0].trim().split(/\s+/).slice(1).map(Number)
        var idle = c[3] + (c[4] || 0), total = c.reduce((a, b) => a + b, 0)
        if (cpuPrev && total > cpuPrev.total)
            cpu = 100 * (1 - (idle - cpuPrev.idle) / (total - cpuPrev.total))
        cpuPrev = { total: total, idle: idle }
        var mt = 0, ma = 0
        for (var l of lines) {
            var m = l.match(/^(\w+):\s+(\d+)/)
            if (m && m[1] === "MemTotal") mt = +m[2]
            else if (m && m[1] === "MemAvailable") ma = +m[2]
        }
        if (mt) mem = 100 * (1 - ma / mt)
    }
    // один долгоживущий процесс вместо запуска трёх новых каждые 2 с
    property var statBuf: []
    Process {
        id: statProc
        // только пока капсулы ЦП или памяти на баре; умирает вместе с оболочкой
        running: bar.visible && (Prefs.barShows("cpu") || Prefs.barShows("mem"))
        command: ["setpriv", "--pdeathsig", "TERM", "sh", "-c", "while :; do head -1 /proc/stat; grep -E '^(MemTotal|MemAvailable):' /proc/meminfo; echo .; sleep 2; done"]
        stdout: SplitParser {
            onRead: (line) => {
                if (line !== ".") { bar.statBuf.push(line); return }
                bar.parseStats(bar.statBuf.join("\n"))
                bar.statBuf = []
            }
        }
    }

    // ---------- «не беспокоить»: свои уведомления (Notifs) или, пока они выключены, DMS ----------
    property bool dmsDnd: false
    readonly property bool dnd: Notifs.active ? Notifs.quiet : dmsDnd   // любая «тишина»: вручную, ночью, при демонстрации
    FileView {
        path: Notifs.active ? "" : (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/DankMaterialShell/session.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: { try { bar.dmsDnd = JSON.parse(text()).doNotDisturb === true } catch (e) {} }
    }

    // ---------- батарея ----------
    readonly property var batt: UPower.displayDevice
    readonly property bool hasBatt: !!batt && batt.isLaptopBattery
    readonly property real battPct: hasBatt ? batt.percentage * 100 : 0
    readonly property bool charging: hasBatt && (batt.state === UPowerDeviceState.Charging
                                                 || batt.state === UPowerDeviceState.FullyCharged)
    function battGlyph(pct, chg) {
        if (chg) return nf(0xF0084)
        var i = Math.round(pct / 10)
        if (i >= 10) return nf(0xF0079)
        return i <= 0 ? nf(0xF008E) : nf(0xF007A + i - 1)   // battery-10 … battery-90
    }

    // ---------- элементы ----------
    component Capsule: Rectangle {
        id: cap
        default property alias items: row.data
        // shaped — капсула рисуется контуром TrayShape: из неё может свисать меню трея (menuH > 0)
        property bool shaped: false
        property real menuL: 0
        property real menuR: 0
        property real menuH: 0
        property real fillet: 0
        property bool mirror: false          // содержимое справа налево (капсула у правого края)
        y: 6
        height: 32
        width: row.implicitWidth + 8
        radius: Theme.r(16)
        color: shaped ? "transparent" : Theme.backgroundBar   // непрозрачность — настройка «Прозрачность»
        border.color: shaped ? "transparent" : Theme.outline
        Item {   // бар показывает только капсулу: всё ниже её края рисует окно меню (стык без перекрытия)
            visible: cap.shaped
            width: cap.width; height: cap.height
            clip: true
            TrayShape {
                capW: cap.width; capH: cap.height; capR: cap.radius
                menuL: cap.menuL; menuR: cap.menuR; menuH: cap.menuH
                fillet: cap.fillet
                menuRadius: Theme.radiusMd
            }
        }
        Behavior on width { enabled: Prefs.anim > 0; Spring { bounce: 0.2; speed: 1.3 } }
        Row {
            id: row
            x: 4
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2
            layoutDirection: cap.mirror ? Qt.RightToLeft : Qt.LeftToRight
        }
    }

    component Chip: Rectangle {
        id: chip
        property bool want: true      // «хочу быть видимым» — для слота капсулы (не зависит от видимости родителя)
        property string glyph
        property string label
        property color tint: Theme.textVariant
        property bool lit: false
        property string tipKey: ""           // подсказка-капля по наведению (bar.tipHover)
        readonly property bool hot: chipMa.containsMouse
        signal clicked(int button)
        signal wheel(int delta)
        anchors.verticalCenter: parent ? parent.verticalCenter : undefined
        height: 24
        width: chipRow.implicitWidth + 16
        radius: Theme.r(12)
        color: lit ? Prefs.accentSoft : (chipMa.containsMouse ? Theme.surfaceHigh : "transparent")
        property real bump: 1
        function pop() { popAnim.restart() }   // «подпрыгнуть»: прилетело уведомление и т.п.
        SequentialAnimation {
            id: popAnim
            NumberAnimation { target: chip; property: "bump"; to: 1.3; duration: Prefs.ms(110); easing.type: Easing.OutQuad }
            NumberAnimation { target: chip; property: "bump"; to: 1; duration: Prefs.ms(320); easing.type: Easing.OutBack; easing.overshoot: 2.5 }
        }
        scale: (chipMa.pressed ? 0.92 : 1) * bump
        Behavior on color { ColorAnimation { duration: Prefs.ms(140) } }
        Behavior on scale { NumberAnimation { duration: Prefs.ms(140); easing.type: Easing.OutBack } }
        Row {
            id: chipRow
            anchors.centerIn: parent
            spacing: 5
            Text {
                visible: chip.glyph !== ""
                anchors.verticalCenter: parent.verticalCenter
                text: chip.glyph
                color: chip.tint
                font.family: Prefs.iconFont
                font.pixelSize: Theme.fs(15)
            }
            Text {
                visible: chip.label !== ""
                anchors.verticalCenter: parent.verticalCenter
                text: chip.label
                color: Theme.text
                font.pixelSize: Theme.fs(12)
                font.features: ({ "tnum": 1 })
            }
        }
        MouseArea {
            id: chipMa
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
            cursorShape: Qt.PointingHandCursor
            onClicked: (m) => chip.clicked(m.button)
            onWheel: (w) => chip.wheel(w.angleDelta.y)
        }
    }

    // ---------- левая капсула ----------
    Capsule {
        id: leftCap
        visible: (bar.showLeft || bar.extSide !== "") && bar.leftIds.length > 0
        x: bar.extSide === "right" ? bar.width - width - 8 : 8
        mirror: bar.extSide === "right"
        // подсказки, список окон и меню трея (если он здесь) вытекают тем же контуром — как у правой
        shaped: true
        readonly property bool dropping: trayMenu.attached && trayMenu.cap === leftCap && trayMenu.openT > 0
        readonly property bool tipping: !dropping && capDrop.cap === leftCap && capDrop.openT > 0
        menuR: tipping ? capDrop.menuL + capDrop.menuW : dropping ? width - trayMenu.offR : 0
        menuL: tipping ? capDrop.menuL : dropping ? menuR - trayMenu.menuW : 0
        menuH: dropping ? trayMenu.dropH : tipping ? capDrop.dropH : 0
        fillet: dropping ? trayMenu.fillet * Math.min(1, trayMenu.openT * 1.5)
              : tipping ? capDrop.fillet * Math.min(1, capDrop.openT * 1.5) : 0

        Repeater { model: bar.leftIds; delegate: PartSlot {} }
    }

    // ---------- правая капсула ----------
    Capsule {
        id: rightCap
        visible: bar.showRight && bar.rightIds.length > 0
        x: bar.width - width - 8
        // меню трея вытекает отсюда: тот же контур, что рисует окно меню, только верхняя часть
        shaped: true
        readonly property bool dropping: trayMenu.attached && trayMenu.cap === rightCap && trayMenu.openT > 0
        readonly property bool tipping: !dropping && capDrop.cap === rightCap && capDrop.openT > 0
        menuR: tipping ? capDrop.menuL + capDrop.menuW : width - trayMenu.offR
        menuL: tipping ? capDrop.menuL : menuR - trayMenu.menuW
        menuH: dropping ? trayMenu.dropH : tipping ? capDrop.dropH : 0
        fillet: dropping ? trayMenu.fillet * Math.min(1, trayMenu.openT * 1.5)
              : tipping ? capDrop.fillet * Math.min(1, capDrop.openT * 1.5) : 0

        Repeater { model: bar.rightIds; delegate: PartSlot {} }
    }

    // ---------- части капсул: каждая — отдельный компонент, капсулы собирают их по Prefs.barItems ----------
    Component {
        id: part_power
        Chip { visible: want; want: Prefs.barShows("power") && bar.extSide === ""; glyph: bar.nf(0xF0425); tipKey: "power"; onHotChanged: bar.tipHover(this); onClicked: bar.p.openCategory("power") }
    }
    Component {
        id: part_workspaces
        Item {   // воркспейсы; колесо листает. Акцентная пилюля — одна на всех и перетекает к текущему
            visible: want
            property bool want: Prefs.barShows("workspaces")
            anchors.verticalCenter: parent.verticalCenter
            width: wsRow.width; height: 24
            readonly property var curItem: {
                var n = wsRep.count, i = bar.wsCur   // зависимости: число и текущий
                return i >= 0 && i < n ? wsRep.itemAt(i) : null
            }
            Rectangle {
                id: wsPill
                readonly property var t: parent.curItem
                visible: !!t
                x: t ? t.x : 0
                width: t ? t.width : 0
                height: 24
                radius: Theme.r(12)
                color: Prefs.accent
                scale: t && t.down ? 0.9 : 1
                Behavior on scale { NumberAnimation { duration: Prefs.ms(140); easing.type: Easing.OutBack } }
                // перетекает к новому рабочему столу с отскоком
                Behavior on x { enabled: Prefs.anim > 0; Spring { bounce: 0.25; speed: 1.3 } }
                Behavior on width { enabled: Prefs.anim > 0; Spring { bounce: 0.3; speed: 1.4 } }
            }
            Row {
                id: wsRow
                spacing: 3
                leftPadding: 2; rightPadding: 4
                Repeater {
                    id: wsRep
                    model: wsList
                    delegate: Rectangle {
                        id: ws
                        required property int idx
                        required property bool cur
                        required property bool urgent
                        required property string apps
                        readonly property var appList: apps ? apps.split("|") : []
                        anchors.verticalCenter: parent.verticalCenter
                        height: 24
                        width: wsInner.implicitWidth + (cur ? 18 : 12)
                        radius: Theme.r(12)
                        readonly property bool down: wsMa.pressed
                        // текущий — прозрачный: под ним акцентная пилюля wsPill
                        color: cur ? (wsMa.containsMouse ? Qt.rgba(1, 1, 1, 0.1) : "transparent")
                                   : urgent ? Theme.errorContainer : (wsMa.containsMouse ? Theme.surfaceHigher : Theme.surface)
                        scale: wsMa.pressed && !cur ? 0.9 : 1
                        Behavior on scale { NumberAnimation { duration: Prefs.ms(140); easing.type: Easing.OutBack } }
                        Behavior on width { enabled: Prefs.anim > 0; Spring { bounce: 0.3; speed: 1.4 } }
                        Behavior on color { ColorAnimation { duration: Prefs.ms(180) } }
                        Row {
                            id: wsInner
                            anchors.centerIn: parent
                            spacing: 4
                            Text {
                                Behavior on color { ColorAnimation { duration: Prefs.ms(140) } }
                                anchors.verticalCenter: parent.verticalCenter
                                text: ws.idx
                                color: ws.cur ? Theme.accentText : Theme.textVariant
                                font.pixelSize: Theme.fs(12); font.bold: true
                            }
                            Repeater {
                                model: Prefs.barWsIcons ? ws.appList : []
                                delegate: IconImage {
                                    required property var modelData
                                    anchors.verticalCenter: parent.verticalCenter
                                    implicitSize: 14
                                    source: bar.iconFor(modelData)
                                }
                            }
                        }
                        MouseArea {
                            id: wsMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: bar.wsAction(["focus-workspace", String(ws.idx)])
                        }
                    }
                }
                WheelHandler {
                    onWheel: (w) => {
                        if (wsCool.running || Math.abs(w.angleDelta.y) < 30) return
                        bar.wsAction([w.angleDelta.y < 0 ? "focus-workspace-down" : "focus-workspace-up"])
                        wsCool.restart()
                    }
                }
                Timer { id: wsCool; interval: 250 }
            }
        }
    }
    Component {
        id: part_window
        Row {   // активное окно; клик — переключатель окон
            visible: want
            Component.onCompleted: bar.winTitleItem = winTitle
            Component.onDestruction: if (bar.winTitleItem === winTitle) bar.winTitleItem = null
            property bool want: !!bar.focusedWindow && Prefs.barShows("window")
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6
            leftPadding: 6; rightPadding: 10
            IconImage {
                anchors.verticalCenter: parent.verticalCenter
                implicitSize: 16
                source: bar.focusedWindow ? bar.iconFor(bar.focusedWindow.app_id) : ""
            }
            Text {
                id: winTitle
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, 220)
                text: bar.focusedWindow ? bar.focusedWindow.title : ""
                color: winMa.containsMouse ? Theme.text : Theme.textVariant   // наведение — ярче, нажатие — чуть меньше
                scale: winMa.pressed ? 0.96 : 1
                Behavior on color { ColorAnimation { duration: Prefs.ms(140) } }
                Behavior on scale { NumberAnimation { duration: Prefs.ms(140); easing.type: Easing.OutBack } }
                font.pixelSize: Theme.fs(12)
                elide: Text.ElideRight
                MouseArea { id: winMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: bar.toggleWindows(parent) }
            }
        }
    }
    Component {
        id: part_layout
        Chip {
            visible: want
            want: bar.layouts.length > 1 && Prefs.barShows("layout")
            glyph: bar.p.capsLock ? bar.nf(0xF0632) : ""   // включён Caps Lock — стрелка рядом с раскладкой
            tint: bar.p.capsLock ? Theme.warning : Theme.textVariant
            tipKey: "layout"; onHotChanged: bar.tipHover(this)
            label: bar.layoutShort
            onClicked: bar.run(["niri", "msg", "action", "switch-layout", "next"])
        }
    }
    Component {
        id: part_cpu
        Chip {
            visible: want
            want: Prefs.barShows("cpu")
            glyph: bar.nf(0xF0EE0)
            tipKey: "cpu"; onHotChanged: bar.tipHover(this)
            label: Math.round(bar.cpu) + "%"
            tint: bar.cpu > 85 ? Theme.error : Theme.textVariant
            onClicked: bar.openPlugin("processes")
        }
    }
    Component {
        id: part_mem
        Chip {
            visible: want
            want: Prefs.barShows("mem")
            glyph: bar.nf(0xF035B)
            tipKey: "mem"; onHotChanged: bar.tipHover(this)
            label: Math.round(bar.mem) + "%"
            tint: bar.mem > 85 ? Theme.error : Theme.textVariant
            onClicked: bar.openPlugin("processes")
        }
    }
    Component {
        id: part_clipboard
        Chip { visible: want; want: Prefs.barShows("clipboard"); glyph: bar.nf(0xF014C); tipKey: "clipboard"; onHotChanged: bar.tipHover(this); onClicked: bar.p.openCategory("clipboard") }
    }
    Component {
        id: part_notifications
        Chip {   // клик — история уведомлений, правый — «не беспокоить»; число — непрочитанные
            visible: want
            Component.onCompleted: bar.bellItem = bellChip
            Component.onDestruction: if (bar.bellItem === bellChip) bar.bellItem = null
            id: bellChip
            want: Prefs.barShows("notifications")
            tipKey: "notifications"; onHotChanged: bar.tipHover(this)
            onWheel: (d) => bar.volumeBy(d)
            glyph: bar.dnd ? bar.nf(0xF009B) : Notifs.active && Notifs.unread > 0 ? bar.nf(0xF116B) : bar.nf(0xF009A)
            label: Notifs.active && Notifs.unread > 0 && !bar.dnd ? String(Notifs.unread) : ""
            tint: bar.dnd ? Theme.warning : Notifs.active && Notifs.unread > 0 ? Prefs.accent : Theme.textVariant
            onClicked: (b) => {
                if (!Notifs.active)
                    bar.run(["dms", "ipc", "call", "notifications", b === Qt.RightButton ? "toggleDoNotDisturb" : "toggle"])
                else if (b === Qt.RightButton) Notifs.setDnd(!Notifs.dnd)
                else bar.p.openCategory("notify")
            }
        }
    }
    Component {
        id: part_battery
        Chip {
            visible: want
            want: bar.hasBatt && Prefs.barShows("battery")
            glyph: bar.chargingNow ? bar.chargeFrame : bar.battGlyph(bar.battPct, bar.charging)
            tipKey: "battery"; onHotChanged: bar.tipHover(this)
            label: Math.round(bar.battPct) + "%"
            onWheel: (d) => bar.brightnessBy(d)
            tint: bar.charging ? Theme.success : bar.battPct <= 15 ? Theme.error : Theme.textVariant
            onClicked: bar.p.openCategory("control")
        }
    }
    Component {
        id: part_phone
        Chip {   // телефон через KDE Connect: заряд, пока на связи; клик — категория «Телефон»
            visible: want
            readonly property var ph: KdeConnect.phone
            want: KdeConnect.available && !!ph && ph.reachable && Prefs.barShows("phone")
            glyph: bar.nf(0xF011C)
            tipKey: "phone"; onHotChanged: bar.tipHover(this)
            label: ph && ph.battery !== undefined ? ph.battery + "%" : ""
            tint: ph && ph.charging ? Theme.success : ph && ph.battery !== undefined && ph.battery <= 15 ? Theme.error : Theme.textVariant
            onClicked: bar.p.openCategory("phone")
        }
    }
    Component {
        id: part_vpn
        Chip {   // VPN: щит, пока поднят туннель (Vpn.qml); клик — подсказка со списком
            visible: want
            want: Vpn.on && Prefs.barShows("vpn")
            glyph: bar.nf(0xF0565)
            tipKey: "vpn"; onHotChanged: bar.tipHover(this)
            tint: Theme.success
            onClicked: bar.showTip(capDrop.key === "vpn" ? "" : "vpn")
        }
    }
    Component {
        id: part_awake
        Chip {   // «не засыпать» включено — чашка; клик выключает
            visible: want
            want: bar.p.awake && Prefs.barShows("awake")
            tipKey: "awake"; onHotChanged: bar.tipHover(this)
            glyph: bar.nf(0xF0176)
            tint: Theme.warning
            onClicked: bar.p.setAwake(false)
        }
    }
    Component {
        id: part_control
        Chip {
            visible: want
            want: Prefs.barShows("control")
            glyph: bar.nf(0xF062E)
            tipKey: "control"; onHotChanged: bar.tipHover(this)
            lit: bar.p.shown && bar.p.category === "control"
            onWheel: (d) => bar.brightnessBy(d)
            onClicked: bar.p.openCategory("control")
        }
    }
    Component {
        id: part_tray
        Row {   // трей: левый клик — открыть, правый — меню, средний — второе действие
            visible: want
            Component.onCompleted: bar.trayRepItem = trayRep
            Component.onDestruction: if (bar.trayRepItem === trayRep) bar.trayRepItem = null
            property bool want: SystemTray.items.values.length > 0 && Prefs.barShows("tray")
            anchors.verticalCenter: parent.verticalCenter
            leftPadding: 4; rightPadding: 6
            spacing: 2
            Repeater {
                id: trayRep
                model: SystemTray.items
                delegate: Item {
                    id: tray
                    required property var modelData
                    width: 24; height: 24
                    // открыто его меню — подсвечен, как нажатый
                    readonly property bool menuOpen: trayMenu.visible && trayMenu.owner === modelData
                    readonly property string tipKey: "tray"
                    readonly property bool hot: trayMa.containsMouse
                    onHotChanged: bar.tipHover(this)
                    scale: trayMa.pressed ? 0.88 : 1
                    Behavior on scale { NumberAnimation { duration: Prefs.ms(140); easing.type: Easing.OutBack } }
                    Rectangle {
                        anchors.fill: parent
                        radius: Theme.r(12)
                        color: tray.menuOpen ? Prefs.accentSoft : trayMa.containsMouse ? Theme.surfaceHigh : "transparent"
                        Behavior on color { ColorAnimation { duration: Prefs.ms(140) } }
                    }
                    IconImage {
                        anchors.centerIn: parent
                        implicitSize: 16
                        source: tray.modelData.icon
                    }
                    MouseArea {
                        id: trayMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                        onClicked: (m) => {
                            var it = tray.modelData
                            if (m.button === Qt.MiddleButton) it.secondaryActivate()
                            else if ((m.button === Qt.RightButton || it.onlyMenu) && it.hasMenu) {
                                capDrop.hide()
                                var pt = tray.mapToItem(null, tray.width, tray.height + 8)
                                trayMenu.openFor(it, bar, pt.x, pt.y, true, bar.capOf(tray))
                            } else it.activate()
                        }
                        onWheel: (w) => tray.modelData.scroll(w.angleDelta.y, false)
                    }
                }
            }
        }
    }
    Component {
        id: part_volume
        Chip {   // громкость: значок и процент; колесо — громче/тише, щелчок — без звука, правый — микшер
            visible: want
            readonly property var a: bar.p.sink && bar.p.sink.audio
            want: !!a
            glyph: !a || a.muted ? bar.nf(0xF0581) : a.volume > 0.66 ? bar.nf(0xF057E) : a.volume > 0.33 ? bar.nf(0xF0580) : bar.nf(0xF057F)
            label: a && !a.muted ? Math.round(a.volume * 100) + "%" : ""
            tint: a && a.muted ? Theme.warning : Theme.textVariant
            onWheel: (d) => bar.volumeBy(d)
            onClicked: (b) => { if (b === Qt.RightButton) bar.openPlugin("mixer"); else if (a) a.muted = !a.muted }
        }
    }
    Component {
        id: part_mic
        Chip {   // микрофон: виден, пока выключен (или всегда — щелчок включает/выключает)
            visible: want
            readonly property var a: bar.p.source && bar.p.source.audio
            want: !!a
            glyph: a && a.muted ? bar.nf(0xF036D) : bar.nf(0xF036C)
            tint: a && a.muted ? Theme.error : Theme.textVariant
            onClicked: if (a) a.muted = !a.muted
        }
    }
    Component {
        id: part_bluetooth
        Chip {   // Bluetooth: пока подключено устройство — значок и заряд (если устройство его сообщает)
            visible: want
            readonly property var devs: { var ad = Bluetooth.defaultAdapter; return ad && ad.enabled ? ad.devices.values.filter(x => x.connected) : [] }
            readonly property var dev: devs.length ? devs[0] : null
            want: devs.length > 0
            glyph: bar.nf(0xF00B1)
            label: dev && dev.batteryAvailable ? Math.round(dev.battery * 100) + "%" : devs.length > 1 ? String(devs.length) : ""
            onClicked: bar.p.openCategory("control")
        }
    }
    Component {
        id: part_night
        Chip {   // ночной свет: луна, пока включён; щелчок — включить/выключить
            visible: want
            want: NightLight.available
            glyph: NightLight.on ? bar.nf(0xF0594) : bar.nf(0xF0F67)
            tint: NightLight.on ? Theme.warning : Theme.textVariant
            onClicked: NightLight.toggle()
        }
    }
    Component {
        id: part_updates
        Chip {   // обновления Arch: число пакетов; наведение — список, щелчок — терминал с обновлением
            visible: want
            want: ArchUpdates.count > 0
            glyph: bar.nf(0xF03D4)
            label: String(ArchUpdates.count)
            tint: Prefs.accent
            tipKey: "updates"; onHotChanged: bar.tipHover(this)
            onClicked: { capDrop.hide(); ArchUpdates.upgrade() }
        }
    }
    Component {
        id: part_weather
        Chip {   // погода: значок и температура; щелчок — «Сегодня»
            visible: want
            want: Weather.ok
            glyph: Weather.ok ? Weather.icon(Weather.data.now.code, Weather.data.now.day) : ""
            label: Weather.ok ? Weather.temp(Weather.data.now.temp) : ""
            onClicked: bar.p.openCategory("today")
        }
    }
    Component {
        id: part_powerprofile
        Chip {   // профиль питания: щелчок — следующий (экономия → баланс → производительность)
            visible: want
            readonly property var opts: PowerProfiles.hasPerformanceProfile
                ? [PowerProfile.PowerSaver, PowerProfile.Balanced, PowerProfile.Performance] : [PowerProfile.PowerSaver, PowerProfile.Balanced]
            want: PowerProfiles.profile !== undefined
            glyph: PowerProfiles.profile === PowerProfile.PowerSaver ? bar.nf(0xF032A) : PowerProfiles.profile === PowerProfile.Performance ? bar.nf(0xF04C5) : bar.nf(0xF0A7A)
            tint: PowerProfiles.profile === PowerProfile.PowerSaver ? Theme.success : PowerProfiles.profile === PowerProfile.Performance ? Theme.warning : Theme.textVariant
            onClicked: PowerProfiles.profile = opts[(opts.indexOf(PowerProfiles.profile) + 1) % opts.length]
        }
    }
    Component {
        id: part_screenshot
        Chip {   // скриншот области (редактор Glide Apps, если есть; иначе niri)
            visible: want
            glyph: bar.nf(0xF0100)
            onClicked: bar.run(["sh", "-c", 'p="$HOME/.local/bin/glide-shot"; [ -x "$p" ] && exec "$p" --capture region || exec niri msg action screenshot'])
        }
    }
    readonly property var parts: ({ power: part_power, workspaces: part_workspaces, window: part_window, layout: part_layout, cpu: part_cpu, mem: part_mem, clipboard: part_clipboard, notifications: part_notifications, battery: part_battery, phone: part_phone, vpn: part_vpn, awake: part_awake, control: part_control, tray: part_tray, volume: part_volume, mic: part_mic, bluetooth: part_bluetooth, night: part_night, weather: part_weather, powerprofile: part_powerprofile, screenshot: part_screenshot, updates: part_updates })
    property var winTitleItem: null        // заголовок окна (список окон вытекает из-под него)
    property var bellItem: null            // колокольчик (туда «влетают» уведомления)
    property var trayRepItem: null         // значки трея (меню по IPC)
    readonly property var leftIds: Prefs.barItems.filter(x => x.place === "left").map(x => x.id)
    readonly property var rightIds: Prefs.barItems.filter(x => x.place === "right").map(x => x.id)
    component PartSlot: Loader {
        required property string modelData
        sourceComponent: bar.parts[modelData] || null
        visible: !!item && item.want   // не item.visible: внутри невидимого слота он всегда false
        anchors.verticalCenter: parent ? parent.verticalCenter : undefined
    }

    // ---------- колесо над капсулами: батарея и центр управления — яркость, колокольчик — громкость ----------
    function brightnessBy(d) {
        if (wheelCool.running || Math.abs(d) < 30) return
        wheelCool.restart()
        run(["sh", Quickshell.shellDir + "/tools/glide-brightness.sh", d > 0 ? "+5" : "-5"])   // сам покажет OSD
    }
    function volumeBy(d) {
        var a = p.sink && p.sink.audio
        if (!a || Math.abs(d) < 30) return
        a.volume = Math.max(0, Math.min(1, a.volume + (d > 0 ? 0.05 : -0.05)))   // OSD — по смене громкости
        if (a.muted && d > 0) a.muted = false
    }
    Timer { id: wheelCool; interval: 60 }

    // ---------- зарядка: значок наполняется ступеньками (раз в 0,7 с — без постоянной перерисовки) ----------
    readonly property bool fullNow: !!batt && (batt.state === UPowerDeviceState.FullyCharged || battPct >= 99.5)
    readonly property bool chargingNow: hasBatt && batt.state === UPowerDeviceState.Charging && !fullNow
    readonly property var chargeFrames: [0xF089C, 0xF0086, 0xF0087, 0xF0088, 0xF089D, 0xF0089, 0xF089E, 0xF008A, 0xF008B, 0xF0085]
    property int chargeStep: 0
    readonly property string chargeFrame: {
        var base = Math.max(0, Math.min(8, Math.floor(battPct / 10) - 1))
        return nf(chargeFrames[base + chargeStep % (10 - base)])
    }
    Timer {
        running: bar.chargingNow && bar.visible && Prefs.anim > 0 && Prefs.barShows("battery")
        interval: 700; repeat: true
        onTriggered: bar.chargeStep++
        onRunningChanged: bar.chargeStep = 0
    }
    // кабель подключили или вынули — вспышка в острове (не при запуске оболочки)
    readonly property bool plugged: hasBatt && batt.state !== UPowerDeviceState.Discharging && batt.state !== UPowerDeviceState.Empty
    property bool plugArmed: false
    Timer { running: true; interval: 4000; onTriggered: bar.plugArmed = true }
    onPluggedChanged: if (plugArmed) {
        if (plugged) p.flash(nf(0xF06A5), Tr.t("Зарядка подключена · ") + Math.round(battPct) + "%", Theme.success)
        else p.flash(battGlyph(battPct, false), Tr.t("От батареи · ") + Math.round(battPct) + "%"
                     + (batt.timeToEmpty > 0 ? " · ≈" + dur(batt.timeToEmpty) : ""), Theme.textVariant)
    }

    // ---------- уведомление «улетает» из острова в колокольчик ----------
    property var lastPopup: null
    property int lastUnread: 0
    Connections {
        target: Notifs
        function onPopupChanged() {
            // всплывашка ушла сама (не закрыли и не открыли) — запись осталась непрочитанной
            var e = bar.lastPopup
            if (e && !Notifs.popup && e.unread && Notifs.list.indexOf(e) >= 0) bar.flyToBell()
            bar.lastPopup = Notifs.popup
        }
        function onUnreadChanged() {
            // в «не беспокоить» всплывашки нет — точка летит сразу при поступлении
            if (Notifs.unread > bar.lastUnread && Notifs.quiet && !Notifs.popup) bar.flyToBell()
            bar.lastUnread = Notifs.unread
        }
    }
    function flyToBell() {
        var bellChip = bar.bellItem
        if (!bellChip) return
        if (!bellChip.visible || !visible || Prefs.anim <= 0) { bellChip.pop(); return }
        var to = bellChip.mapToItem(contentItem, bellChip.width / 2, bellChip.height / 2)
        // с главного монитора — из-под острова; с соседнего — от края со стороны главного
        var from = isMain ? width / 2 : p.panelScreen && screen.x > p.panelScreen.x ? 0 : width
        flyer.x = from - flyer.width / 2
        flyer.y = to.y - flyer.height / 2
        flyX.to = to.x - flyer.width / 2
        fly.restart()
    }
    Rectangle {   // летящая точка: из-под острова по пустому месту бара к колокольчику
        id: flyer
        width: 10; height: 10; radius: 5
        color: Prefs.accent
        opacity: 0
        z: 50
        SequentialAnimation {
            id: fly
            NumberAnimation { target: flyer; property: "opacity"; to: 1; duration: Prefs.ms(60) }
            ParallelAnimation {
                NumberAnimation { id: flyX; target: flyer; property: "x"; duration: Prefs.ms(520); easing.type: Easing.InOutCubic }
                SequentialAnimation {   // лёгкая дуга
                    NumberAnimation { target: flyer; property: "scale"; to: 1.4; duration: Prefs.ms(260); easing.type: Easing.OutQuad }
                    NumberAnimation { target: flyer; property: "scale"; to: 0.6; duration: Prefs.ms(260); easing.type: Easing.InQuad }
                }
            }
            ScriptAction { script: if (bar.bellItem) bar.bellItem.pop() }
            NumberAnimation { target: flyer; property: "opacity"; to: 0; duration: Prefs.ms(80) }
            ScriptAction { script: flyer.scale = 1 }
        }
    }

    TrayMenu { id: trayMenu }

    // ---------- капли из капсул: подсказки по наведению и список окон по щелчку ----------
    property var tipTarget: null
    function capOf(item) {
        for (var it = item; it; it = it.parent) if (it === leftCap || it === rightCap) return it
        return null
    }
    function tipHover(item) {
        if (item.hot) {
            tipTarget = item
            tipLeave.stop()
            if (trayMenu.visible || capDrop.key === "windows" || p.shown) return
            // подсказка уже открыта — следующая сразу, без задержки
            if (capDrop.visible && capDrop.key !== "") openTip(); else tipDelay.restart()
        } else if (tipTarget === item) {
            tipDelay.stop()
            tipLeave.restart()
        }
    }
    function openTip() {
        var t = tipTarget
        if (!t || !t.hot || !t.tipKey) return
        if (t.tipKey === "tray" && !(t.modelData.tooltipTitle || t.modelData.title)) return
        var cap = capOf(t)
        if (!cap) return
        tipItem = t
        capDrop.show(t.tipKey, bar, cap, t.mapToItem(cap, t.width / 2, 0).x, 250, false)
    }
    property var tipItem: null          // чей значок описывает открытая подсказка (трей — его modelData)
    Timer { id: tipDelay; interval: 550; onTriggered: bar.openTip() }
    Timer {
        id: tipLeave
        interval: 200
        onTriggered: {
            if (capDrop.key === "windows" || capDrop.hovered || (bar.tipTarget && bar.tipTarget.hot)) return
            capDrop.hide()
            bar.tipTarget = null
        }
    }
    Connections { target: capDrop; function onHoveredChanged() { if (!capDrop.hovered) tipLeave.restart() } }
    // панель открывается — капля исчезает сразу, без анимации: попап бара рядом с окном панели, забирающим
    // клавиатуру, подвешивал оболочку (зависания при щелчке по капсуле с открытой подсказкой)
    Connections {
        target: bar.p
        function onShownChanged() {
            if (!bar.p.shown) return
            tipDelay.stop(); tipLeave.stop()
            capDrop.pending = null; capDrop.closing = false
            capDrop.visible = false; capDrop.key = ""; capDrop.openT = 0
        }
    }

    // IPC panel barTip КЛЮЧ: открыть каплю без наведения (проверка); windows — список окон; "" — закрыть
    function showTip(key) {
        if (key === "") { capDrop.hide(); return "closed" }
        if (key === "windows") { if (!bar.winTitleItem) return Tr.t("нет капсулы ") + key; toggleWindows(bar.winTitleItem, false); return "ok" }
        function find(it) {
            if (it.tipKey === key && it.visible) return it
            for (var ch of it.children) { var r = find(ch); if (r) return r }
            return null
        }
        var t = find(leftCap) || find(rightCap)
        if (!t) return Tr.t("нет капсулы ") + key
        var cap = capOf(t)
        tipTarget = t; tipItem = t
        capDrop.show(key, bar, cap, t.mapToItem(cap, t.width / 2, 0).x, 250, false)
        return "ok"
    }
    function toggleWindows(from, grab) {   // grab: false — из IPC (захват попапа только после ввода)
        if (capDrop.key === "windows") { capDrop.hide(); return }
        tipDelay.stop()
        // капсула узкая (мало места под список) — прежний раздел «Окна» в панели
        var cap = capOf(from)
        if (!from.visible || !cap || !capDrop.show("windows", bar, cap, from.mapToItem(cap, from.width / 2, 0).x, 300, grab !== false))
            openPlugin("windows")
    }
    // окна: сначала текущего рабочего стола, потом остальных (по номеру стола)
    readonly property var winList: {
        var ws = {}, cur = null
        for (var w of workspaces) { ws[w.id] = w.idx; if (w.is_focused) cur = w.id }
        var out = []
        for (var id in windows) out.push(windows[id])
        out.sort((a, b) => {
            var ca = a.workspace_id === cur ? 0 : 1, cb = b.workspace_id === cur ? 0 : 1
            if (ca !== cb) return ca - cb
            return (ws[a.workspace_id] || 0) - (ws[b.workspace_id] || 0) || a.id - b.id
        })
        return out.map(w => ({ id: w.id, title: w.title || w.app_id, app: w.app_id,
                               ws: ws[w.workspace_id] || 0, here: w.workspace_id === cur, focused: w.id === focusedId }))
    }

    // процессы для подсказок ЦП и памяти — только пока они открыты
    property var topProcs: []
    Process {
        running: capDrop.key === "cpu" || capDrop.key === "mem"
        command: ["python3", "-I", Quickshell.shellDir + "/plugins/processes/tm.py", "1"]
        stdout: SplitParser {
            onRead: (line) => { try { bar.topProcs = JSON.parse(line).procs || [] } catch (e) {} }
        }
        onRunningChanged: if (!running) bar.topProcs = []
    }
    function topBy(i, n) { return topProcs.slice().sort((a, b) => b[i] - a[i]).slice(0, n) }
    function dur(sec) {
        if (!sec || sec <= 0) return ""
        var h = Math.floor(sec / 3600), m = Math.round(sec % 3600 / 60)
        return h ? h + Tr.t(" ч ") + m + Tr.t(" мин") : m + Tr.t(" мин")
    }
    // последние тексты из истории буфера — читаются при открытии подсказки
    property var clipTop: []
    FileView {
        id: clipFile
        path: capDrop.key === "clipboard" ? (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/glide-shell/clipboard.json" : ""
        printErrors: false
        onLoaded: {
            try { bar.clipTop = JSON.parse(text()).slice(0, 3).map(x => typeof x === "string" ? x : Tr.t("🖼 картинка")) } catch (e) { bar.clipTop = [] }
        }
    }

    CapsuleDrop {
        id: capDrop
        contentH: tipLoader.item ? tipLoader.item.implicitHeight : 0
        Loader {
            id: tipLoader
            width: parent.width
            sourceComponent: ({ windows: winTip, cpu: procTip, mem: procTip, battery: battTip, layout: layoutTip,
                                clipboard: clipTip, notifications: notifTip, phone: phoneTip, tray: trayTip, vpn: vpnTip, updates: updatesTip })[capDrop.key] || simpleTip
        }
    }

    // ---- содержимое капель ----
    component TipTitle: Text {
        width: parent ? parent.width : 200
        color: Theme.text; font.pixelSize: Theme.fs(13); font.weight: Font.DemiBold
        elide: Text.ElideRight
    }
    component TipLine: Text {
        width: parent ? parent.width : 200
        color: Theme.textSecondary; font.pixelSize: Theme.fs(12)
        elide: Text.ElideRight
    }
    component TipHint: Text {
        width: parent ? parent.width : 200
        color: Theme.textMuted; font.pixelSize: Theme.fs(11)
        wrapMode: Text.WordWrap
    }
    component TipRow: Item {   // «имя ………… значение»
        property string name
        property string value
        property color tint: Theme.textVariant
        width: parent ? parent.width : 200
        height: 20
        Text { width: parent.width - val.width - 8; anchors.verticalCenter: parent.verticalCenter; text: parent.name
               color: Theme.textVariant; font.pixelSize: Theme.fs(12); elide: Text.ElideRight }
        Text { id: val; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; text: parent.value
               color: parent.tint; font.pixelSize: Theme.fs(12); font.features: ({ "tnum": 1 }) }
    }

    Component {
        id: simpleTip
        Column {
            spacing: 2
            TipTitle {
                text: ({ power: Tr.t("Питание"), awake: Tr.t("«Не засыпать» включено"), control: Tr.t("Центр управления") })[capDrop.key] || ""
            }
            TipHint {
                text: ({ power: Tr.t("Выключение, перезагрузка, сон, выход"),
                         awake: Tr.t("Экран не гаснет и не блокируется. Щелчок — выключить"),
                         control: Tr.t("Wi-Fi, Bluetooth, звук, яркость, режим питания") })[capDrop.key] || ""
            }
        }
    }
    Component {
        id: procTip
        Column {
            spacing: 3
            readonly property bool isCpu: capDrop.key === "cpu"
            TipTitle { text: parent.isCpu ? Tr.t("Процессор · ") + Math.round(bar.cpu) + "%" : Tr.t("Память · ") + Math.round(bar.mem) + "%" }
            TipLine { visible: bar.topProcs.length === 0; text: Tr.t("Считаю процессы…") }
            Repeater {
                model: bar.topBy(parent.isCpu ? 2 : 3, 4)
                delegate: TipRow {
                    required property var modelData
                    name: modelData[1]
                    value: capDrop.key === "cpu" ? Tr.num(modelData[2], 1) + "%"
                         : modelData[3] >= 1024 ? Tr.num((modelData[3] / 1024), 1) + Tr.t(" ГБ") : Math.round(modelData[3]) + Tr.t(" МБ")
                }
            }
            TipHint { text: Tr.t("Щелчок — диспетчер задач") }
        }
    }
    Component {
        id: battTip
        Column {
            spacing: 3
            TipTitle {
                text: Tr.t("Батарея · ") + Math.round(bar.battPct) + "%"
                      + (bar.batt && bar.batt.state === UPowerDeviceState.FullyCharged ? Tr.t(" · заряжена")
                         : bar.charging ? Tr.t(" · заряжается") : Tr.t(" · от батареи"))
            }
            TipRow {
                visible: value !== ""
                name: bar.charging ? Tr.t("До полной") : Tr.t("Осталось")
                value: bar.batt ? bar.dur(bar.charging ? bar.batt.timeToFull : bar.batt.timeToEmpty) : ""
            }
            TipRow {
                visible: !!bar.batt && Math.abs(bar.batt.changeRate) > 0.05
                name: bar.charging ? Tr.t("Мощность заряда") : Tr.t("Расход")
                value: bar.batt ? Tr.num(Math.abs(bar.batt.changeRate), 1) + Tr.t(" Вт") : ""
            }
            TipRow {
                visible: !!bar.batt && bar.batt.healthSupported
                name: Tr.t("Здоровье")
                value: bar.batt && bar.batt.healthSupported ? Math.round(bar.batt.healthPercentage) + "%" : ""
            }
        }
    }
    Component {
        id: layoutTip
        Column {
            spacing: 2
            TipTitle { text: Tr.t("Раскладка") }
            Repeater {
                model: bar.layouts
                delegate: TipRow {
                    required property var modelData
                    required property int index
                    name: modelData
                    value: index === bar.layoutIdx ? "●" : ""
                    tint: Prefs.accent
                }
            }
            TipHint { text: Tr.t("Щелчок — следующая") + (bar.p.capsLock ? Tr.t(" · Caps Lock включён") : "") }
        }
    }
    Component {
        id: clipTip
        Column {
            spacing: 3
            Component.onCompleted: clipFile.reload()
            TipTitle { text: Tr.t("Буфер обмена") }
            Repeater {
                model: bar.clipTop
                delegate: TipLine { required property var modelData; text: modelData.replace(/\s+/g, " ") }
            }
            TipHint { text: bar.clipTop.length ? Tr.t("Щелчок — вся история") : Tr.t("История пуста") }
        }
    }
    Component {
        id: notifTip
        Column {
            spacing: 3
            readonly property var last: Notifs.active && Notifs.list.length ? Notifs.list[0] : null
            TipTitle {
                text: !Notifs.active ? Tr.t("Уведомления") : Notifs.unread > 0 ? Tr.t("Непрочитанных: ") + Notifs.unread : Tr.t("Новых уведомлений нет")
            }
            TipLine { visible: !!parent.last; text: parent.last ? (parent.last.appName ? parent.last.appName + ": " : "") + parent.last.summary : "" }
            TipHint { text: (bar.dnd ? Tr.t("«Не беспокоить» включено. ") : "") + Tr.t("Щелчок — история, правый — «не беспокоить»") }
        }
    }
    Component {
        id: phoneTip
        Column {
            spacing: 3
            readonly property var ph: KdeConnect.phone
            TipTitle { text: parent.ph ? parent.ph.name : Tr.t("Телефон") }
            TipRow {
                name: Tr.t("Заряд")
                value: parent.ph && parent.ph.battery !== undefined ? parent.ph.battery + "%" + (parent.ph.charging ? Tr.t(" · заряжается") : "") : "—"
            }
            TipHint { text: Tr.t("Щелчок — файлы, буфер, звонок телефону") }
        }
    }
    Component {
        id: updatesTip
        Column {
            spacing: 3
            readonly property var all: ArchUpdates.repo.concat(ArchUpdates.aur.map(x => Object.assign({ aur: true }, x)))
            TipTitle { text: Tr.t("Обновления: ") + ArchUpdates.count }
            Repeater {
                model: parent.all.slice(0, 8)
                delegate: TipRow {
                    required property var modelData
                    name: modelData.name + (modelData.aur ? "  AUR" : "")
                    value: modelData.to
                    tint: Theme.textVariant
                }
            }
            TipLine { visible: parent.all.length > 8; text: Tr.t("…и ещё ") + (parent.all.length - 8) }
            TipHint { text: Tr.t("Щелчок — обновить в терминале") }
        }
    }
    Component {
        id: vpnTip
        Column {
            spacing: 3
            TipTitle { text: Vpn.on ? Tr.t("VPN включён") : Tr.t("VPN выключен") }
            Repeater {
                model: Vpn.tunnels
                delegate: TipRow {
                    required property var modelData
                    name: modelData.name
                    value: modelData.addr + (modelData.lan ? Tr.t(" · сеть") : "")
                    tint: modelData.lan ? Theme.textVariant : Theme.success
                }
            }
        }
    }
    Component {
        id: trayTip
        Column {
            spacing: 2
            readonly property var it: bar.tipItem && bar.tipItem.modelData ? bar.tipItem.modelData : null
            TipTitle { text: parent.it ? (parent.it.tooltipTitle || parent.it.title || parent.it.id) : "" }
            TipLine {
                visible: text !== ""
                text: parent.it ? (parent.it.tooltipDescription || "").replace(/<[^>]*>/g, "") : ""
                wrapMode: Text.WordWrap; maximumLineCount: 3
            }
            TipHint { text: Tr.t("Щелчок — открыть, правый — меню") }
        }
    }
    Component {
        id: winTip
        Column {
            spacing: 1
            TipTitle { text: Tr.t("Окна"); bottomPadding: 4 }
            Repeater {
                model: bar.winList.slice(0, 10)
                delegate: Rectangle {
                    id: wr
                    required property var modelData
                    width: parent ? parent.width : 260
                    height: 30
                    radius: Theme.radiusSm
                    color: wrMa.pressed ? Theme.surfaceHigher : wrMa.containsMouse ? Theme.surfaceHigh
                         : wr.modelData.focused ? Prefs.accentSoft : "transparent"
                    Behavior on color { ColorAnimation { duration: Prefs.ms(120) } }
                    IconImage {
                        x: 6; anchors.verticalCenter: parent.verticalCenter
                        implicitSize: 16
                        source: bar.iconFor(wr.modelData.app)
                    }
                    Text {
                        x: 30; width: parent.width - x - wsNum.width - 12
                        anchors.verticalCenter: parent.verticalCenter
                        text: wr.modelData.title
                        color: wr.modelData.here ? Theme.text : Theme.textSecondary
                        font.pixelSize: Theme.fs(12); elide: Text.ElideRight
                    }
                    Text {
                        id: wsNum
                        anchors.right: parent.right; anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        text: wr.modelData.here ? "" : String(wr.modelData.ws)
                        color: Theme.textMuted; font.pixelSize: Theme.fs(11)
                    }
                    MouseArea {
                        id: wrMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                        onClicked: (m) => {
                            if (m.button === Qt.MiddleButton) { Niri.closeWindow(wr.modelData.id); return }
                            Niri.focusWindow(wr.modelData.id)
                            capDrop.hide()
                        }
                    }
                }
            }
            TipHint {
                topPadding: 4
                text: (bar.winList.length > 10 ? Tr.t("Ещё ") + (bar.winList.length - 10) + " · " : "") + Tr.t("средняя кнопка — закрыть окно")
            }
        }
    }
    // IPC panel trayMenu ID: меню значка трея (без ID или с чужим — вернуть список значков)
    function openTrayMenu(id) {
        var trayRep = bar.trayRepItem
        for (var i = 0; trayRep && i < trayRep.count; i++) {
            var t = trayRep.itemAt(i)
            if (t && t.modelData.id === id && t.modelData.hasMenu) {
                var pt = t.mapToItem(null, t.width, t.height + 8)
                trayMenu.openFor(t.modelData, bar, pt.x, pt.y, false, capOf(t))
                return "ok"
            }
        }
        if (id === "" && trayMenu.visible) { trayMenu.close(); return "closed" }
        return SystemTray.items.values.filter(x => x.hasMenu).map(x => x.id).join(" ")
    }
}
