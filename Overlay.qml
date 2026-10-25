import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.UPower

// Оверлей поверх всего, в том числе полноэкранной игры (слой Overlay у niri — выше полноэкранных окон).
// Открытый — затемнение и карточки (время, система, музыка, быстрые действия, уведомления), забирает клавиатуру;
// Esc или щелчок мимо карточек — закрыть. Закреплённая плашка — строка в углу, мышь проходит сквозь неё.
// Внутрь игры не встраивается (FPS игры не видно — для этого MangoHud). Данные собираются, только пока что-то видно.
Item {
    id: ov
    required property var root
    property bool open: false
    readonly property bool pinned: Prefs.overlayPin
    readonly property bool active: open || pinned

    function toggle() { open = !open }

    // ---------- система: ЦП, память, температура — раз в секунду, только пока видно ----------
    property real cpu: 0
    property real mem: 0
    property real temp: -1
    property var prev: null
    property var buf: []
    function parse(lines) {
        var c = lines[0].trim().split(/\s+/).slice(1).map(Number)
        var idle = c[3] + (c[4] || 0), total = c.reduce((a, b) => a + b, 0)
        if (prev && total > prev.total) cpu = 100 * (1 - (idle - prev.idle) / (total - prev.total))
        prev = { total: total, idle: idle }
        var mt = 0, ma = 0, t = -1
        for (var l of lines) {
            var m = l.match(/^(\w+):\s+(\d+)/)
            if (m && m[1] === "MemTotal") mt = +m[2]
            else if (m && m[1] === "MemAvailable") ma = +m[2]
            else if (/^T \d+$/.test(l)) t = Math.max(t, +l.slice(2) / 1000)
        }
        if (mt) mem = 100 * (1 - ma / mt)
        temp = t
    }
    Process {
        running: ov.active
        // температура — датчик процессора (coretemp, k10temp, zenpower), самый горячий из его входов
        command: ["setpriv", "--pdeathsig", "TERM", "sh", "-c",
                  "for h in /sys/class/hwmon/hwmon*; do case $(cat $h/name 2>/dev/null) in coretemp|k10temp|zenpower) d=$h;; esac; done; " +
                  "while :; do head -1 /proc/stat; grep -E '^(MemTotal|MemAvailable):' /proc/meminfo; " +
                  "[ -n \"$d\" ] && for f in $d/temp*_input; do echo \"T $(cat $f)\"; done; echo .; sleep 1; done"]
        stdout: SplitParser {
            onRead: (line) => {
                if (line !== ".") { ov.buf.push(line); return }
                ov.parse(ov.buf)
                ov.buf = []
            }
        }
        onRunningChanged: if (!running) { ov.prev = null; ov.buf = [] }
    }
    property date now: new Date()
    Timer { running: ov.active; repeat: true; interval: 1000; triggeredOnStart: true; onTriggered: ov.now = new Date() }

    readonly property var battery: UPower.displayDevice && UPower.displayDevice.isLaptopBattery ? UPower.displayDevice : null
    readonly property var player: root.musicPlayer || root.playingPlayer
    readonly property var sink: root.sink && root.sink.audio ? root.sink : null
    function num(v) { return Math.round(v) }

    // ---------- открытый оверлей ----------
    LazyLoader {
        active: ov.open
        PanelWindow {
            id: win
            screen: ov.root.panelScreen
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
            WlrLayershell.namespace: "glide-overlay"
            color: "transparent"

            Rectangle {   // затемнение — появляется плавно, щелчок по нему закрывает
                anchors.fill: parent
                color: Qt.rgba(0, 0, 0, 0.55)
                opacity: grid.opacity
                MouseArea { anchors.fill: parent; onClicked: ov.open = false }
            }
            NumberAnimation { target: grid; property: "opacity"; from: 0; to: 1; duration: Prefs.ms(180); running: true }
            Item { focus: true; Keys.onEscapePressed: ov.open = false; Component.onCompleted: forceActiveFocus() }

            GridLayout {
                id: grid
                anchors.centerIn: parent
                width: Math.min(parent.width - 48, 900)
                columns: width > 640 ? 3 : 2
                columnSpacing: 12; rowSpacing: 12
                scale: 0.97 + 0.03 * opacity

                // ---- сейчас ----
                Card {
                    title: Tr.t("Сейчас")
                    Text { text: Qt.formatTime(ov.now, "HH:mm"); color: Theme.text; font.pixelSize: Theme.fs(44); font.bold: true }
                    Text { text: Tr.date(ov.now, "dddd, d MMMM"); color: Theme.textSecondary; font.pixelSize: Theme.fs(13) }
                    Text {
                        Layout.fillWidth: true
                        visible: !!Niri.focusedWindow
                        text: Niri.focusedWindow ? Niri.titleFor(Niri.focusedWindow) : ""
                        color: Theme.textMuted; font.pixelSize: Theme.fs(12); elide: Text.ElideRight
                    }
                }
                // ---- система ----
                Card {
                    title: Tr.t("Система")
                    Meter { label: Tr.t("ЦП"); value: ov.cpu; text: ov.num(ov.cpu) + "%" }
                    Meter { label: Tr.t("Память"); value: ov.mem; text: ov.num(ov.mem) + "%" }
                    Meter { visible: ov.temp >= 0; label: Tr.t("Температура"); value: ov.temp; text: ov.num(ov.temp) + "°C"; warn: ov.temp >= 85 }
                    Meter {
                        visible: !!ov.battery
                        label: Tr.t("Батарея") + (UPower.onBattery ? "" : " ⚡")
                        value: ov.battery ? ov.battery.percentage * 100 : 0
                        text: ov.battery ? ov.num(ov.battery.percentage * 100) + "%" : ""
                        warn: !!ov.battery && UPower.onBattery && ov.battery.percentage < 0.15
                    }
                }
                // ---- музыка и звук ----
                Card {
                    title: Tr.t("Музыка и звук")
                    Text {
                        Layout.fillWidth: true
                        text: ov.player ? (ov.player.trackTitle || ov.player.identity || "") : Tr.t("Ничего не играет")
                        color: Theme.text; font.pixelSize: Theme.fs(14); font.bold: !!ov.player; elide: Text.ElideRight
                    }
                    Text {
                        Layout.fillWidth: true
                        visible: !!ov.player && !!ov.player.trackArtist
                        text: ov.player ? ov.player.trackArtist || "" : ""
                        color: Theme.textSecondary; font.pixelSize: Theme.fs(12); elide: Text.ElideRight
                    }
                    RowLayout {
                        visible: !!ov.player
                        spacing: 6
                        Btn { glyph: 0xF04AE; onClicked: ov.player.previous(); enabled: !!ov.player && ov.player.canGoPrevious }
                        Btn { glyph: ov.player && ov.player.isPlaying ? 0xF03E4 : 0xF040A; on: true; onClicked: ov.player.togglePlaying() }
                        Btn { glyph: 0xF04AD; onClicked: ov.player.next(); enabled: !!ov.player && ov.player.canGoNext }
                    }
                    RowLayout {
                        visible: !!ov.sink
                        spacing: 6
                        Btn { glyph: ov.sink && ov.sink.audio.muted ? 0xF075F : 0xF057E; onClicked: ov.sink.audio.muted = !ov.sink.audio.muted }
                        Btn { glyph: 0xF0374; onClicked: ov.sink.audio.volume = Math.max(0, ov.sink.audio.volume - 0.05) }
                        Text {
                            Layout.preferredWidth: 44
                            horizontalAlignment: Text.AlignHCenter
                            text: ov.sink ? ov.num(ov.sink.audio.volume * 100) + "%" : ""
                            color: Theme.text; font.pixelSize: Theme.fs(13)
                        }
                        Btn { glyph: 0xF0415; onClicked: ov.sink.audio.volume = Math.min(1, ov.sink.audio.volume + 0.05) }
                    }
                }
                // ---- быстро ----
                Card {
                    title: Tr.t("Быстро")
                    Layout.columnSpan: grid.columns > 2 ? 1 : 2
                    Flow {
                        Layout.fillWidth: true
                        spacing: 6
                        Toggle { glyph: 0xF009B; label: Tr.t("Не беспокоить"); on: Notifs.dnd; onClicked: Notifs.setDnd(!Notifs.dnd) }
                        Toggle { glyph: 0xF0176; label: Tr.t("Не засыпать"); on: ov.root.awake; onClicked: ov.root.setAwake(!ov.root.awake) }
                        Toggle {
                            glyph: 0xF044A; label: Recorder.recording ? Tr.t("Остановить запись") : Tr.t("Запись экрана")
                            on: Recorder.recording; enabled: Recorder.hasRecorder
                            onClicked: { if (!Recorder.recording) ov.open = false; Recorder.toggle("") }
                        }
                        Toggle {
                            glyph: 0xF0100; label: Tr.t("Скриншот")
                            onClicked: { ov.open = false; shot.restart() }
                        }
                        Toggle { glyph: 0xF0403; label: Tr.t("Плашка в углу"); on: ov.pinned; onClicked: Prefs.set("overlayPin", !ov.pinned) }
                    }
                }
                // ---- уведомления ----
                Card {
                    title: Tr.t("Уведомления")
                    Layout.columnSpan: grid.columns > 2 ? 2 : 2
                    Text {
                        visible: Notifs.list.length === 0
                        text: Tr.t("Нет уведомлений")
                        color: Theme.textMuted; font.pixelSize: Theme.fs(12)
                    }
                    Repeater {
                        model: Notifs.list.slice(0, 4)
                        delegate: Text {
                            required property var modelData
                            Layout.fillWidth: true
                            text: ((modelData.appName ? modelData.appName + ": " : "") + Notifs.titleOf(modelData)
                                  + (Notifs.bodyOf(modelData) ? " — " + Notifs.bodyOf(modelData).replace(/<[^>]*>/g, "") : "")).replace(/\s*\n\s*/g, " · ")
                            color: Theme.textSecondary; font.pixelSize: Theme.fs(12)
                            textFormat: Text.PlainText; elide: Text.ElideRight; maximumLineCount: 1
                        }
                    }
                }
            }
        }
    }
    // скриншот — когда оверлей уже убран с экрана
    Timer {
        id: shot
        interval: 350
        onTriggered: Quickshell.execDetached(["sh", "-c", "p=\"$HOME/.local/bin/glide-shot\"; [ -x \"$p\" ] && exec \"$p\" --capture region || exec niri msg action screenshot"])
    }

    // ---------- закреплённая плашка: строка в углу, мышь — насквозь ----------
    LazyLoader {
        active: ov.pinned && !ov.open
        PanelWindow {
            screen: ov.root.panelScreen
            anchors { top: true; left: true }
            margins { top: 8; left: 8 }
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            WlrLayershell.namespace: "glide-overlay-pin"
            mask: Region {}
            color: "transparent"
            implicitWidth: pinRow.implicitWidth + 20
            implicitHeight: 28
            Rectangle {
                anchors.fill: parent
                radius: height / 2
                color: Qt.rgba(Theme.background.r, Theme.background.g, Theme.background.b, 0.72)
                border.color: Theme.outline
                Text {
                    id: pinRow
                    anchors.centerIn: parent
                    text: Qt.formatTime(ov.now, "HH:mm") + "   " + Tr.t("ЦП ") + ov.num(ov.cpu) + "%   " + Tr.t("ОЗУ ") + ov.num(ov.mem) + "%"
                          + (ov.temp >= 0 ? "   " + ov.num(ov.temp) + "°C" : "")
                          + (ov.battery && UPower.onBattery ? "   " + ov.num(ov.battery.percentage * 100) + "%" : "")
                    color: ov.temp >= 85 ? Theme.warning : Theme.text
                    font.pixelSize: Theme.fs(12); font.family: "JetBrainsMono Nerd Font"
                }
            }
        }
    }

    // ---------- элементы ----------
    component Card: Rectangle {
        id: card
        property string title
        default property alias content: body.data
        Layout.fillWidth: true
        Layout.preferredWidth: 100 * Layout.columnSpan   // столбцы — поровну, длинный текст их не раздвигает
        Layout.alignment: Qt.AlignTop
        implicitHeight: body.implicitHeight + 28
        radius: Theme.radiusLg
        color: Theme.backgroundBar
        border.color: Theme.outline
        MouseArea { anchors.fill: parent }   // щелчок по карточке не закрывает оверлей
        ColumnLayout {
            id: body
            x: 14; y: 14
            width: card.width - 28
            spacing: 6
            Text { text: card.title; color: Theme.textSecondary; font.pixelSize: Theme.fs(11); font.bold: true; font.capitalization: Font.AllUppercase }
        }
    }
    component Meter: ColumnLayout {
        id: m
        property string label
        property real value: 0
        property string text
        property bool warn: false
        Layout.fillWidth: true
        spacing: 3
        RowLayout {
            Layout.fillWidth: true
            Text { Layout.fillWidth: true; text: m.label; color: Theme.textSecondary; font.pixelSize: Theme.fs(12) }
            Text { text: m.text; color: m.warn ? Theme.warning : Theme.text; font.pixelSize: Theme.fs(12); font.bold: true }
        }
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 4; radius: 2
            color: Theme.surfaceHigh
            Rectangle {
                width: parent.width * Math.max(0, Math.min(1, m.value / 100)); height: parent.height; radius: 2
                color: m.warn ? Theme.warning : Prefs.accent
                Behavior on width { NumberAnimation { duration: Prefs.ms(300); easing.type: Easing.OutCubic } }
            }
        }
    }
    component Btn: Rectangle {
        id: b
        property int glyph
        property bool on: false
        signal clicked()
        implicitWidth: 34; implicitHeight: 34; radius: height / 2
        opacity: enabled ? 1 : Theme.disabledOpacity
        color: on ? (bm.pressed ? Theme.accentPressed : bm.containsMouse ? Theme.accentLight : Prefs.accent)
                  : (bm.pressed ? Theme.surfacePressed : bm.containsMouse ? Theme.surfaceHigher : Theme.surface)
        scale: bm.pressed && enabled ? 0.9 : 1
        Behavior on color { ColorAnimation { duration: Prefs.ms(120) } }
        Behavior on scale { NumberAnimation { duration: Prefs.ms(140); easing.type: Easing.OutBack } }
        Text { anchors.centerIn: parent; text: String.fromCodePoint(b.glyph); color: b.on ? Theme.accentText : Theme.text
               font.family: Prefs.iconFont; font.pixelSize: Theme.fs(16) }
        MouseArea { id: bm; anchors.fill: parent; hoverEnabled: true; enabled: b.enabled
                    cursorShape: b.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor; onClicked: b.clicked() }
    }
    component Toggle: Rectangle {
        id: t
        property int glyph
        property string label
        property bool on: false
        signal clicked()
        width: tRow.implicitWidth + 24; height: 34; radius: height / 2
        opacity: enabled ? 1 : Theme.disabledOpacity
        color: on ? (tm.pressed ? Theme.accentPressed : tm.containsMouse ? Theme.accentLight : Prefs.accent)
                  : (tm.pressed ? Theme.surfacePressed : tm.containsMouse ? Theme.surfaceHigher : Theme.surface)
        scale: tm.pressed && enabled ? 0.95 : 1
        Behavior on color { ColorAnimation { duration: Prefs.ms(120) } }
        Behavior on scale { NumberAnimation { duration: Prefs.ms(140); easing.type: Easing.OutBack } }
        Row {
            id: tRow
            anchors.centerIn: parent
            spacing: 6
            Text { anchors.verticalCenter: parent.verticalCenter; text: String.fromCodePoint(t.glyph); color: t.on ? Theme.accentText : Theme.textVariant
                   font.family: Prefs.iconFont; font.pixelSize: Theme.fs(15) }
            Text { anchors.verticalCenter: parent.verticalCenter; text: t.label; color: t.on ? Theme.accentText : Theme.text; font.pixelSize: Theme.fs(12) }
        }
        MouseArea { id: tm; anchors.fill: parent; hoverEnabled: true; enabled: t.enabled
                    cursorShape: t.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor; onClicked: t.clicked() }
    }
}
