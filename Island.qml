import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Bluetooth
import Quickshell.Services.UPower

// Остров сверху по центру. В покое — чёрная таблетка; при активности показывает музыку,
// таймер или подтверждение действия; при наведении раскрывается в «живую активность».
// Клик открывает панель: её фигура (blob в shell.qml) стартует ровно с геометрии острова
// и лежит поверх него, поэтому переход между окнами не виден.
PanelWindow {
    id: iw
    required property var panel
    readonly property var p: panel
    readonly property string kind: p.activity
    readonly property bool peek: p.islandPeek
    // пока панель раскрыта из острова, его содержимое прячется под её фигурой; у рейки — остаётся
    readonly property bool live: !p.panelVisible || !p.island
    readonly property var player: p.musicPlayer
    readonly property bool bubbleOn: kind === "music" && p.timerOn && !peek && live && !p.barOn

    // без бара и в компактном виде остров показывает одну (главную) активность; в стопке — все строками
    function shows(k) {
        if (!p.barOn || !p.stacked) return kind === k
        return k === "music" ? p.musicOn : k === "timer" ? p.timerOn : k === "flash" ? !!p.flashMsg
             : k === "osd" ? !!p.osd : k === "notif" ? !!p.notif : k === "rec" ? p.recOn : k === "live" ? p.liveOn : false
    }
    function kindAt(x, y) {   // что под курсором (с баром): в компактном виде — часы или активность справа
        if (!p.barOn) return p.activity
        if (!p.stacked) return p.inlineAct && x >= p.inlineX ? p.activity : "idle"
        var t = 32
        if (y < t) return "idle"
        for (var k of Prefs.islandOrder) if (y < (t += p.rowH(k))) return k   // строки — в порядке из настроек
        return "idle"
    }

    visible: p.islandShown
    anchors.top: true
    margins.top: 0   // отступ сверху — у самой фигуры (pill.y): так подъём к краю анимируется
    implicitWidth: 440
    implicitHeight: 360   // хватает на часы + все строки в раскрытом виде
    exclusionMode: p.islandOver ? ExclusionMode.Ignore : ExclusionMode.Normal
    WlrLayershell.layer: WlrLayer.Top
    // клавиатура — только пока пишут ответ на уведомление
    WlrLayershell.keyboardFocus: p.replying ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    WlrLayershell.namespace: "glide-island"
    color: "transparent"
    // ввод ловит только сама фигура (и пузырёк), остальное окно прозрачно для мыши
    mask: Region { item: pill; Region { item: iw.bubbleOn ? bubble : null } }

    function nf(code) { return String.fromCodePoint(code) }   // значок из Nerd Font
    function fmt(s) {
        s = Math.max(0, Math.floor(s))
        return Math.floor(s / 60) + ":" + ("0" + (s % 60)).slice(-2)
    }

    // ---- элементы ----
    // место содержимого: без бара — весь остров; с баром — своя строка в стопке, а в компактном
    // виде — правая часть строки часов (inlineX — откуда начинается)
    component Slot: Item {
        id: slot
        property bool row: false
        property int rowY: 0
        property int rowH: 0
        property int inlineX: 0
        x: row ? 0 : inlineX
        width: parent.width - x
        y: row ? rowY : 0
        height: row ? rowH : parent.height
        Behavior on y { enabled: Prefs.anim > 0 && slot.row; Spring { bounce: 0.24; speed: 0.9 } }
        Behavior on height { enabled: Prefs.anim > 0 && slot.row; Spring { bounce: 0.24; speed: 0.9 } }
    }

    component Layer: Item {   // слой содержимого: плавно проявляется, когда on
        id: layer
        property bool on
        anchors.fill: parent
        enabled: on
        visible: opacity > 0
        opacity: on ? 1 : 0
        scale: on ? 1 : 0.9
        Behavior on opacity { NumberAnimation { duration: Prefs.ms(layer.on ? 280 : 120); easing.type: Easing.OutCubic } }
        Behavior on scale { NumberAnimation { duration: Prefs.ms(340); easing.type: Easing.OutCubic } }
    }

    component IBtn: Rectangle {
        id: ib
        property string glyph
        property int glyphSize: 15
        property color tint: Theme.text
        property bool active: true
        property color base: "transparent"
        property color hot: Theme.surfaceHigh
        signal clicked()
        width: 32; height: 32; radius: width / 2
        color: ibm.containsMouse && active ? hot : base
        opacity: active ? 1 : 0.35
        scale: ibm.pressed && active ? 0.86 : 1
        Behavior on color { ColorAnimation { duration: Prefs.ms(120) } }
        Behavior on scale { NumberAnimation { duration: Prefs.ms(160); easing.type: Easing.OutBack } }
        Text { anchors.centerIn: parent; text: ib.glyph; color: ib.tint; font.family: Prefs.iconFont; font.pixelSize: ib.glyphSize }
        MouseArea { id: ibm; anchors.fill: parent; hoverEnabled: true; cursorShape: ib.active ? Qt.PointingHandCursor : Qt.ArrowCursor; onClicked: if (ib.active) ib.clicked() }
    }

    component Ring: Canvas {   // кольцо прогресса
        id: ring
        property real progress: 0
        property color tint: Theme.warning
        property real line: 3
        onProgressChanged: requestPaint()
        onPaint: {
            var c = getContext("2d"), r = width / 2 - line / 2
            c.reset()
            c.lineWidth = line
            c.lineCap = "round"
            c.strokeStyle = Qt.rgba(tint.r, tint.g, tint.b, 0.22)
            c.beginPath(); c.arc(width / 2, height / 2, r, 0, 2 * Math.PI); c.stroke()
            c.strokeStyle = tint
            c.beginPath(); c.arc(width / 2, height / 2, r, -Math.PI / 2, -Math.PI / 2 + 2 * Math.PI * progress); c.stroke()
        }
    }

    component Art: ClippingRectangle {   // обложка трека; без неё — нота
        id: art
        property string url
        color: Theme.surface
        Text { anchors.centerIn: parent; text: "♫"; color: Prefs.accent; font.pixelSize: parent.height * 0.5 }
        Image {
            anchors.fill: parent
            source: art.url
            // обложки бывают 1000×1000 и больше — декодируем под размер на экране, это экономит память
            sourceSize.width: art.width * 2
            sourceSize.height: art.height * 2
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            opacity: status === Image.Ready ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Prefs.ms(250) } }
        }
    }

    component NotifIcon: ClippingRectangle {   // картинка уведомления или значок приложения; без них — колокольчик
        id: ni
        property var entry
        readonly property string src: Notifs.iconFor(entry)
        color: Theme.surfaceHigh
        Text {
            anchors.centerIn: parent
            visible: img.status !== Image.Ready
            text: String.fromCodePoint(0xF009A)
            color: ni.entry && ni.entry.urgency === 2 ? Theme.error : Prefs.accent   // 2 — Critical
            font.family: Prefs.iconFont; font.pixelSize: parent.height * 0.55
        }
        Image {
            id: img
            anchors.fill: parent
            source: ni.src
            sourceSize.width: ni.width * 2
            sourceSize.height: ni.height * 2
            fillMode: Image.PreserveAspectCrop
        }
    }
    // ---- значки у часов (Prefs.islandIcons): видны, только когда есть что показать ----
    readonly property var btConnected: {
        var a = Bluetooth.defaultAdapter
        return a && a.enabled ? a.devices.values.filter(d => d.connected) : []
    }
    function iconInfo(id) {   // {show, glyph, text, color}
        var p = iw.p
        switch (id) {
        case "weather": return { show: Weather.ok, glyph: Weather.ok ? Weather.icon(Weather.data.now.code, Weather.data.now.day) : "",
                                 text: Weather.ok ? Weather.temp(Weather.data.now.temp) : "", color: Theme.textVariant }
        case "battery": {
            var b = p.battery, has = !!b && b.isLaptopBattery
            var pct = has ? Math.round(b.percentage * 100) : 0, chg = has && !UPower.onBattery
            var g = chg ? 0xF0084 : pct >= 95 ? 0xF0079 : pct <= 5 ? 0xF008E : 0xF007A + Math.max(0, Math.round(pct / 10) - 1)
            return { show: has, glyph: iw.nf(g), text: pct + "%", color: chg ? Theme.success : pct <= Math.max(10, Prefs.battCrit) ? Theme.error : Theme.textVariant }
        }
        case "notif": return { show: Notifs.active && Notifs.unread > 0, glyph: iw.nf(0xF009A), text: String(Notifs.unread), color: Prefs.accent }
        case "dnd": return { show: Notifs.active && Notifs.quiet, glyph: iw.nf(0xF009B), text: "", color: Theme.textVariant }
        case "vpn": return { show: Vpn.on, glyph: iw.nf(0xF0565), text: "", color: Theme.success }
        case "mic": return { show: !!p.source && !!p.source.audio && p.source.audio.muted, glyph: iw.nf(0xF036D), text: "", color: Theme.error }
        case "volume": return { show: !!p.sink && !!p.sink.audio && p.sink.audio.muted, glyph: iw.nf(0xF0581), text: "", color: Theme.warning }
        case "bt": return { show: iw.btConnected.length > 0, glyph: iw.nf(0xF00B1), text: "", color: Theme.textVariant }
        case "awake": return { show: p.awake, glyph: iw.nf(0xF0176), text: "", color: Theme.warning }
        case "night": return { show: NightLight.on, glyph: iw.nf(0xF0594), text: "", color: Theme.textVariant }
        case "ptimer": {
            var t = p.powerTimer, left = t ? Math.max(0, Math.ceil((t.end * 1000 - p.now) / 60000)) : 0
            return { show: !!t && left > 0, glyph: iw.nf(t && t.action === "suspend" ? 0xF04B2 : 0xF0425),
                     text: left >= 60 ? Math.floor(left / 60) + ":" + ("0" + left % 60).slice(-2) : left + Tr.t(" мин"), color: Theme.warning }
        }
        case "layout": {
            var n = Niri.layouts[Niri.layoutIdx] || "", first = n.split(/[\s(]/)[0]
            var known = { English: "EN", Russian: "RU", Ukrainian: "UA", Belarusian: "BY", German: "DE", French: "FR", Spanish: "ES", Polish: "PL", Kazakh: "KZ" }
            return { show: Niri.layouts.length > 1, glyph: "", text: known[first] || first.slice(0, 2).toUpperCase(), color: Theme.textSecondary }
        }
        }
        return { show: false }
    }
    // ---- громкость плеера колесом над островом с музыкой ----
    readonly property bool musicHere: !!player && (iw.kind === "music" || iw.shows("music"))
    property real volAcc: 0
    function playerVolume(dy) {
        var pl = iw.player
        if (!pl) return
        volAcc += dy
        if (Math.abs(volAcc) < 60) return                           // тачпад шлёт мелкие шаги — копим до «щелчка»
        var step = volAcc > 0 ? 0.05 : -0.05; volAcc = 0
        var name = pl.identity || Tr.t("Плеер")
        if (pl.volumeSupported && pl.canControl) {
            pl.volume = Math.max(0, Math.min(1, pl.volume + step))
            iw.p.showOsd(iw.nf(pl.volume <= 0 ? 0xF0581 : pl.volume > 0.66 ? 0xF057E : pl.volume > 0.33 ? 0xF0580 : 0xF057F), name, pl.volume, Math.round(pl.volume * 100) + "%")
        } else {
            iw.p.flash(iw.nf(0xF075A), name + Tr.t(": громкость не меняется отсюда"), Theme.textVariant)
        }
    }
    function plain(s) { return s.replace(/<[^>]*>/g, "").replace(/\s+/g, " ").trim() }
    Binding { target: Notifs; property: "hold"; value: iw.peek && iw.shows("notif") }

    // ---- смена трека: старое уезжает, новое въезжает (сам, ⏭ — влево, ⏮ — вправо) ----
    property string shownKey: ""
    property string shownTitle: ""
    property string shownArtist: ""
    property string shownArt: ""
    property int swapDir: 1
    property real swapX: 0
    property real swapOpacity: 1
    property real artScale: 1
    function trackKey(pl) { return pl ? (pl.trackTitle || "") + "\n" + (pl.trackArtist || "") : "" }
    function applyTrack() {
        var pl = player
        shownKey = trackKey(pl)
        shownTitle = pl ? (pl.trackTitle || pl.identity || "") : ""
        shownArtist = pl ? (pl.trackArtist || pl.identity || "") : ""
        shownArt = pl ? (pl.trackArtUrl || "") : ""
    }
    function syncTrack(animate) {
        // тот же трек (например, обложка пришла позже названия) — тихо обновляем
        if (!animate || trackKey(player) === shownKey || shownKey === "" || Prefs.anim === 0 || !live)
            applyTrack()
        else
            swapAnim.restart()
    }
    onPlayerChanged: syncTrack(false)
    Component.onCompleted: syncTrack(false)
    Connections {
        target: iw.player
        // метаданные приходят по частям: собираем их 80 мс и только потом анимируем
        function onTrackTitleChanged() { trackDebounce.restart() }
        function onTrackArtistChanged() { trackDebounce.restart() }
        function onTrackArtUrlChanged() { trackDebounce.restart() }
    }
    Timer { id: trackDebounce; interval: 80; onTriggered: iw.syncTrack(true) }
    SequentialAnimation {
        id: swapAnim
        ParallelAnimation {
            NumberAnimation { target: iw; property: "swapX"; to: -18 * iw.swapDir; duration: Prefs.ms(140); easing.type: Easing.InCubic }
            NumberAnimation { target: iw; property: "swapOpacity"; to: 0; duration: Prefs.ms(140) }
            NumberAnimation { target: iw; property: "artScale"; to: 0.75; duration: Prefs.ms(140); easing.type: Easing.InCubic }
        }
        ScriptAction { script: { iw.applyTrack(); iw.swapX = 18 * iw.swapDir } }
        ParallelAnimation {
            NumberAnimation { target: iw; property: "swapX"; to: 0; duration: Prefs.ms(360); easing.type: Easing.OutBack; easing.overshoot: 1.3 }
            NumberAnimation { target: iw; property: "swapOpacity"; to: 1; duration: Prefs.ms(240); easing.type: Easing.OutCubic }
            NumberAnimation { target: iw; property: "artScale"; to: 1; duration: Prefs.ms(420); easing.type: Easing.OutBack; easing.overshoot: 2.2 }
        }
        ScriptAction { script: iw.swapDir = 1 }
    }

    // ---- наведение ----
    HoverHandler {
        id: hh
        onHoveredChanged: {
            if (hovered) {
                leave.stop()
                iw.p.islandHover = true
                // сразу после закрытия курсор ещё над островом — не открываем снова
                if (Prefs.edgeTrigger && iw.kind === "idle" && iw.live && Date.now() - iw.p.closedAt > 400)
                    openDelay.restart()
            } else {
                openDelay.stop()
                leave.restart()
            }
        }
    }
    Timer { id: leave; interval: 260; onTriggered: if (!iw.p.replying) iw.p.islandHover = false }   // пишут ответ — не сворачивать
    Connections {
        target: iw.p
        function onReplyingChanged() { if (!iw.p.replying && !hh.hovered) leave.restart() }
        function onShownChanged() { if (iw.p.shown) iw.p.replying = false }
    }
    Timer {
        id: openDelay
        interval: Math.max(1, Prefs.hoverDelay)
        onTriggered: if (hh.hovered && iw.kind === "idle" && !iw.p.shown) iw.p.open()
    }

    // ---- фигура ----
    Rectangle {
        id: pill
        readonly property bool ghost: iw.kind === "idle" && !Prefs.edgePill && !iw.peek && !iw.p.barOn
        x: Math.round((iw.width - width) / 2)
        y: iw.p.islandTop
        Behavior on y { enabled: Prefs.anim > 0; Spring { bounce: 0.2 } }
        width: iw.p.compactW
        height: iw.p.compactH
        radius: Math.min(height / 2, iw.p.compactRadius)
        Behavior on radius { NumberAnimation { duration: Prefs.ms(180); easing.type: Easing.OutCubic } }
        color: iw.p.islandColor
        border.color: iw.p.islandBorder
        Behavior on color { ColorAnimation { duration: Prefs.ms(400) } }          // камера/микрофон — плавно
        Behavior on border.color { ColorAnimation { duration: Prefs.ms(400) } }
        opacity: ghost ? 0 : 1
        // пока панель раскрыта из острова, он прячется под её фигурой: иначе его углы
        // выглядывают из-под более скруглённых углов сжимающейся фигуры
        visible: !(iw.p.island && iw.p.panelVisible && !iw.p.blobAtCompact)
        scale: tap.pressed ? 0.96 : 1
        clip: true
        IslandTint { colors: iw.p.islandColors; radius: pill.radius }
        Behavior on width { enabled: Prefs.anim > 0; Spring { bounce: 0.3 } }
        Behavior on height { enabled: Prefs.anim > 0; Spring { bounce: 0.24; speed: 0.9 } }
        Behavior on opacity { NumberAnimation { duration: Prefs.ms(200) } }
        Behavior on scale { enabled: Prefs.anim > 0; Spring { bounce: 0.45; speed: 1.6 } }

        MouseArea {   // клик — открыть панель (на категории активности); средняя кнопка — пауза
            cursorShape: Qt.PointingHandCursor
            id: tap
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.MiddleButton
            // колесо, пока в острове музыка, — громкость этого плеера (MPRIS Volume), а не всей системы
            onWheel: (w) => { if (iw.musicHere) iw.playerVolume(w.angleDelta.y); else w.accepted = false }
            onClicked: (e) => {
                if (e.button === Qt.MiddleButton) { if (iw.player && iw.player.canTogglePlaying) iw.player.togglePlaying() }
                else iw.p.openFromIsland(iw.kindAt(e.x, e.y))
            }
        }

        // с баром: часы и дата — всегда верхняя строка острова
        Slot {
            row: iw.p.barOn
            rowH: iw.p.rowsH ? 32 : iw.p.compactH
            Layer {
            on: iw.p.barOn && iw.live
            Row {
                // в покое — по центру; когда справа активность (компактный вид) — только время, слева
                anchors.verticalCenter: parent.verticalCenter
                x: iw.p.inlineAct ? 15 : Math.round((parent.width - width) / 2)
                spacing: 8
                IconRow { id: iconsL; side: "left"; visible: implicitWidth > 0 && !iw.p.inlineAct }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: iw.p.clockTime
                    color: Theme.text; font.pixelSize: Theme.fs(13); font.bold: true
                    font.features: ({ "tnum": 1 })
                }
                Text {
                    visible: text !== "" && !iw.p.inlineAct
                    anchors.verticalCenter: parent.verticalCenter
                    text: iw.p.clockDate
                    color: Theme.textSecondary; font.pixelSize: Theme.fs(12)
                }
                IconRow { id: iconsR; side: "right"; visible: implicitWidth > 0 && !iw.p.inlineAct; leftPadding: 4 }
            }
            // ширина значков — ядру, чтобы остров вырос под них
            Binding { target: iw.p; property: "clockIconsW"
                      value: (iconsL.visible ? iconsL.implicitWidth + 8 : 0) + (iconsR.visible ? iconsR.implicitWidth + 8 : 0) }
            }
        }
        Rectangle {   // шов между часами и строками активностей
            x: 14; y: 32
            width: parent.width - 28; height: 1
            color: Theme.surface
            opacity: iw.p.barOn && iw.p.rowsH > 0 && iw.live ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Prefs.ms(200) } }
        }
        Rectangle {   // компактный вид: вертикальный шов между временем и активностью
            x: iw.p.inlineX - 6; y: 8
            width: 1; height: 16
            color: Theme.surface
            opacity: iw.p.inlineAct && iw.live ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Prefs.ms(200) } }
        }

        // покой + наведение: категории, клик открывает нужную
        Layer {
            on: iw.kind === "idle" && iw.peek && iw.live && !iw.p.barOn
            Row {
                anchors.centerIn: parent
                spacing: 2
                Repeater {
                    model: iw.p.categories.slice(0, iw.p.islandCats)
                    delegate: IBtn {
                        required property var modelData
                        width: 30; height: 30
                        glyph: modelData.icon
                        onClicked: iw.p.openCategory(modelData.id)
                    }
                }
            }
        }

        // OSD: громкость, микрофон, яркость, профиль питания, выход звука
        Slot {
            row: iw.p.stacked; inlineX: iw.p.inlineAct ? iw.p.inlineX : 0
            rowY: iw.p.rowY("osd")
            rowH: iw.p.rowOsdH
        Layer {
            on: iw.shows("osd") && iw.live
            readonly property var o: iw.p.osd
            property var last: ({ icon: "", label: "", value: -1, text: "" })   // держим, пока строка гаснет
            onOChanged: if (o) last = o
            Text {
                x: 12; anchors.verticalCenter: parent.verticalCenter
                text: parent.last.icon
                color: Prefs.accent
                font.family: Prefs.iconFont; font.pixelSize: Theme.fs(16)
            }
            Text {   // без полосы: «Микрофон · выключен»
                visible: parent.last.value < 0
                x: 38; width: parent.width - 38 - 14
                anchors.verticalCenter: parent.verticalCenter
                text: parent.last.label + "  ·  " + parent.last.text
                color: Theme.text; font.pixelSize: Theme.fs(12)
                elide: Text.ElideRight
            }
            Rectangle {   // полоса уровня; справа место под значение («без звука» длиннее процентов)
                visible: parent.last.value >= 0
                x: 38; width: parent.width - 38 - osdValue.implicitWidth - 24
                anchors.verticalCenter: parent.verticalCenter
                height: 6; radius: Theme.r(3)
                color: Theme.surfaceHigh
                Rectangle {
                    height: parent.height; radius: Theme.r(3)
                    width: Math.max(height, parent.width * Math.max(0, parent.parent.last.value))
                    color: Prefs.accent
                    Behavior on width { NumberAnimation { duration: Prefs.ms(140); easing.type: Easing.OutCubic } }
                }
            }
            Text {
                id: osdValue
                visible: parent.last.value >= 0
                anchors.right: parent.right; anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                text: parent.last.text
                color: Theme.textSecondary; font.pixelSize: Theme.fs(12)
                font.features: ({ "tnum": 1 })
            }
        }
        }

        Slot {
            row: iw.p.stacked; inlineX: iw.p.inlineAct ? iw.p.inlineX : 0
            rowY: iw.p.rowY("music")
            rowH: iw.p.rowMusicH
        // музыка: обложка, название, эквалайзер
        Layer {
            on: iw.shows("music") && !iw.peek && iw.live
            Art {
                url: iw.shownArt
                x: 5; anchors.verticalCenter: parent.verticalCenter
                width: 22; height: 22; radius: Theme.r(11)
                scale: iw.artScale
            }
            Text {
                x: 36 + iw.swapX; width: parent.width - 36 - 34
                anchors.verticalCenter: parent.verticalCenter
                opacity: iw.swapOpacity
                text: iw.shownTitle
                color: Theme.textVariant; font.pixelSize: Theme.fs(12)
                elide: Text.ElideRight
            }
            Row {
                anchors.right: parent.right; anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2
                Repeater {
                    id: bars
                    model: 4
                    delegate: Rectangle {
                        property real level: 3
                        anchors.verticalCenter: parent.verticalCenter
                        width: 3; height: level; radius: 1.5
                        color: Prefs.accent
                        // плавный режим перерисовывает остров 60 раз в секунду (~10% ядра) —
                        // по умолчанию столбики меняются ступеньками, ~7 кадров в секунду
                        Behavior on height { enabled: Prefs.eqMode === "smooth"; NumberAnimation { duration: Prefs.ms(150); easing.type: Easing.OutQuad } }
                    }
                }
                Timer {
                    interval: Prefs.eqMode === "smooth" ? 150 : 140; repeat: true
                    running: Prefs.eqMode !== "off" && iw.shows("music") && !iw.peek && iw.live
                             && !!iw.player && iw.player.isPlaying
                    onRunningChanged: {
                        if (running) return
                        var rest = [5, 9, 7, 4]   // без анимации — неподвижный значок эквалайзера
                        for (var i = 0; i < bars.count; i++) bars.itemAt(i).level = Prefs.eqMode === "off" && iw.player && iw.player.isPlaying ? rest[i] : 3
                    }
                    onTriggered: { for (var i = 0; i < bars.count; i++) bars.itemAt(i).level = 4 + Math.random() * 11 }
                }
            }
        }

        // музыка + наведение: обложка, трек, прогресс, кнопки
        Layer {
            id: musicPeek
            on: iw.shows("music") && iw.peek && iw.live
            Timer {   // position в Mpris сам не обновляется
                running: musicPeek.on && !!iw.player && iw.player.isPlaying
                interval: 500; repeat: true
                onTriggered: iw.player.positionChanged()
            }
            Art { url: iw.shownArt; x: 12; y: 12; width: 64; height: 64; radius: Theme.r(14); scale: iw.artScale }
            Column {
                x: 88 + iw.swapX; y: 16
                width: parent.width - 88 - 116
                spacing: 2
                opacity: iw.swapOpacity
                Text {
                    width: parent.width
                    text: iw.shownTitle || "—"
                    color: Theme.text; font.pixelSize: Theme.fs(14); font.bold: true
                    elide: Text.ElideRight
                }
                Text {
                    width: parent.width
                    text: iw.shownArtist
                    color: Theme.textSecondary; font.pixelSize: Theme.fs(12)
                    elide: Text.ElideRight
                }
            }
            Rectangle {
                visible: !!iw.player && iw.player.lengthSupported && iw.player.length > 0
                x: 88; y: 62
                width: parent.width - 88 - 116; height: 4; radius: Theme.r(2)
                color: Theme.surfaceHigh
                Rectangle {
                    height: parent.height; radius: Theme.r(2)
                    color: Prefs.accent
                    width: iw.player && iw.player.length > 0
                           ? parent.width * Math.min(1, iw.player.position / iw.player.length) : 0
                    Behavior on width { NumberAnimation { duration: Prefs.ms(500) } }
                }
            }
            Row {
                anchors.right: parent.right; anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2
                IBtn { glyph: iw.nf(0xF04AE); active: !!iw.player && iw.player.canGoPrevious; onClicked: { iw.swapDir = -1; iw.player.previous() } }
                IBtn {
                    width: 36; height: 36; glyphSize: 18
                    glyph: iw.player && iw.player.isPlaying ? iw.nf(0xF03E4) : iw.nf(0xF040A)
                    active: !!iw.player && iw.player.canTogglePlaying
                    onClicked: iw.player.togglePlaying()
                }
                IBtn { glyph: iw.nf(0xF04AD); active: !!iw.player && iw.player.canGoNext; onClicked: { iw.swapDir = 1; iw.player.next() } }
            }
        }
        }

        Slot {
            row: iw.p.stacked; inlineX: iw.p.inlineAct ? iw.p.inlineX : 0
            rowY: iw.p.rowY("timer")
            rowH: iw.p.rowTimerH
        // таймер: кольцо и остаток
        Layer {
            on: iw.shows("timer") && !iw.peek && iw.live
            Ring {
                x: 7; anchors.verticalCenter: parent.verticalCenter
                width: 20; height: 20
                progress: iw.p.timerProgress
            }
            Text {
                anchors.right: parent.right; anchors.rightMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                text: iw.fmt(iw.p.timerLeft)
                color: Theme.warning; font.pixelSize: Theme.fs(13); font.bold: true
                font.features: ({ "tnum": 1 })
            }
        }

        // таймер + наведение: крупный остаток и отмена
        Layer {
            on: iw.shows("timer") && iw.peek && iw.live
            Ring {
                x: 12; anchors.verticalCenter: parent.verticalCenter
                width: 40; height: 40; line: 4
                progress: iw.p.timerProgress
            }
            Text {
                x: 64; y: 8
                text: iw.fmt(iw.p.timerLeft)
                color: Theme.warning; font.pixelSize: Theme.fs(24); font.bold: true
                font.features: ({ "tnum": 1 })
            }
            Text {
                x: 65; y: 40
                text: Tr.t("Таймер · ") + Math.round(iw.p.timerTotal / 60) + Tr.t(" мин")
                color: Theme.textSecondary; font.pixelSize: Theme.fs(11)
            }
            IBtn {
                anchors.right: parent.right; anchors.rightMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                width: 36; height: 36
                glyph: iw.nf(0xF0156); tint: Theme.error
                base: Theme.errorContainer; hot: Theme.errorHover
                onClicked: iw.p.cancelTimer()
            }
        }
        }

        Slot {
            row: iw.p.stacked; inlineX: iw.p.inlineAct ? iw.p.inlineX : 0
            rowY: iw.p.rowY("live")
            rowH: iw.p.rowLiveH
        // «живая активность» (Activities.qml): значок, название, прогресс; наведение — подпись, кнопка, «×»
        Layer {
            id: liveL
            readonly property var a: Activities.top
            readonly property real prog: a ? a.progress : -1
            readonly property color tone: a && a.color ? a.color : Prefs.accent
            on: iw.shows("live") && iw.live
            Text {
                x: 12; y: iw.peek ? 10 : 0; height: iw.peek ? 22 : parent.height
                verticalAlignment: Text.AlignVCenter
                text: liveL.a && liveL.a.icon ? liveL.a.icon : iw.nf(0xF0996)
                color: liveL.tone; font.family: Prefs.iconFont; font.pixelSize: Theme.fs(iw.peek ? 18 : 15)
            }
            Text {
                x: iw.peek ? 38 : 34; y: iw.peek ? 10 : 0; height: iw.peek ? 22 : parent.height
                width: parent.width - x - liveRight.width - 12
                verticalAlignment: Text.AlignVCenter
                text: liveL.a ? liveL.a.title : ""
                color: Theme.text; font.pixelSize: Theme.fs(12); font.weight: iw.peek ? Font.DemiBold : Font.Normal
                elide: Text.ElideRight; textFormat: Text.PlainText
            }
            Text {   // при наведении — подпись и «ещё N»
                visible: iw.peek
                x: 38; y: 32
                width: parent.width - x - liveRight.width - 12
                text: (liveL.a ? liveL.a.subtitle : "") + (Activities.list.length > 1 ? (liveL.a && liveL.a.subtitle ? "  ·  " : "") + Tr.t("ещё ") + (Activities.list.length - 1) : "")
                color: Theme.textSecondary; font.pixelSize: Theme.fs(11)
                elide: Text.ElideRight; textFormat: Text.PlainText
            }
            Row {
                id: liveRight
                anchors.right: parent.right; anchors.rightMargin: 6
                y: iw.peek ? 6 : (parent.height - height) / 2
                spacing: 4
                Text {
                    visible: liveL.prog >= 0
                    anchors.verticalCenter: parent.verticalCenter
                    text: Math.round(liveL.prog * 100) + "%"
                    color: liveL.tone; font.pixelSize: Theme.fs(12); font.bold: true; font.features: ({ "tnum": 1 })
                }
                Rectangle {   // кнопка активности (props.actionLabel)
                    visible: iw.peek && !!liveL.a && !!liveL.a.actionLabel
                    anchors.verticalCenter: parent.verticalCenter
                    width: actText.implicitWidth + 18; height: 24; radius: 12
                    color: actMa.pressed ? Theme.accentPressed : actMa.containsMouse ? Theme.accentLight : Prefs.accent
                    Behavior on color { ColorAnimation { duration: Prefs.ms(120) } }
                    Text { id: actText; anchors.centerIn: parent; text: liveL.a ? liveL.a.actionLabel : ""
                           color: Theme.accentText; font.pixelSize: Theme.fs(11) }
                    MouseArea { id: actMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: Activities.act(liveL.a.id) }
                }
                IBtn {
                    visible: iw.peek
                    width: 24; height: 24; glyphSize: 12
                    glyph: iw.nf(0xF0156); tint: Theme.textSecondary
                    onClicked: Activities.end(liveL.a.id)
                }
            }
            Rectangle {   // полоска прогресса снизу; без прогресса — бегущая
                x: 12; width: parent.width - 24
                anchors.bottom: parent.bottom; anchors.bottomMargin: iw.peek ? 8 : 3
                height: 3; radius: 2
                color: Qt.rgba(liveL.tone.r, liveL.tone.g, liveL.tone.b, 0.22)
                clip: true
                Rectangle {
                    visible: liveL.prog >= 0
                    width: parent.width * Math.max(0, Math.min(1, liveL.prog)); height: parent.height; radius: 2
                    color: liveL.tone
                    Behavior on width { NumberAnimation { duration: Prefs.ms(300); easing.type: Easing.OutCubic } }
                }
                Rectangle {   // ожидание без процента: бесконечный индикатор (не через Prefs.ms — см. CLAUDE.md)
                    id: liveRun
                    visible: liveL.prog < 0 && liveL.on
                    width: parent.width * 0.3; height: parent.height; radius: 2
                    color: liveL.tone
                    NumberAnimation on x { from: -liveRun.width; to: liveRun.parent.width; duration: 1300; loops: Animation.Infinite; running: liveL.prog < 0 && liveL.on }
                }
            }
        }
        }

        Slot {
            row: iw.p.stacked; inlineX: iw.p.inlineAct ? iw.p.inlineX : 0
            rowY: iw.p.rowY("rec")
            rowH: iw.p.rowRecH
        // запись экрана: красная точка, таймер, «стоп» (клик по строке тоже останавливает)
        Layer {
            on: iw.shows("rec") && iw.live
            Rectangle {
                x: 12; anchors.verticalCenter: parent.verticalCenter
                width: 10; height: 10; radius: Theme.r(5)
                color: Theme.error
            }
            Text {
                x: 30; anchors.verticalCenter: parent.verticalCenter
                text: Tr.t("Запись")
                color: Theme.text; font.pixelSize: Theme.fs(12)
            }
            Text {
                anchors.right: stopRec.left; anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                text: Recorder.fmt(Recorder.elapsed)
                color: Theme.error; font.pixelSize: Theme.fs(13); font.bold: true
                font.features: ({ "tnum": 1 })
            }
            IBtn {
                id: stopRec
                anchors.right: parent.right; anchors.rightMargin: 4
                anchors.verticalCenter: parent.verticalCenter
                width: 26; height: 26; glyphSize: 13
                glyph: iw.nf(0xF04DB); tint: Theme.error
                base: Theme.errorContainer; hot: Theme.errorHover
                onClicked: Recorder.stop()
            }
        }
        }

        Slot {
            row: iw.p.stacked; inlineX: iw.p.inlineAct ? iw.p.inlineX : 0
            rowY: iw.p.rowY("flash")
            rowH: iw.p.rowFlashH
        // вспышка: подтверждение действия или сообщение через ipc
        Layer {
            on: iw.shows("flash") && iw.live
            Rectangle {
                x: 6; anchors.verticalCenter: parent.verticalCenter
                width: 24; height: 24; radius: Theme.r(12)
                color: iw.p.flashMsg ? iw.p.flashMsg.color : Theme.success
                Text {
                    anchors.centerIn: parent
                    text: iw.p.flashMsg ? iw.p.flashMsg.icon : ""
                    color: Theme.accentText; font.pixelSize: Theme.fs(13); font.bold: true
                }
            }
            Text {
                x: 38; width: parent.width - 38 - 14
                anchors.verticalCenter: parent.verticalCenter
                text: iw.p.flashMsg ? iw.p.flashMsg.text : ""
                color: Theme.text; font.pixelSize: Theme.fs(13)
                elide: Text.ElideRight
            }
        }
        }

        Slot {
            row: iw.p.stacked; inlineX: iw.p.inlineAct ? iw.p.inlineX : 0
            rowY: iw.p.rowY("notif")
            rowH: iw.p.rowNotifH
        // уведомление: значок и строка текста
        Layer {
            on: iw.shows("notif") && !iw.peek && iw.live
            readonly property var e: iw.p.notif
            property var last: null          // держим, пока строка гаснет
            onEChanged: if (e) last = e
            NotifIcon { entry: parent.last; x: 5; anchors.verticalCenter: parent.verticalCenter; width: 22; height: 22; radius: Theme.r(11) }
            Text {
                x: 36; width: parent.width - 36 - 14
                anchors.verticalCenter: parent.verticalCenter
                text: parent.last ? parent.last.summary + (parent.last.body ? "  ·  " + iw.plain(parent.last.body) : "") : ""
                color: Theme.text; font.pixelSize: Theme.fs(12)
                textFormat: Text.PlainText
                elide: Text.ElideRight
            }
        }

        // уведомление + наведение: приложение, время, текст, действия, закрыть
        Layer {
            on: iw.shows("notif") && iw.peek && iw.live
            readonly property var e: iw.p.notif
            property var last: null
            onEChanged: if (e) last = e
            NotifIcon { entry: parent.last; x: 12; y: 12; width: 44; height: 44; radius: Theme.r(12) }
            Text {
                x: 68; y: 11; width: parent.width - 68 - 44
                text: parent.last ? (parent.last.appName || Tr.t("Уведомление")) + "  ·  " + Notifs.ago(parent.last.time) : ""
                color: Theme.textSecondary; font.pixelSize: Theme.fs(11)
                textFormat: Text.PlainText
                elide: Text.ElideRight
            }
            Text {
                x: 68; y: 26; width: parent.width - 68 - 44
                text: parent.last ? parent.last.summary : ""
                color: Theme.text; font.pixelSize: Theme.fs(13); font.bold: true
                textFormat: Text.PlainText
                elide: Text.ElideRight
            }
            Text {
                x: 68; y: 45; width: parent.width - 68 - 16
                text: parent.last ? parent.last.body : ""
                color: Theme.textVariant; font.pixelSize: Theme.fs(12)
                textFormat: Text.StyledText
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
                linkColor: Prefs.accent
                onLinkActivated: (link) => Notifs.openLink(link)
            }
            IBtn {   // закрыть уведомление
                anchors.right: parent.right; anchors.rightMargin: 8
                y: 8; width: 28; height: 28; glyphSize: 14
                glyph: iw.nf(0xF0156); tint: Theme.textSecondary
                onClicked: Notifs.remove(parent.last)
            }
            Rectangle {   // поле ответа: Enter — отправить, Esc — отмена
                id: replyBox
                visible: iw.p.replying && !!parent.last && parent.last.reply
                x: 68; y: 80; width: parent.width - 68 - 12; height: 30; radius: Theme.r(15)
                color: Theme.surfaceHigh
                border.color: Prefs.accent; border.width: 2
                onVisibleChanged: if (visible) { replyInput.text = ""; replyInput.forceActiveFocus() }
                TextInput {
                    id: replyInput
                    x: 12; width: parent.width - 12 - 34
                    anchors.verticalCenter: parent.verticalCenter
                    color: Theme.text; font.pixelSize: Theme.fs(12)
                    selectionColor: Prefs.accent; selectedTextColor: Theme.accentText
                    clip: true
                    Keys.onEscapePressed: iw.p.replying = false
                    onAccepted: send()
                    function send() {
                        if (Notifs.sendReply(replyBox.parent.last, text)) { iw.p.replying = false; iw.p.flash(iw.nf(0xF048A), Tr.t("Ответ отправлен"), Theme.success) }
                    }
                    Text {
                        visible: !parent.text
                        anchors.verticalCenter: parent.verticalCenter
                        text: replyBox.parent.last && replyBox.parent.last.replyHint ? replyBox.parent.last.replyHint : Tr.t("Ответ… (Enter — отправить, Esc — отмена)")
                        color: Theme.textFaint; font.pixelSize: Theme.fs(12)
                        width: parent.width; elide: Text.ElideRight
                    }
                    HoverHandler { cursorShape: Qt.IBeamCursor }
                }
                IBtn {   // отправить
                    anchors.right: parent.right; anchors.rightMargin: 3
                    anchors.verticalCenter: parent.verticalCenter
                    width: 24; height: 24; glyphSize: 14
                    glyph: iw.nf(0xF048A); tint: replyInput.text.trim() ? Prefs.accent : Theme.textFaint
                    onClicked: replyInput.send()
                }
            }
            Row {   // кнопки действий приложения («Ответить», «Отметить прочитанным»…)
                visible: !!parent.last && (parent.last.actions.length > 0 || parent.last.reply) && !replyBox.visible
                x: 68; y: 82
                spacing: 6
                Rectangle {   // свой «Ответить» — поле прямо в острове
                    visible: !!parent.parent.last && parent.parent.last.reply
                    height: 26; radius: Theme.r(13)
                    width: replyText.implicitWidth + 24
                    color: replyMouse.pressed ? Theme.accentPressed : replyMouse.containsMouse ? Theme.accentLight : Theme.accent
                    scale: replyMouse.pressed ? 0.94 : 1
                    Behavior on color { ColorAnimation { duration: Prefs.ms(120) } }
                    Behavior on scale { NumberAnimation { duration: Prefs.ms(140); easing.type: Easing.OutBack } }
                    Text { id: replyText; anchors.centerIn: parent; text: Tr.t("Ответить"); color: Theme.accentText; font.pixelSize: Theme.fs(12) }
                    MouseArea { id: replyMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: iw.p.replying = true }
                }
                Repeater {
                    model: parent.parent.last ? parent.parent.last.actions.slice(0, parent.parent.last.reply ? 2 : 3) : []
                    delegate: Rectangle {
                        id: act
                        required property var modelData
                        height: 26; radius: Theme.r(13)
                        width: Math.min(140, actText.implicitWidth + 24)
                        color: actMouse.pressed ? Theme.surfacePressed : actMouse.containsMouse ? Theme.surfaceHigher : Theme.surfaceHigh
                        scale: actMouse.pressed ? 0.94 : 1
                        Behavior on color { ColorAnimation { duration: Prefs.ms(120) } }
                        Behavior on scale { NumberAnimation { duration: Prefs.ms(140); easing.type: Easing.OutBack } }
                        Text {
                            id: actText
                            anchors.centerIn: parent
                            width: Math.min(implicitWidth, 116)
                            text: act.modelData.text
                            color: Theme.text; font.pixelSize: Theme.fs(12)
                            elide: Text.ElideRight
                        }
                        MouseArea {
                            id: actMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Notifs.invoke(iw.p.notif, act.modelData.id)
                        }
                    }
                }
            }
        }
        }
    }

    // ---- пузырёк второй активности (таймер, пока играет музыка) ----
    Rectangle {
        id: bubble
        Behavior on border.color { ColorAnimation { duration: Prefs.ms(140) } }
        width: 32; height: 32; radius: Theme.r(16)
        y: iw.p.islandTop + (iw.p.compactH - height) / 2
        x: pill.x + pill.width + (iw.bubbleOn ? 8 : -height)
        color: iw.p.islandColor
        border.color: bubbleMa.containsMouse ? Theme.textFaint : iw.p.islandBorder   // наведение — обводка ярче
        IslandTint { colors: iw.p.islandColors; radius: bubble.radius }
        opacity: iw.bubbleOn ? 1 : 0
        scale: !iw.bubbleOn ? 0.4 : bubbleMa.pressed ? 0.88 : 1
        visible: opacity > 0
        Behavior on x { enabled: Prefs.anim > 0; Spring { bounce: 0.35 } }
        Behavior on opacity { NumberAnimation { duration: Prefs.ms(200) } }
        Behavior on scale { enabled: Prefs.anim > 0; Spring { bounce: 0.35 } }
        Ring {
            anchors.centerIn: parent
            width: 20; height: 20
            progress: iw.p.timerProgress
        }
        MouseArea {
            id: bubbleMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: { var t = iw.p.pluginById("timer"); if (t) iw.p.openCategory(t.categories[0]); else iw.p.open() }
        }
    }

    // строка значков у часов; inline-компонент не видит id — данные через iw передаются свойством
    component IconRow: Row {
        id: ir
        property string side
        property var hub: iw
        anchors.verticalCenter: parent ? parent.verticalCenter : undefined
        spacing: 7
        Repeater {
            model: Prefs.islandIcons.filter(x => x.on && x.side === ir.side)
            delegate: Row {
                id: ic
                required property var modelData
                readonly property var info: ir.hub.iconInfo(modelData.id)
                visible: !!info.show
                anchors.verticalCenter: parent ? parent.verticalCenter : undefined
                spacing: 3
                Text {
                    visible: !!ic.info.glyph
                    anchors.verticalCenter: parent.verticalCenter
                    text: ic.info.glyph || ""
                    color: ic.info.color || Theme.textVariant
                    font.family: Prefs.iconFont; font.pixelSize: Theme.fs(14)
                    Behavior on color { ColorAnimation { duration: Prefs.ms(160) } }
                }
                Text {
                    visible: !!ic.info.text
                    anchors.verticalCenter: parent.verticalCenter
                    text: ic.info.text || ""
                    color: ic.modelData.id === "notif" ? ic.info.color : Theme.textSecondary
                    font.pixelSize: Theme.fs(12); font.features: ({ "tnum": 1 })
                }
            }
        }
    }
}
