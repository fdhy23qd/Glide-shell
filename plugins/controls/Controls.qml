import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower
import Quickshell.Bluetooth
import qs

// Центр управления: плитки (Wi-Fi, Bluetooth, «не беспокоить», «не засыпать»), ползунки
// громкости, микрофона и яркости, выбор выхода звука, батарея и профиль питания.
// «Не засыпать» ведёт ядро; «не беспокоить» — свои уведомления или, пока они выключены, DMS.
ColumnLayout {
    id: cc
    property var api
    readonly property color accent: api && api.accent ? api.accent : Theme.accent   // акцент из настроек панели
    readonly property color accentText: api && api.accentText ? api.accentText : Theme.accentText   // текст на акценте
    readonly property bool shown: api ? api.shown : false
    spacing: 10

    function nf(code) { return String.fromCodePoint(code) }
    function run(argv) { if (api) api.run(argv, "") }
    function refresh() { wifiProc.running = true; brProc.running = true }
    onShownChanged: if (shown) { refresh(); if (!NightLight.available) NightLight.recheck() }
    Component.onCompleted: refresh()

    // ---------- состояние ----------
    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var source: Pipewire.defaultAudioSource
    readonly property var sinks: Pipewire.nodes.values.filter(n => n.isSink && !n.isStream && n.audio)
    PwObjectTracker { objects: cc.sinks.concat(cc.source ? [cc.source] : []) }

    property bool wifiOn: false
    property string wifiName: ""
    property bool wired: false
    Process {
        id: wifiProc
        command: ["sh", "-c", "nmcli radio wifi; nmcli -t -f TYPE,STATE,CONNECTION device"]
        stdout: StdioCollector {
            onStreamFinished: {
                var l = text.trim().split("\n")   // радио, затем устройства «тип:состояние:соединение»
                cc.wifiOn = (l[0] || "").trim() === "enabled"
                var name = "", wired = false
                for (var i = 1; i < l.length; i++) {
                    var f = cc.fields(l[i])
                    if (f[0] === "wifi" && f[1] === "connected" && !name) name = f[2] || ""
                    if (f[0] === "ethernet" && f[1] === "connected") wired = true
                }
                cc.wifiName = name
                cc.wired = wired
            }
        }
    }
    function fields(line) {   // nmcli -t: «:» внутри значения экранирован как «\:», «\» — как «\\»
        var out = [""], esc = false
        for (var c of line) {
            if (esc) { out[out.length - 1] += c; esc = false }
            else if (c === "\\") esc = true
            else if (c === ":") out.push("")
            else out[out.length - 1] += c
        }
        return out
    }
    function toggleWifi() {
        wifiOn = !wifiOn
        run(["nmcli", "radio", "wifi", wifiOn ? "on" : "off"])
        wifiLater.restart()
    }
    Timer { id: wifiLater; interval: 2500; onTriggered: wifiProc.running = true }

    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property bool btOn: !!adapter && adapter.enabled
    readonly property var btDevices: Bluetooth.devices.values.filter(d => d.paired)
    readonly property string btConnected: btDevices.filter(d => d.connected).map(d => d.name).join(", ")

    // «не беспокоить»: свои уведомления (api.notifs) или, пока они выключены, DMS
    readonly property var notifs: api && api.notifs && api.notifs.active ? api.notifs : null
    property bool dmsDnd: false
    readonly property bool dnd: notifs ? notifs.dnd : dmsDnd
    function toggleDnd() {
        if (notifs) notifs.setDnd(!notifs.dnd)
        else { dmsDnd = !dmsDnd; run(["dms", "ipc", "call", "notifications", "toggleDoNotDisturb"]) }
    }
    FileView {
        path: cc.notifs ? "" : (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/DankMaterialShell/session.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: { try { cc.dmsDnd = JSON.parse(text()).doNotDisturb === true } catch (e) {} }
    }

    readonly property bool inhibit: !!api && !!api.awake   // «не засыпать» ведёт ядро Glide Shell

    // яркость через logind: без root и без brightnessctl
    property string brDev: ""
    property int brMax: 0
    property int br: 0
    Process {
        id: brProc
        command: ["sh", "-c", "for d in /sys/class/backlight/*; do [ -e \"$d/brightness\" ] && echo \"${d##*/} $(cat \"$d/brightness\") $(cat \"$d/max_brightness\")\" && break; done"]
        stdout: StdioCollector {
            onStreamFinished: {
                var a = text.trim().split(/\s+/)
                if (a.length < 3) return
                cc.brDev = a[0]; cc.br = +a[1]; cc.brMax = +a[2]
            }
        }
    }
    property int brPending: -1
    function setBrightness(frac) {
        br = Math.max(1, Math.round(frac * brMax))
        brPending = br
        if (!brThrottle.running) brThrottle.start()
    }
    Timer {   // ползунок тянут быстро — не чаще раза в 60 мс
        id: brThrottle
        interval: 60
        onTriggered: {
            if (cc.brPending < 0) return
            cc.run(["busctl", "call", "org.freedesktop.login1", "/org/freedesktop/login1/session/auto",
                    "org.freedesktop.login1.Session", "SetBrightness", "ssu", "backlight", cc.brDev, String(cc.brPending)])
            cc.brPending = -1
        }
    }

    readonly property var batt: UPower.displayDevice
    readonly property bool hasBatt: !!batt && batt.isLaptopBattery
    function fmtTime(s) {
        if (!s || s <= 0) return ""
        var h = Math.floor(s / 3600), m = Math.round((s % 3600) / 60)
        return h > 0 ? h + Tr.t(" ч ") + m + Tr.t(" мин") : m + Tr.t(" мин")
    }
    readonly property string battText: {
        if (!hasBatt) return ""
        var pct = Math.round(batt.percentage * 100) + "%"
        switch (batt.state) {
        case UPowerDeviceState.Charging: return pct + Tr.t(" · заряжается") + (batt.timeToFull > 0 ? Tr.t(", ещё ") + fmtTime(batt.timeToFull) : "")
        case UPowerDeviceState.FullyCharged: return pct + Tr.t(" · заряжена")
        case UPowerDeviceState.Discharging: return pct + (batt.timeToEmpty > 0 ? Tr.t(" · осталось ") + fmtTime(batt.timeToEmpty) : "")
        }
        return pct
    }

    // ---------- элементы ----------
    component Tile: Rectangle {
        id: t
        property string glyph
        property string title
        property string sub
        property bool on
        property color accent: Theme.accent
        property color accentText: Theme.accentText
        signal clicked()
        Layout.fillWidth: true
        Layout.preferredWidth: 1
        implicitHeight: 54
        radius: Theme.r(16)
        color: on ? (tm.containsMouse ? Qt.lighter(t.accent, 1.12) : t.accent) : (tm.containsMouse ? Theme.surfaceHigh : Theme.surface)
        scale: tm.pressed ? 0.95 : 1
        Behavior on color { ColorAnimation { duration: Prefs.ms(180) } }
        Behavior on scale { NumberAnimation { duration: Prefs.ms(160); easing.type: Easing.OutBack } }
        Text {
            x: 12
            anchors.verticalCenter: parent.verticalCenter
            text: t.glyph
            color: t.on ? accentText : Theme.textVariant
            font.family: Prefs.iconFont
            font.pixelSize: Theme.fs(20)
            Behavior on color { ColorAnimation { duration: Prefs.ms(180) } }
        }
        Column {
            x: 42
            width: parent.width - 50
            anchors.verticalCenter: parent.verticalCenter
            spacing: 1
            Text {
                Behavior on color { ColorAnimation { duration: Prefs.ms(140) } }
                width: parent.width
                text: t.title
                color: t.on ? accentText : Theme.text
                font.pixelSize: Theme.fs(12); font.bold: true
                elide: Text.ElideRight
            }
            Text {
                Behavior on color { ColorAnimation { duration: Prefs.ms(140) } }
                width: parent.width
                visible: text !== ""
                text: t.sub
                color: t.on ? accentText : Theme.textSecondary
                font.pixelSize: Theme.fs(11)
                elide: Text.ElideRight
            }
        }
        MouseArea { id: tm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: t.clicked() }
    }

    component Slider: Item {
        id: s
        property real value: 0          // 0..1
        property string glyph
        property bool muted: false
        property color accent: Theme.accent
        property color accentText: Theme.accentText
        signal moved(real v)
        signal glyphClicked()
        Layout.fillWidth: true
        implicitHeight: 34
        Rectangle {
            anchors.fill: parent
            radius: Theme.r(17)
            color: drag.containsMouse || drag.pressed ? Theme.surfaceHigh : Theme.surface
            Behavior on color { ColorAnimation { duration: Prefs.ms(120) } }
            Rectangle {
                height: parent.height
                radius: Theme.r(17)
                width: Math.max(height, parent.width * Math.min(1, s.value))
                color: s.muted ? Theme.divider : drag.pressed ? Qt.lighter(s.accent, 1.15) : s.accent
                Behavior on width { enabled: !drag.sliding; NumberAnimation { duration: Prefs.ms(220); easing.type: Easing.OutCubic } }
                Behavior on color { ColorAnimation { duration: Prefs.ms(160) } }
            }
        }
        MouseArea {   // перетаскивание и колесо
            id: drag
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            function at(x) { s.moved(Math.max(0, Math.min(1, x / width))) }
            // щелчок — заливка плавно доезжает до места; перетаскивание — идёт за курсором без задержки
            property bool sliding: false
            property real pressX: 0
            onPressed: (m) => { sliding = false; pressX = m.x; at(m.x) }
            onPositionChanged: (m) => { if (!pressed) return; if (Math.abs(m.x - pressX) > 3) sliding = true; if (sliding) at(m.x) }
            onReleased: sliding = false
            onCanceled: sliding = false
            onWheel: (w) => s.moved(Math.max(0, Math.min(1, s.value + (w.angleDelta.y > 0 ? 0.05 : -0.05))))
        }
        Rectangle {   // значок: клик — выключить/включить
            Behavior on color { ColorAnimation { duration: Prefs.ms(140) } }
            width: 34; height: 34; radius: Theme.r(17)
            color: gm.pressed ? Qt.rgba(Theme.background.r, Theme.background.g, Theme.background.b, 0.22) : gm.containsMouse ? Qt.rgba(Theme.background.r, Theme.background.g, Theme.background.b, 0.125) : "transparent"
            scale: gm.pressed ? 0.88 : 1
            Behavior on scale { NumberAnimation { duration: Prefs.ms(140); easing.type: Easing.OutBack } }
            Text {
                anchors.centerIn: parent
                text: s.glyph
                color: accentText
                font.family: Prefs.iconFont
                font.pixelSize: Theme.fs(17)
            }
            MouseArea { id: gm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: s.glyphClicked() }
        }
        Text {
            Behavior on color { ColorAnimation { duration: Prefs.ms(140) } }
            anchors.right: parent.right; anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            text: Math.round(s.value * 100) + "%"
            color: s.value > 0.88 ? accentText : Theme.textSecondary
            font.pixelSize: Theme.fs(11)
            font.features: ({ "tnum": 1 })
        }
    }

    component Chip: Rectangle {
        id: ch
        property string text
        property bool on
        property color accent: Theme.accent
        property color accentText: Theme.accentText
        signal clicked()
        width: Math.min(chT.implicitWidth + 22, 240)
        height: 28
        radius: Theme.r(14)
        color: on ? Qt.rgba(accent.r, accent.g, accent.b, chm.containsMouse ? 0.32 : 0.22)
                  : (chm.pressed ? Theme.surfaceHigher : chm.containsMouse ? Theme.surfaceHigh : Theme.surface)
        border.color: on ? accent : "transparent"
        scale: chm.pressed ? 0.95 : 1
        Behavior on color { ColorAnimation { duration: Prefs.ms(140) } }
        Behavior on scale { NumberAnimation { duration: Prefs.ms(140); easing.type: Easing.OutBack } }
        Text {
            id: chT
            Behavior on color { ColorAnimation { duration: Prefs.ms(140) } }
            anchors.centerIn: parent
            width: Math.min(implicitWidth, 218)
            text: ch.text
            color: ch.on ? Theme.text : Theme.textVariant
            font.pixelSize: Theme.fs(12)
            elide: Text.ElideRight
        }
        MouseArea { id: chm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: ch.clicked() }
    }

    // ---------- время, дата и погода (щелчок — «Сегодня»: календарь и прогноз) ----------
    // свои часы: идут, только пока панель открыта; при открытии сразу сверяются (после сна таймеры отстают)
    property date now: new Date()
    readonly property bool secs: Prefs.clockSeconds
    function tick() { now = new Date() }
    Timer {
        id: clock
        running: cc.shown
        repeat: true
        interval: 1000
        onTriggered: {
            cc.tick()
            interval = cc.secs ? 1000 : 60000 - cc.now.getSeconds() * 1000 - cc.now.getMilliseconds() + 20
        }
        onRunningChanged: if (running) { cc.tick(); interval = 1000 }   // через секунду встанет на границу минуты
    }
    readonly property var wx: api && api.weather && api.weather.ok ? api.weather : null
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: 70
        radius: Theme.r(18)
        color: hdrMa.pressed ? Theme.surfacePressed : hdrMa.containsMouse ? Theme.surfaceHigh : Theme.surface
        scale: hdrMa.pressed ? 0.98 : 1
        Behavior on color { ColorAnimation { duration: Prefs.ms(140) } }
        Behavior on scale { NumberAnimation { duration: Prefs.ms(140); easing.type: Easing.OutBack } }
        Column {
            x: 16
            anchors.verticalCenter: parent.verticalCenter
            spacing: 0
            Text {
                text: Qt.formatTime(cc.now, cc.secs ? "HH:mm:ss" : "HH:mm")
                color: Theme.text
                font.pixelSize: Theme.fs(30); font.weight: Font.DemiBold
                font.features: ({ "tnum": 1 })
            }
            Text {
                text: { var s = Tr.locale.toString(cc.now, "dddd, d MMMM"); return s.charAt(0).toUpperCase() + s.slice(1) }
                color: Theme.textSecondary
                font.pixelSize: Theme.fs(12)
            }
        }
        Row {   // погода справа
            visible: !!cc.wx
            anchors.right: parent.right; anchors.rightMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            spacing: 10
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: cc.wx ? cc.wx.icon(cc.wx.data.now.code, cc.wx.data.now.day) : ""
                color: cc.accent
                font.family: Prefs.iconFont; font.pixelSize: Theme.fs(26)
            }
            Column {
                anchors.verticalCenter: parent.verticalCenter
                Text {
                    anchors.right: parent.right
                    text: cc.wx ? cc.wx.temp(cc.wx.data.now.temp) : ""
                    color: Theme.text
                    font.pixelSize: Theme.fs(18); font.weight: Font.DemiBold
                }
                Text {
                    anchors.right: parent.right
                    text: cc.wx ? cc.wx.describe(cc.wx.data.now.code) : ""
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fs(11)
                }
            }
        }
        MouseArea {
            id: hdrMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: if (cc.api) cc.api.openCategory("today")
        }
    }

    // ---------- плитки ----------
    GridLayout {
        Layout.fillWidth: true
        columns: 2
        columnSpacing: 8
        rowSpacing: 8
        Tile {
            accent: cc.accent; accentText: cc.accentText
            glyph: cc.wifiOn ? cc.nf(0xF05A9) : cc.nf(0xF05AA)
            title: "Wi-Fi"
            sub: (!cc.wifiOn ? Tr.t("выкл") : (cc.wifiName || Tr.t("не подключено"))) + (cc.wired ? Tr.t(" · кабель") : "")
            on: cc.wifiOn
            onClicked: cc.toggleWifi()
        }
        Tile {
            accent: cc.accent; accentText: cc.accentText
            glyph: cc.btOn ? (cc.btConnected ? cc.nf(0xF00B1) : cc.nf(0xF00AF)) : cc.nf(0xF00B2)
            title: "Bluetooth"
            sub: !cc.adapter ? Tr.t("нет адаптера") : !cc.btOn ? Tr.t("выкл") : (cc.btConnected || Tr.t("вкл"))
            on: cc.btOn
            onClicked: {
                if (!cc.adapter) return
                if (cc.btOn) cc.adapter.enabled = false
                else if (cc.adapter.state === BluetoothAdapterState.Blocked) { cc.run(["rfkill", "unblock", "bluetooth"]); btPowerOn.restart() }
                else cc.adapter.enabled = true
            }
            Timer { id: btPowerOn; interval: 600; onTriggered: if (cc.adapter) cc.adapter.enabled = true }
        }
        Tile {
            accent: cc.accent; accentText: cc.accentText
            readonly property bool auto: !!cc.notifs && cc.notifs.quiet && !cc.notifs.dnd   // ночь или демонстрация
            glyph: cc.dnd || auto ? cc.nf(0xF009B) : cc.nf(0xF009A)
            title: Tr.t("Не беспокоить")
            sub: cc.dnd ? Tr.t("вкл") : auto ? cc.notifs.quietReason : Tr.t("выкл")
            on: cc.dnd
            onClicked: cc.toggleDnd()
        }
        Tile {
            accent: cc.accent; accentText: cc.accentText
            glyph: cc.inhibit ? cc.nf(0xF0176) : cc.nf(0xF06CA)
            title: Tr.t("Не засыпать")
            sub: cc.inhibit ? Tr.t("экран не гаснет") : Tr.t("выкл")
            on: cc.inhibit
            onClicked: if (cc.api) cc.api.setAwake(!cc.inhibit)
        }
        Tile {
            accent: cc.accent; accentText: cc.accentText
            Layout.columnSpan: 2
            glyph: NightLight.on ? cc.nf(0xF0594) : cc.nf(0xF0F67)
            title: Tr.t("Ночной свет")
            sub: !NightLight.available ? Tr.t("нужен wlsunset")
                 : Prefs.night === "on" ? Tr.t("вкл · ") + Prefs.nightTemp + " K"
                 : Prefs.night === "auto" ? Tr.t("с ") + NightLight.sunset + Tr.t(" до ") + NightLight.sunrise
                 : Tr.t("выкл")
            on: NightLight.on && NightLight.available
            onClicked: NightLight.toggle()
            Connections {
                target: NightLight
                function onMissing() { if (cc.api) cc.api.flash(Tr.t("Установи wlsunset: sudo pacman -S wlsunset")) }
            }
        }
    }

    // ---------- ползунки ----------
    Slider {
        accent: cc.accent; accentText: cc.accentText
        visible: !!cc.sink && !!cc.sink.audio
        glyph: !cc.sink || !cc.sink.audio || cc.sink.audio.muted ? cc.nf(0xF0581)
               : cc.sink.audio.volume > 0.66 ? cc.nf(0xF057E) : cc.sink.audio.volume > 0.33 ? cc.nf(0xF0580) : cc.nf(0xF057F)
        value: cc.sink && cc.sink.audio ? cc.sink.audio.volume : 0
        muted: !!cc.sink && !!cc.sink.audio && cc.sink.audio.muted
        onMoved: (v) => { cc.sink.audio.volume = v; if (cc.sink.audio.muted && v > 0) cc.sink.audio.muted = false }
        onGlyphClicked: cc.sink.audio.muted = !cc.sink.audio.muted
    }
    Slider {
        accent: cc.accent; accentText: cc.accentText
        visible: !!cc.source && !!cc.source.audio
        glyph: cc.source && cc.source.audio && cc.source.audio.muted ? cc.nf(0xF036D) : cc.nf(0xF036C)
        value: cc.source && cc.source.audio ? cc.source.audio.volume : 0
        muted: !!cc.source && !!cc.source.audio && cc.source.audio.muted
        onMoved: (v) => { cc.source.audio.volume = v; if (cc.source.audio.muted && v > 0) cc.source.audio.muted = false }
        onGlyphClicked: cc.source.audio.muted = !cc.source.audio.muted
    }
    Slider {
        accent: cc.accent; accentText: cc.accentText
        visible: cc.brMax > 0
        glyph: cc.nf(0xF00DF)
        value: cc.brMax > 0 ? cc.br / cc.brMax : 0
        onMoved: (v) => cc.setBrightness(v)
        onGlyphClicked: cc.setBrightness(cc.br / cc.brMax > 0.5 ? 0.25 : 1)
    }

    // ---------- выход звука ----------
    Text {
        visible: cc.sinks.length > 1
        text: Tr.t("Выход звука")
        color: Theme.textSecondary; font.pixelSize: Theme.fs(11); font.bold: true
        Layout.topMargin: 2
    }
    Flow {
        visible: cc.sinks.length > 1
        Layout.fillWidth: true
        spacing: 6
        Repeater {
            model: cc.sinks
            delegate: Chip {
                accent: cc.accent; accentText: cc.accentText
                required property var modelData
                text: modelData.description || modelData.nickname || modelData.name
                on: modelData === cc.sink
                onClicked: Pipewire.preferredDefaultAudioSink = modelData
            }
        }
    }

    // ---------- батарея и профиль питания ----------
    RowLayout {
        visible: cc.hasBatt
        Layout.fillWidth: true
        Layout.topMargin: 2
        spacing: 8
        Text {
            text: cc.batt && cc.batt.state === UPowerDeviceState.Charging ? cc.nf(0xF0084) : cc.nf(0xF0079)
            color: cc.batt && cc.batt.state === UPowerDeviceState.Charging ? Theme.success : Theme.textVariant
            font.family: Prefs.iconFont
            font.pixelSize: Theme.fs(16)
        }
        Text {
            Layout.fillWidth: true
            text: cc.battText
            color: Theme.text; font.pixelSize: Theme.fs(12)
            elide: Text.ElideRight
        }
    }
    Rectangle {   // профиль питания: переезжающая плашка
        id: prof
        readonly property var opts: PowerProfiles.hasPerformanceProfile
            ? [PowerProfile.PowerSaver, PowerProfile.Balanced, PowerProfile.Performance]
            : [PowerProfile.PowerSaver, PowerProfile.Balanced]
        readonly property var labels: [Tr.t("Экономия"), Tr.t("Баланс"), Tr.t("Мощность")]
        readonly property var glyphs: [0xF032A, 0xF05D1, 0xF04C5]
        readonly property int idx: opts.indexOf(PowerProfiles.profile)
        readonly property real cell: (width - 4) / opts.length
        Layout.fillWidth: true
        implicitHeight: 32
        radius: Theme.r(16)
        color: Theme.surface
        Rectangle {
            visible: prof.idx >= 0
            x: 2 + prof.idx * prof.cell
            y: 2
            width: prof.cell
            height: parent.height - 4
            radius: Theme.r(14)
            color: cc.accent
            Behavior on x { NumberAnimation { duration: Prefs.ms(260); easing.type: Easing.OutBack; easing.overshoot: 1.1 } }
        }
        Row {
            x: 2
            anchors.verticalCenter: parent.verticalCenter
            Repeater {
                model: prof.opts.length
                delegate: Item {
                    required property int index
                    width: prof.cell
                    height: 28
                    Rectangle {   // наведение на невыбранный режим
                        anchors.fill: parent
                        radius: Theme.r(14)
                        visible: index !== prof.idx
                        color: profMa.pressed ? Theme.surfaceHigher : profMa.containsMouse ? Theme.surfaceHigh : "transparent"
                        Behavior on color { ColorAnimation { duration: Prefs.ms(120) } }
                    }
                    Row {
                        scale: profMa.pressed ? 0.92 : 1
                        Behavior on scale { NumberAnimation { duration: Prefs.ms(140); easing.type: Easing.OutBack } }
                        anchors.centerIn: parent
                        spacing: 5
                        Text {
                            Behavior on color { ColorAnimation { duration: Prefs.ms(140) } }
                            anchors.verticalCenter: parent.verticalCenter
                            text: cc.nf(prof.glyphs[index])
                            font.family: Prefs.iconFont; font.pixelSize: Theme.fs(13)
                            color: index === prof.idx ? accentText : Theme.textVariant
                        }
                        Text {
                            Behavior on color { ColorAnimation { duration: Prefs.ms(140) } }
                            anchors.verticalCenter: parent.verticalCenter
                            text: prof.labels[index]
                            font.pixelSize: Theme.fs(11)
                            color: index === prof.idx ? accentText : Theme.textVariant
                        }
                    }
                    MouseArea {
                        id: profMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: PowerProfiles.profile = prof.opts[index]
                    }
                }
            }
        }
    }
}
