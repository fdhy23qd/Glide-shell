import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Widgets

// Один виджет рабочего стола (настройки — в Prefs.widgets, см. DesktopWidgets.qml): положение — якорь (tl t tr l c r
// bl b br) и сдвиг dx/dy, размер (масштаб), цвет (текст / акцент / приглушённый), прозрачность. Текст — с мягкой
// тенью: читается на любых обоях. Содержимое по типу: clock, date, weather, music, system, text.
Item {
    id: wgt
    property var cfg: ({})
    property var hub: null
    // правка рабочего стола (DesktopWidgets.editing): тянуть — сдвиг (с прилипанием к сетке 8 px и к центру),
    // колесо — размер, правая кнопка — настройки, крестик — убрать. Пока тянут, сдвиг живёт здесь, в конфиг — по отпусканию
    property bool editing: false
    property real dragDx: 0
    property real dragDy: 0
    property bool dragging: false
    readonly property string type: cfg.type || "clock"
    readonly property real k: Math.max(0.5, Math.min(3, Number(cfg.size) || 1))
    readonly property string anchorPos: cfg.anchor || "c"
    readonly property bool interactive: type === "music"
    readonly property color tint: cfg.color === "accent" ? Theme.accent : cfg.color === "muted" ? Theme.textSecondary : Theme.text
    readonly property color sub: cfg.color === "muted" ? Theme.textMuted : Theme.textSecondary
    function nf(code) { return String.fromCodePoint(code) }

    visible: type !== "music" || !!hub.player || editing
    opacity: cfg.opacity === undefined ? 1 : Math.max(0.2, Math.min(1, Number(cfg.opacity)))
    width: body.item ? body.item.implicitWidth : 0
    height: body.item ? body.item.implicitHeight : 0
    readonly property string h: anchorPos.indexOf("l") >= 0 ? "l" : anchorPos.indexOf("r") >= 0 ? "r" : "c"
    readonly property string v: anchorPos[0] === "t" ? "t" : anchorPos[0] === "b" ? "b" : "c"
    readonly property real baseX: h === "l" ? 0 : h === "r" ? parent.width - width : (parent.width - width) / 2
    readonly property real baseY: v === "t" ? 0 : v === "b" ? parent.height - height : (parent.height - height) / 2
    x: baseX + (dragging ? dragDx : Number(cfg.dx) || 0)
    y: baseY + (dragging ? dragDy : Number(cfg.dy) || 0)
    readonly property int align: h === "l" ? Text.AlignLeft : h === "r" ? Text.AlignRight : Text.AlignHCenter
    Behavior on x { enabled: !wgt.dragging; NumberAnimation { duration: Prefs.ms(260); easing.type: Easing.OutCubic } }
    Behavior on y { enabled: !wgt.dragging; NumberAnimation { duration: Prefs.ms(260); easing.type: Easing.OutCubic } }

    // ---- правка: рамка, перетаскивание, размер колесом ----
    Rectangle {
        visible: wgt.editing
        anchors.fill: parent
        anchors.margins: -10
        z: 10
        radius: Theme.r(14)
        color: editMa.containsMouse || wgt.dragging ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.12) : "transparent"
        border.width: editMa.containsMouse || wgt.dragging ? 2 : 1
        border.color: editMa.containsMouse || wgt.dragging ? Theme.accent : Qt.rgba(1, 1, 1, 0.45)
        Behavior on color { ColorAnimation { duration: Prefs.ms(120) } }
        MouseArea {
            id: editMa
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            cursorShape: wgt.dragging ? Qt.ClosedHandCursor : Qt.OpenHandCursor
            property point start
            property real sx: 0
            property real sy: 0
            onPressed: (m) => {
                if (m.button !== Qt.LeftButton) return
                start = mapToItem(wgt.parent, m.x, m.y)
                sx = Number(wgt.cfg.dx) || 0; sy = Number(wgt.cfg.dy) || 0
                wgt.dragDx = sx; wgt.dragDy = sy
                wgt.dragging = true
            }
            onPositionChanged: (m) => {
                if (!wgt.dragging) return
                var p = mapToItem(wgt.parent, m.x, m.y)
                var dx = Math.round((sx + p.x - start.x) / 8) * 8, dy = Math.round((sy + p.y - start.y) / 8) * 8
                // прилипание к центру экрана (по горизонтали и вертикали), если рядом
                var cx = wgt.baseX + dx + wgt.width / 2 - wgt.parent.width / 2
                if (Math.abs(cx) < 14) dx -= cx
                var cy = wgt.baseY + dy + wgt.height / 2 - wgt.parent.height / 2
                if (Math.abs(cy) < 14) dy -= cy
                wgt.dragDx = dx; wgt.dragDy = dy
            }
            onReleased: (m) => {
                if (!wgt.dragging) return
                wgt.hub.setWidget(wgt.cfg.id, { dx: Math.round(wgt.dragDx), dy: Math.round(wgt.dragDy) })
                wgt.dragging = false
            }
            onClicked: (m) => { if (m.button === Qt.RightButton) wgt.hub.openSettings(wgt.cfg.id) }
            onWheel: (w) => {
                var s = Math.round(Math.max(0.5, Math.min(3, wgt.k + (w.angleDelta.y > 0 ? 0.1 : -0.1))) * 10) / 10
                if (s !== wgt.k) wgt.hub.setWidget(wgt.cfg.id, { size: s })
            }
        }
        Rectangle {   // убрать виджет
            anchors.right: parent.right; anchors.top: parent.top
            anchors.margins: -10
            width: 24; height: 24; radius: 12
            visible: editMa.containsMouse || delMa.containsMouse
            color: delMa.pressed ? Qt.darker(Theme.error, 1.2) : delMa.containsMouse ? Theme.error : Theme.surfaceHigh
            border.color: Theme.outline
            scale: delMa.pressed ? 0.88 : 1
            Behavior on scale { NumberAnimation { duration: Prefs.ms(140); easing.type: Easing.OutBack } }
            Text { anchors.centerIn: parent; text: String.fromCodePoint(0xF0156); color: Theme.text
                   font.family: Prefs.iconFont; font.pixelSize: 14 }
            MouseArea { id: delMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: wgt.hub.removeWidget(wgt.cfg.id) }
        }
        Rectangle {   // размер — подпись снизу, пока под курсором
            visible: editMa.containsMouse && !wgt.dragging
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.bottom; anchors.topMargin: 6
            width: hintText.implicitWidth + 16; height: 22; radius: 11
            color: Theme.surfaceHigh; border.color: Theme.outline
            Text { id: hintText; anchors.centerIn: parent; color: Theme.textSecondary; font.pixelSize: 11
                   text: Tr.t("размер ") + Math.round(wgt.k * 100) + Tr.t("% · колесо — больше/меньше · правая — настройки") }
        }
    }

    // ---- свой виджет (type "custom", cfg.custom — папка в ~/.config/glide-shell/widgets) ----
    readonly property var meta: type === "custom" && hub ? hub.custom(cfg.custom) : null
    readonly property var opts: {   // настройки виджета: значения из конфига, а нет — умолчания из widget.json
        var o = {}
        for (var s of (meta ? meta.settings : [])) o[s.key] = s.default
        return Object.assign(o, cfg.opts || {})
    }
    property string errText: ""
    // что получает свой виджет (см. examples/widgets и README)
    QtObject {
        id: wapi
        readonly property date now: wgt.hub ? wgt.hub.now : new Date()
        readonly property real k: wgt.k
        readonly property color tint: wgt.tint
        readonly property color sub: wgt.sub
        readonly property color accent: Theme.accent
        readonly property var theme: Theme
        readonly property string iconFont: Prefs.iconFont
        readonly property var weather: Weather
        readonly property var player: wgt.hub ? wgt.hub.player : null
        readonly property real cpu: wgt.hub ? wgt.hub.cpu : 0
        readonly property real mem: wgt.hub ? wgt.hub.mem : 0
        function run(argv) { Quickshell.execDetached(argv) }
        function openUrl(url) { Qt.openUrlExternally(url) }
    }
    function loadCustom() {
        if (type !== "custom") return
        if (!meta) { errText = Tr.t("Нет виджета «") + (cfg.custom || "") + Tr.t("» в ~/.config/glide-shell/widgets"); body.sourceComponent = errC; return }
        var url = "file://" + meta.dir + "/widget.qml?v=" + meta.mtime   // ?v — свежая версия после правки файла
        var comp = Qt.createComponent(url)
        if (comp.status === Component.Error) { errText = comp.errorString().trim(); body.sourceComponent = errC; return }
        errText = ""
        body.setSource(url, { api: wapi, cfg: opts })
    }
    onMetaChanged: loadCustom()
    Component.onCompleted: loadCustom()
    Binding { target: body.item; property: "cfg"; value: wgt.opts; when: wgt.type === "custom" && wgt.errText === "" && !!body.item }
    Component {
        id: errC
        Rectangle {
            implicitWidth: Math.min(420, errBox.implicitWidth + 24); implicitHeight: errBox.implicitHeight + 20
            radius: Theme.r(12)
            color: Qt.rgba(Theme.background.r, Theme.background.g, Theme.background.b, 0.85)
            border.color: Theme.error
            Text {
                id: errBox
                x: 12; y: 10; width: Math.min(396, implicitWidth)
                text: Tr.t("Виджет «") + (wgt.meta ? wgt.meta.name : wgt.cfg.custom) + Tr.t("» не загрузился:\n") + wgt.errText
                color: Theme.text; font.pixelSize: 12; wrapMode: Text.WordWrap
            }
        }
    }

    Loader {
        id: body
        sourceComponent: wgt.type === "custom" ? null
                         : ({ clock: clockC, date: dateC, weather: weatherC, music: musicC, system: systemC, text: textC })[wgt.type] || clockC
        // мягкая тень под содержимым: статичная картинка, перерисовывается, только когда содержимое меняется
        layer.enabled: wgt.type !== "music" && wgt.type !== "system"
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: "#000000"
            shadowOpacity: 0.55
            shadowBlur: 0.6
            shadowVerticalOffset: 2
            blurMax: 24
        }
    }

    // ---- часы ----
    Component {
        id: clockC
        Column {
            Text {
                width: Math.max(implicitWidth, parent.width)
                horizontalAlignment: wgt.align
                text: Qt.formatTime(wgt.hub.now, wgt.cfg.seconds ? "HH:mm:ss" : "HH:mm")
                color: wgt.tint
                font.pixelSize: Math.round(96 * wgt.k)
                font.weight: wgt.cfg.bold ? Font.DemiBold : Font.Light
                font.features: ({ "tnum": 1 })
            }
            Text {
                visible: !!wgt.cfg.showDate
                width: Math.max(implicitWidth, parent.width)
                horizontalAlignment: wgt.align
                text: { var s = Tr.locale.toString(wgt.hub.now, "dddd, d MMMM"); return s.charAt(0).toUpperCase() + s.slice(1) }
                color: wgt.sub
                font.pixelSize: Math.round(20 * wgt.k)
            }
        }
    }
    // ---- дата ----
    Component {
        id: dateC
        Text {
            text: {
                var f = wgt.cfg.format === "short" ? "d MMMM" : wgt.cfg.format === "numeric" ? "dd.MM.yyyy" : "dddd, d MMMM"
                var s = Tr.locale.toString(wgt.hub.now, f)
                return s.charAt(0).toUpperCase() + s.slice(1)
            }
            horizontalAlignment: wgt.align
            color: wgt.tint
            font.pixelSize: Math.round(28 * wgt.k)
            font.weight: Font.Medium
        }
    }
    // ---- погода ----
    Component {
        id: weatherC
        Column {
            id: wcol
            spacing: Math.round(6 * wgt.k)
            readonly property var d: Weather.ok ? Weather.data : null
            Row {
                anchors.horizontalCenter: wgt.h === "c" ? parent.horizontalCenter : undefined
                anchors.right: wgt.h === "r" ? parent.right : undefined
                spacing: Math.round(12 * wgt.k)
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: wcol.d ? Weather.icon(wcol.d.now.code, wcol.d.now.day) : wgt.nf(0xF0599)
                    color: wgt.cfg.color === "text" || !wgt.cfg.color ? Theme.accent : wgt.tint
                    font.family: Prefs.iconFont
                    font.pixelSize: Math.round(48 * wgt.k)
                }
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    Text {
                        text: wcol.d ? Weather.temp(wcol.d.now.temp) : "—"
                        color: wgt.tint
                        font.pixelSize: Math.round(44 * wgt.k); font.weight: Font.Light
                    }
                    Text {
                        text: wcol.d ? Weather.describe(wcol.d.now.code)
                              + Tr.t(" · ощущается ") + Weather.temp(wcol.d.now.feels) : Tr.t("Погода выключена или не загрузилась")
                        color: wgt.sub
                        font.pixelSize: Math.round(14 * wgt.k)
                    }
                }
            }
            Row {   // прогноз на 3 дня
                visible: !!wgt.cfg.forecast && !!parent.d && !!parent.d.days
                anchors.horizontalCenter: wgt.h === "c" ? parent.horizontalCenter : undefined
                anchors.right: wgt.h === "r" ? parent.right : undefined
                spacing: Math.round(18 * wgt.k)
                Repeater {
                    model: wcol.d && wcol.d.days ? wcol.d.days.slice(1, 4) : []
                    delegate: Column {
                        required property var modelData
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: { var s = Tr.locale.toString(new Date(modelData.date + "T12:00"), "ddd"); return s.charAt(0).toUpperCase() + s.slice(1) }
                            color: wgt.sub; font.pixelSize: Math.round(13 * wgt.k)
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: Weather.icon(modelData.code, true)
                            color: wgt.tint; font.family: Prefs.iconFont; font.pixelSize: Math.round(22 * wgt.k)
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: Math.round(modelData.max) + "° / " + Math.round(modelData.min) + "°"
                            color: wgt.tint; font.pixelSize: Math.round(13 * wgt.k)
                        }
                    }
                }
            }
        }
    }
    // ---- музыка: карточка с обложкой и кнопками ----
    Component {
        id: musicC
        Rectangle {
            id: card
            readonly property var pl: wgt.hub.player
            implicitWidth: Math.round(360 * wgt.k)
            implicitHeight: Math.round(84 * wgt.k)
            radius: Theme.r(Math.round(22 * wgt.k))
            color: Qt.rgba(Theme.background.r, Theme.background.g, Theme.background.b, 0.72)
            border.color: Theme.outline
            ClippingRectangle {
                x: Math.round(10 * wgt.k); anchors.verticalCenter: parent.verticalCenter
                width: Math.round(64 * wgt.k); height: width; radius: Theme.r(Math.round(14 * wgt.k))
                color: Theme.surfaceHigh
                Text { anchors.centerIn: parent; text: "♫"; color: Theme.accent; font.pixelSize: Math.round(26 * wgt.k) }
                Image {
                    anchors.fill: parent
                    source: card.pl ? (card.pl.trackArtUrl || "") : ""
                    sourceSize.width: 128; sourceSize.height: 128
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    visible: status === Image.Ready
                }
            }
            Column {
                x: Math.round(86 * wgt.k); anchors.verticalCenter: parent.verticalCenter
                width: parent.width - x - ctl.width - Math.round(12 * wgt.k)
                Text {
                    width: parent.width
                    text: card.pl ? (card.pl.trackTitle || card.pl.identity || "") : ""
                    color: Theme.text; font.pixelSize: Math.round(14 * wgt.k); font.bold: true
                    elide: Text.ElideRight
                }
                Text {
                    width: parent.width
                    text: card.pl ? (card.pl.trackArtist || card.pl.identity || "") : ""
                    color: Theme.textSecondary; font.pixelSize: Math.round(12 * wgt.k)
                    elide: Text.ElideRight
                }
            }
            Row {
                id: ctl
                anchors.right: parent.right; anchors.rightMargin: Math.round(8 * wgt.k)
                anchors.verticalCenter: parent.verticalCenter
                MusicBtn { k: wgt.k; glyph: wgt.nf(0xF04AE); on: !!card.pl && card.pl.canGoPrevious; onClicked: card.pl.previous() }
                MusicBtn {
                    k: wgt.k
                    glyph: card.pl && card.pl.isPlaying ? wgt.nf(0xF03E4) : wgt.nf(0xF040A)
                    on: !!card.pl && card.pl.canTogglePlaying
                    onClicked: card.pl.togglePlaying()
                }
                MusicBtn { k: wgt.k; glyph: wgt.nf(0xF04AD); on: !!card.pl && card.pl.canGoNext; onClicked: card.pl.next() }
            }
        }
    }
    component MusicBtn: Rectangle {
        id: mb
        property string glyph
        property bool on: true
        property real k: 1
        signal clicked()
        width: Math.round(36 * mb.k); height: width; radius: width / 2
        color: !on ? "transparent" : mbm.pressed ? Theme.surfacePressed : mbm.containsMouse ? Theme.surfaceHigher : "transparent"
        opacity: on ? 1 : Theme.disabledOpacity
        scale: mbm.pressed && on ? 0.88 : 1
        Behavior on color { ColorAnimation { duration: Prefs.ms(120) } }
        Behavior on scale { NumberAnimation { duration: Prefs.ms(140); easing.type: Easing.OutBack } }
        Text { anchors.centerIn: parent; text: mb.glyph; color: Theme.text; font.family: Prefs.iconFont; font.pixelSize: Math.round(18 * mb.k) }
        MouseArea { id: mbm; anchors.fill: parent; hoverEnabled: true; cursorShape: mb.on ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: if (mb.on) mb.clicked() }
    }
    // ---- система: процессор и память ----
    Component {
        id: systemC
        Rectangle {
            implicitWidth: Math.round(240 * wgt.k)
            implicitHeight: col.implicitHeight + Math.round(24 * wgt.k)
            radius: Theme.r(Math.round(20 * wgt.k))
            color: Qt.rgba(Theme.background.r, Theme.background.g, Theme.background.b, 0.72)
            border.color: Theme.outline
            Column {
                id: col
                x: Math.round(14 * wgt.k); y: Math.round(12 * wgt.k)
                width: parent.width - 2 * x
                spacing: Math.round(10 * wgt.k)
                Repeater {
                    model: [{ name: Tr.t("Процессор"), glyph: 0xF0EE0, v: wgt.hub.cpu, label: Math.round(wgt.hub.cpu) + "%" },
                            { name: Tr.t("Память"), glyph: 0xF035B, v: wgt.hub.mem,
                              label: Tr.num(wgt.hub.memUsedGb, 1) + Tr.t(" из ") + Math.round(wgt.hub.memTotalGb) + Tr.t(" ГБ") }]
                    delegate: Column {
                        required property var modelData
                        width: col.width
                        spacing: Math.round(5 * wgt.k)
                        Item {
                            width: parent.width; height: Math.round(18 * wgt.k)
                            Text { anchors.verticalCenter: parent.verticalCenter; text: wgt.nf(modelData.glyph) + "  " + modelData.name
                                   color: Theme.textSecondary; font.family: Prefs.iconFont; font.pixelSize: Math.round(13 * wgt.k) }
                            Text { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; text: modelData.label
                                   color: Theme.text; font.pixelSize: Math.round(13 * wgt.k); font.features: ({ "tnum": 1 }) }
                        }
                        Rectangle {
                            width: parent.width; height: Math.round(6 * wgt.k); radius: height / 2
                            color: Theme.surfaceHigh
                            Rectangle {
                                width: parent.width * Math.min(1, modelData.v / 100); height: parent.height; radius: parent.radius
                                color: modelData.v > 85 ? Theme.error : Theme.accent
                                Behavior on width { NumberAnimation { duration: Prefs.ms(400); easing.type: Easing.OutCubic } }
                            }
                        }
                    }
                }
            }
        }
    }
    // ---- свой текст ----
    Component {
        id: textC
        Text {
            text: wgt.cfg.text || Tr.t("Текст")
            width: Math.min(implicitWidth, Math.round(640 * wgt.k))
            wrapMode: Text.WordWrap
            horizontalAlignment: wgt.align
            color: wgt.tint
            font.pixelSize: Math.round(24 * wgt.k)
            font.weight: wgt.cfg.bold ? Font.DemiBold : Font.Normal
            font.italic: !!wgt.cfg.italic
        }
    }
}
