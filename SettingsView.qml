import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

// Экран настроек: поведение и вид панели, включение плагинов, порядок категорий.
ColumnLayout {
    id: sv
    property var panel
    spacing: 14

    // ---- элементы ----
    component Header: Text {
        color: Theme.textSecondary
        font.pixelSize: Theme.fs(12)
        font.bold: true
        Layout.topMargin: 4
    }

    component Switch: Rectangle {
        id: sw
        property bool checked
        signal toggled()
        // переключатель MD3: выключен — контур и маленький бегунок, включён — акцент и бегунок крупнее
        // наведение — ярче, нажатие — бегунок крупнее (как в MD3), недоступен — полупрозрачный
        implicitWidth: 44; implicitHeight: 26; radius: Theme.r(13)
        opacity: enabled ? 1 : Theme.disabledOpacity
        color: checked ? (swm.containsMouse ? Theme.accentLight : Prefs.accent) : swm.containsMouse ? Theme.surfaceHigher : Theme.surfaceHigh
        border.width: 2
        border.color: checked ? color : swm.containsMouse ? Theme.textVariant : Theme.textMuted
        Behavior on color { ColorAnimation { duration: Prefs.ms(160) } }
        Behavior on border.color { ColorAnimation { duration: Prefs.ms(160) } }
        Rectangle {
            width: swm.pressed ? 20 : sw.checked ? 18 : 12; height: width; radius: width / 2
            anchors.verticalCenter: parent.verticalCenter
            x: sw.checked ? parent.width - width - 4 : swm.pressed ? 3 : 7
            color: sw.checked ? Theme.accentText : swm.containsMouse ? Theme.textVariant : Theme.textMuted
            Behavior on width { NumberAnimation { duration: Prefs.ms(180); easing.type: Easing.OutBack } }
            Behavior on x { NumberAnimation { duration: Prefs.ms(180); easing.type: Easing.OutBack } }
            Behavior on color { ColorAnimation { duration: Prefs.ms(160) } }
        }
        MouseArea { id: swm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: sw.toggled() }
    }

    component ToggleRow: RowLayout {
        id: tr
        property string label
        property string hint
        property string icon          // значок Nerd Font слева (необязательно)
        property bool checked
        signal toggled()
        Layout.fillWidth: true
        spacing: 10
        Text {
            visible: tr.icon !== ""
            Layout.preferredWidth: 20
            Layout.alignment: Qt.AlignTop
            Layout.topMargin: 1
            text: tr.icon
            color: tr.checked ? Prefs.accent : Theme.textMuted
            font.family: Prefs.iconFont
            font.pixelSize: Theme.fs(15)
            Behavior on color { ColorAnimation { duration: Prefs.ms(160) } }
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 1
            Text { text: tr.label; color: Theme.text; Layout.fillWidth: true; elide: Text.ElideRight }
            Text { visible: tr.hint !== ""; text: tr.hint; color: Theme.textMuted; font.pixelSize: Theme.fs(11)
                   Layout.fillWidth: true; wrapMode: Text.WordWrap }
        }
        Switch { checked: tr.checked; onToggled: tr.toggled() }
    }

    // Сегменты: [{label, value}]; выбранный подсвечивается переезжающей плашкой
    // строка острова в настройках: ↑↓ — порядок, значок, название, выключатель (у записи экрана — всегда)
    readonly property var islandMeta: ({
        osd:   { glyph: 0xF057E, label: Tr.t("Громкость и яркость"), hint: Tr.t("А также микрофон, профиль питания и выход звука"), pref: "islandOsd" },
        flash: { glyph: 0xF012C, label: Tr.t("Подтверждения действий"), hint: Tr.t("«✓ название» после действия"), pref: "islandFlash" },
        rec:   { glyph: 0xF044A, label: Tr.t("Запись экрана"), hint: Tr.t("Всегда — чтобы идущая запись не забылась"), pref: "" },
        notif: { glyph: 0xF009A, label: Tr.t("Уведомления"), hint: Tr.t("История и колокольчик в баре — всегда"), pref: "islandNotif" },
        music: { glyph: 0xF075A, label: Tr.t("Музыка"), hint: Tr.t("Обложка и эквалайзер; наведение — управление"), pref: "islandMusic" },
        timer: { glyph: 0xF13AB, label: Tr.t("Таймер"), hint: Tr.t("Кольцо и остаток; наведение — отмена"), pref: "islandTimer" }
    })
    // элементы боковых островов бара
    readonly property var barMeta: ({
        power: { glyph: 0xF0425, label: Tr.t("Кнопка питания") }, workspaces: { glyph: 0xF056E, label: Tr.t("Воркспейсы") },
        window: { glyph: 0xF003B, label: Tr.t("Активное окно") }, layout: { glyph: 0xF030C, label: Tr.t("Раскладка клавиатуры") },
        cpu: { glyph: 0xF0EE0, label: Tr.t("Процессор") }, mem: { glyph: 0xF035B, label: Tr.t("Память") },
        clipboard: { glyph: 0xF014C, label: Tr.t("Буфер обмена") }, notifications: { glyph: 0xF009A, label: Tr.t("Уведомления") },
        battery: { glyph: 0xF0079, label: Tr.t("Батарея") }, phone: { glyph: 0xF011C, label: Tr.t("Телефон (KDE Connect)") },
        vpn: { glyph: 0xF0565, label: Tr.t("VPN (когда включён)") }, awake: { glyph: 0xF0176, label: Tr.t("Значок «не засыпать»") },
        control: { glyph: 0xF062E, label: Tr.t("Центр управления") }, tray: { glyph: 0xF01D8, label: Tr.t("Трей") },
        volume: { glyph: 0xF057E, label: Tr.t("Громкость"), hint: Tr.t("колесо — громче/тише, щелчок — без звука") },
        mic: { glyph: 0xF036C, label: Tr.t("Микрофон"), hint: Tr.t("щелчок — выключить/включить") },
        bluetooth: { glyph: 0xF00B1, label: "Bluetooth", hint: Tr.t("пока подключено устройство, с его зарядом") },
        night: { glyph: 0xF0594, label: Tr.t("Ночной свет"), hint: Tr.t("щелчок — включить/выключить") },
        weather: { glyph: 0xF0590, label: Tr.t("Погода"), hint: Tr.t("температура; щелчок — «Сегодня»") },
        powerprofile: { glyph: 0xF0A7A, label: Tr.t("Профиль питания"), hint: Tr.t("щелчок — экономия → баланс → производительность") },
        screenshot: { glyph: 0xF0100, label: Tr.t("Скриншот"), hint: Tr.t("снять область") }
    })
    function setBarPlace(id, place) { Prefs.set("barItems", Prefs.barItems.map(x => x.id === id ? ({ id: id, place: place }) : x)) }
    function moveBarItem(i, d) {   // соседний элемент того же острова
        var o = Prefs.barItems.slice(), pl = o[i].place, j = i + d
        while (j >= 0 && j < o.length && o[j].place !== pl) j += d
        if (j < 0 || j >= o.length) return
        var t = o[i]; o[i] = o[j]; o[j] = t
        Prefs.set("barItems", o)
    }
    component BarItemRow: Rectangle {
        id: bi
        property var it
        property int pos
        readonly property var meta: sv.barMeta[it.id] || ({})
        readonly property bool on: it.place !== "off"
        implicitHeight: 48
        radius: Theme.r(14)
        color: Theme.surface
        border.color: Theme.outline
        opacity: on ? 1 : 0.72
        Behavior on opacity { NumberAnimation { duration: Prefs.ms(160) } }
        Column {
            x: 6; anchors.verticalCenter: parent.verticalCenter
            ArrowBtn { glyph: 0xF0143; enabled: bi.on && Prefs.barItems.slice(0, bi.pos).some(x => x.place === bi.it.place); onClicked: sv.moveBarItem(bi.pos, -1) }
            ArrowBtn { glyph: 0xF0140; enabled: bi.on && Prefs.barItems.slice(bi.pos + 1).some(x => x.place === bi.it.place); onClicked: sv.moveBarItem(bi.pos, 1) }
        }
        Text {
            x: 38; anchors.verticalCenter: parent.verticalCenter
            text: String.fromCodePoint(bi.meta.glyph || 0xF0337)
            color: bi.on ? Prefs.accent : Theme.textMuted
            font.family: Prefs.iconFont; font.pixelSize: Theme.fs(18)
            Behavior on color { ColorAnimation { duration: Prefs.ms(160) } }
        }
        Column {
            x: 68; anchors.verticalCenter: parent.verticalCenter
            width: parent.width - 68 - placeBox.width - 20
            spacing: 1
            Text { width: parent.width; text: bi.meta.label || bi.it.id; color: Theme.text; font.pixelSize: Theme.fs(13); elide: Text.ElideRight }
            Text { width: parent.width; visible: !!bi.meta.hint; text: bi.meta.hint || ""; color: Theme.textMuted; font.pixelSize: Theme.fs(11); elide: Text.ElideRight }
        }
        Row {   // место: левый остров / правый / скрыт
            id: placeBox
            anchors.right: parent.right; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter
            spacing: 2
            Repeater {
                model: [{ v: "left", l: Tr.t("левый") }, { v: "right", l: Tr.t("правый") }, { v: "off", l: Tr.t("скрыт") }]
                delegate: Rectangle {
                    id: pb
                    required property var modelData
                    readonly property bool sel: bi.it.place === modelData.v
                    width: pbT.implicitWidth + 16; height: 26; radius: 13
                    color: sel ? (pbMa.containsMouse ? Theme.accentLight : Prefs.accent)
                               : pbMa.pressed ? Theme.surfacePressed : pbMa.containsMouse ? Theme.surfaceHigher : Theme.surfaceHigh
                    scale: pbMa.pressed ? 0.94 : 1
                    Behavior on color { ColorAnimation { duration: Prefs.ms(120) } }
                    Behavior on scale { NumberAnimation { duration: Prefs.ms(140); easing.type: Easing.OutBack } }
                    Text { id: pbT; anchors.centerIn: parent; text: pb.modelData.l; font.pixelSize: Theme.fs(11)
                           color: pb.sel ? Theme.accentText : Theme.textSecondary }
                    MouseArea { id: pbMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: sv.setBarPlace(bi.it.id, pb.modelData.v) }
                }
            }
        }
    }
    // значки у часов
    readonly property var iconMeta: ({
        weather: { glyph: 0xF0590, label: Tr.t("Погода"), hint: Tr.t("значок и температура") },
        battery: { glyph: 0xF0079, label: Tr.t("Батарея"), hint: Tr.t("процент; красная — мало, зелёная — заряжается") },
        notif:   { glyph: 0xF009A, label: Tr.t("Непрочитанные"), hint: Tr.t("число, пока есть непрочитанные уведомления") },
        dnd:     { glyph: 0xF009B, label: Tr.t("Не беспокоить"), hint: Tr.t("пока включено") },
        vpn:     { glyph: 0xF0565, label: "VPN", hint: Tr.t("пока поднят туннель") },
        mic:     { glyph: 0xF036D, label: Tr.t("Микрофон выключен"), hint: Tr.t("пока микрофон заглушён") },
        volume:  { glyph: 0xF0581, label: Tr.t("Звук выключен"), hint: Tr.t("пока звук заглушён") },
        bt:      { glyph: 0xF00B1, label: "Bluetooth", hint: Tr.t("пока подключено устройство") },
        awake:   { glyph: 0xF0176, label: Tr.t("Не засыпать"), hint: Tr.t("пока включено") },
        night:   { glyph: 0xF0594, label: Tr.t("Ночной свет"), hint: Tr.t("пока включён") },
        layout:  { glyph: 0xF030C, label: Tr.t("Раскладка"), hint: Tr.t("EN / RU, если раскладок несколько") }
    })
    function iconOn(id) { var x = Prefs.islandIcons.find(i => i.id === id); return !!x && x.on }
    function setIcon(id, patch) { Prefs.set("islandIcons", Prefs.islandIcons.map(i => i.id === id ? Object.assign({}, i, patch) : i)) }
    function moveIcon(i, d) {
        var o = Prefs.islandIcons.slice(), j = i + d
        if (j < 0 || j >= o.length) return
        var t = o[i]; o[i] = o[j]; o[j] = t
        Prefs.set("islandIcons", o)
    }
    component IconSetting: Rectangle {
        id: is
        property var ic
        property int pos
        property int count
        readonly property var meta: sv.iconMeta[ic.id] || ({})
        implicitHeight: 48
        radius: Theme.r(14)
        color: Theme.surface
        border.color: Theme.outline
        opacity: ic.on ? 1 : 0.72
        Behavior on opacity { NumberAnimation { duration: Prefs.ms(160) } }
        Column {
            x: 6; anchors.verticalCenter: parent.verticalCenter
            ArrowBtn { glyph: 0xF0143; enabled: is.pos > 0; onClicked: sv.moveIcon(is.pos, -1) }
            ArrowBtn { glyph: 0xF0140; enabled: is.pos < is.count - 1; onClicked: sv.moveIcon(is.pos, 1) }
        }
        Text {
            x: 38; anchors.verticalCenter: parent.verticalCenter
            text: String.fromCodePoint(is.meta.glyph || 0xF0337)
            color: is.ic.on ? Prefs.accent : Theme.textMuted
            font.family: Prefs.iconFont; font.pixelSize: Theme.fs(18)
            Behavior on color { ColorAnimation { duration: Prefs.ms(160) } }
        }
        Column {
            x: 68; anchors.verticalCenter: parent.verticalCenter
            width: parent.width - 68 - 150
            spacing: 1
            Text { width: parent.width; text: is.meta.label || is.ic.id; color: Theme.text; font.pixelSize: Theme.fs(13); elide: Text.ElideRight }
            Text { width: parent.width; text: is.meta.hint || ""; color: Theme.textMuted; font.pixelSize: Theme.fs(11); elide: Text.ElideRight }
        }
        Rectangle {   // сторона от часов: щелчок меняет
            anchors.right: sw.left; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter
            width: sideT.implicitWidth + 20; height: 26; radius: 13
            color: sideMa.pressed ? Theme.surfacePressed : sideMa.containsMouse ? Theme.surfaceHigher : Theme.surfaceHigh
            border.color: Theme.outline
            scale: sideMa.pressed ? 0.94 : 1
            Behavior on color { ColorAnimation { duration: Prefs.ms(120) } }
            Behavior on scale { NumberAnimation { duration: Prefs.ms(140); easing.type: Easing.OutBack } }
            Text { id: sideT; anchors.centerIn: parent; text: is.ic.side === "left" ? Tr.t("← слева") : Tr.t("справа →")
                   color: Theme.textSecondary; font.pixelSize: Theme.fs(11) }
            MouseArea { id: sideMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: sv.setIcon(is.ic.id, { side: is.ic.side === "left" ? "right" : "left" }) }
        }
        Switch {
            id: sw
            anchors.right: parent.right; anchors.rightMargin: 10; anchors.verticalCenter: parent.verticalCenter
            checked: is.ic.on
            onToggled: sv.setIcon(is.ic.id, { on: !is.ic.on })
        }
    }
    function moveIsland(i, d) {
        var o = Prefs.islandOrder.slice(), j = i + d
        if (j < 0 || j >= o.length) return
        var t = o[i]; o[i] = o[j]; o[j] = t
        Prefs.set("islandOrder", o)
    }
    component IslandRow: Rectangle {
        id: ir
        property string kind
        property int pos
        property int count
        readonly property var meta: sv.islandMeta[kind] || ({})
        readonly property bool on: !meta.pref || Prefs[meta.pref]
        implicitHeight: 48
        radius: Theme.r(14)
        color: Theme.surface
        border.color: Theme.outline
        opacity: on ? 1 : 0.72
        Behavior on opacity { NumberAnimation { duration: Prefs.ms(160) } }
        Column {   // порядок
            x: 6; anchors.verticalCenter: parent.verticalCenter
            spacing: 0
            ArrowBtn { glyph: 0xF0143; enabled: ir.pos > 0; onClicked: sv.moveIsland(ir.pos, -1) }
            ArrowBtn { glyph: 0xF0140; enabled: ir.pos < ir.count - 1; onClicked: sv.moveIsland(ir.pos, 1) }
        }
        Text {
            x: 38; anchors.verticalCenter: parent.verticalCenter
            text: String.fromCodePoint(ir.meta.glyph || 0xF0337)
            color: ir.on ? Prefs.accent : Theme.textMuted
            font.family: Prefs.iconFont; font.pixelSize: Theme.fs(18)
            Behavior on color { ColorAnimation { duration: Prefs.ms(160) } }
        }
        Column {
            x: 68; anchors.verticalCenter: parent.verticalCenter
            width: parent.width - 68 - 64
            spacing: 1
            Text { width: parent.width; text: ir.meta.label || ir.kind; color: Theme.text; font.pixelSize: Theme.fs(13); elide: Text.ElideRight }
            Text { width: parent.width; text: ir.meta.hint || ""; color: Theme.textMuted; font.pixelSize: Theme.fs(11); elide: Text.ElideRight }
        }
        Switch {
            visible: !!ir.meta.pref
            anchors.right: parent.right; anchors.rightMargin: 10; anchors.verticalCenter: parent.verticalCenter
            checked: ir.on
            onToggled: Prefs.set(ir.meta.pref, !ir.on)
        }
    }
    component ArrowBtn: Rectangle {
        id: ab
        property int glyph
        signal clicked()
        width: 26; height: 20; radius: Theme.r(8)
        color: !ab.enabled ? "transparent" : abMa.pressed ? Theme.surfacePressed : abMa.containsMouse ? Theme.surfaceHigher : "transparent"
        opacity: ab.enabled ? 1 : Theme.disabledOpacity
        scale: abMa.pressed && ab.enabled ? 0.88 : 1
        Behavior on color { ColorAnimation { duration: Prefs.ms(120) } }
        Behavior on scale { NumberAnimation { duration: Prefs.ms(140); easing.type: Easing.OutBack } }
        Text { anchors.centerIn: parent; text: String.fromCodePoint(ab.glyph); color: Theme.textSecondary
               font.family: Prefs.iconFont; font.pixelSize: Theme.fs(14) }
        MouseArea { id: abMa; anchors.fill: parent; hoverEnabled: true
                    cursorShape: ab.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: if (ab.enabled) ab.clicked() }
    }

    // выбор из многих вариантов: чипы с переносом строк (ChoiceRow — пилюля на 2–5 вариантов)
    component ChipChoice: ColumnLayout {
        id: cc
        property string label
        property string hint
        property var options: []
        property var current
        signal picked(var value)
        Layout.fillWidth: true
        spacing: 6
        Text { text: cc.label; color: Theme.text }
        Flow {
            Layout.fillWidth: true
            spacing: 6
            Repeater {
                model: cc.options
                delegate: Rectangle {
                    id: chip
                    required property var modelData
                    readonly property bool on: modelData.value === cc.current
                    width: chipText.implicitWidth + 26; height: 30; radius: height / 2
                    color: on ? (chipMa.pressed ? Theme.accentPressed : chipMa.containsMouse ? Theme.accentLight : Prefs.accent)
                              : (chipMa.pressed ? Theme.surfacePressed : chipMa.containsMouse ? Theme.surfaceHigher : Theme.surface)
                    border.color: on ? "transparent" : Theme.outline
                    scale: chipMa.pressed ? 0.95 : 1
                    Behavior on color { ColorAnimation { duration: Prefs.ms(140) } }
                    Behavior on scale { NumberAnimation { duration: Prefs.ms(140); easing.type: Easing.OutBack } }
                    Text {
                        id: chipText
                        anchors.centerIn: parent
                        text: chip.modelData.label
                        color: chip.on ? Theme.accentText : Theme.textSecondary
                        font.pixelSize: Theme.fs(12)
                    }
                    MouseArea { id: chipMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: cc.picked(chip.modelData.value) }
                }
            }
        }
        Text {
            Layout.fillWidth: true
            visible: cc.hint !== ""
            text: cc.hint
            color: Theme.textMuted; font.pixelSize: Theme.fs(11)
            wrapMode: Text.WordWrap
        }
    }
    component ChoiceRow: ColumnLayout {
        id: cr
        property string label
        property var options: []
        property var current
        signal picked(var value)
        Layout.fillWidth: true
        spacing: 6
        readonly property int idx: {
            for (var i = 0; i < options.length; i++) if (options[i].value === current) return i
            return -1
        }
        Text { text: cr.label; color: Theme.text }
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 32
            radius: height / 2          // сегменты MD3 — пилюля
            color: Theme.surface
            border.color: Theme.outline
            readonly property real cell: (width - 4) / Math.max(1, cr.options.length)
            Rectangle {
                visible: cr.idx >= 0
                x: 2 + cr.idx * parent.cell
                y: 2
                width: parent.cell
                height: parent.height - 4
                radius: height / 2
                color: Prefs.accent
                Behavior on x { NumberAnimation { duration: Prefs.ms(220); easing.type: Easing.OutCubic } }
            }
            Row {
                x: 2
                anchors.verticalCenter: parent.verticalCenter
                Repeater {
                    model: cr.options
                    delegate: Item {
                        required property var modelData
                        required property int index
                        width: parent.parent.cell
                        height: 26
                        Text {
                            anchors.centerIn: parent
                            text: modelData.label
                            font.pixelSize: Theme.fs(12)
                            color: index === cr.idx ? Theme.accentText : (oma.containsMouse ? Theme.text : Theme.textVariant)
                            scale: oma.pressed ? 0.9 : 1
                            Behavior on color { ColorAnimation { duration: Prefs.ms(150) } }
                            Behavior on scale { NumberAnimation { duration: Prefs.ms(140); easing.type: Easing.OutBack } }
                        }
                        MouseArea {
                            id: oma
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: cr.picked(modelData.value)
                        }
                    }
                }
            }
        }
    }

    // Палитра: кружки цветов, выбранный обведён
    component ColorRow: ColumnLayout {
        id: clr
        property string label
        property var colors: []
        property color current
        signal picked(string value)
        Layout.fillWidth: true
        spacing: 8
        Text { text: clr.label; color: Theme.text }
        Row {
            spacing: 10
            Repeater {
                model: clr.colors
                delegate: Rectangle {
                    id: sw
                    required property var modelData
                    readonly property bool sel: Qt.colorEqual(clr.current, modelData)
                    width: 28; height: 28; radius: Theme.r(14)
                    color: "transparent"
                    border.width: 2
                    border.color: sel ? modelData : "transparent"
                    Behavior on border.color { ColorAnimation { duration: Prefs.ms(160) } }
                    Rectangle {
                        anchors.centerIn: parent
                        width: sw.sel ? 18 : 22; height: width; radius: width / 2
                        color: sw.modelData
                        scale: swm.pressed ? 0.85 : (swm.containsMouse ? 1.1 : 1)
                        Behavior on width { NumberAnimation { duration: Prefs.ms(180); easing.type: Easing.OutBack } }
                        Behavior on scale { NumberAnimation { duration: Prefs.ms(140); easing.type: Easing.OutBack } }
                    }
                    MouseArea { id: swm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: clr.picked(sw.modelData) }
                }
            }
        }
        Rectangle {   // свой цвет: #RRGGBB → Enter
            implicitWidth: 150; implicitHeight: 30; radius: Theme.r(15)
            color: Theme.surface
            border.width: hex.activeFocus ? 2 : 1
            border.color: hex.activeFocus ? clr.current : hexHover.hovered ? Theme.outlineHover : Theme.outline
            Behavior on border.color { ColorAnimation { duration: Prefs.ms(150) } }
            HoverHandler { id: hexHover; cursorShape: Qt.IBeamCursor }
            Rectangle { x: 8; anchors.verticalCenter: parent.verticalCenter; width: 16; height: 16; radius: 8; color: clr.current }
            TextInput {
                id: hex
                x: 32; width: parent.width - 40
                anchors.verticalCenter: parent.verticalCenter
                color: Theme.text; font.pixelSize: Theme.fs(12)
                font.family: "monospace"
                maximumLength: 7
                text: String(clr.current).slice(0, 7)
                validator: RegularExpressionValidator { regularExpression: /#?[0-9a-fA-F]{0,6}/ }
                onAccepted: {
                    var v = (text[0] === "#" ? text : "#" + text).toLowerCase()
                    if (/^#[0-9a-f]{6}$/.test(v)) clr.picked(v)
                }
            }
        }
    }

    // Текстовая настройка: подпись и поле; Enter — сохранить (поле подсвечивается, пока не сохранено)
    component TextRow: ColumnLayout {
        id: txr
        property string label
        property string placeholder
        property string value
        signal submitted(string value)
        Layout.fillWidth: true
        spacing: 6
        Text { text: txr.label; color: Theme.text }
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 34; radius: Theme.radiusSm
            color: Theme.surface
            // фокус — акцентная обводка 2, не сохранено (Enter не нажат) — акцентная 1, наведение — ярче
            border.width: tin.activeFocus ? 2 : 1
            border.color: tin.activeFocus || tin.text !== txr.value ? Prefs.accent : tinHover.hovered ? Theme.outlineHover : Theme.outline
            Behavior on border.color { ColorAnimation { duration: Prefs.ms(150) } }
            HoverHandler { id: tinHover; cursorShape: Qt.IBeamCursor }
            TextInput {
                id: tin
                anchors.left: parent.left; anchors.right: parent.right
                anchors.leftMargin: 10; anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                color: Theme.text; font.pixelSize: Theme.fs(13)
                clip: true
                text: txr.value
                onAccepted: txr.submitted(text.trim())
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: !tin.text
                    text: txr.placeholder
                    color: Theme.textMuted; font.pixelSize: Theme.fs(12)
                }
            }
        }
    }

    // кнопка со значком и подписью (действия в разделах)
    component ActionBtn: Rectangle {
        id: ab
        property string glyph
        property string text
        signal clicked()
        implicitWidth: abRow.implicitWidth + 24; implicitHeight: 32
        radius: Theme.r(16)
        opacity: enabled ? 1 : Theme.disabledOpacity
        color: abm.pressed ? Theme.surfacePressed : abm.containsMouse ? Theme.surfaceHigher : Theme.surface
        border.color: Theme.outline
        scale: abm.pressed ? 0.95 : 1
        Behavior on color { ColorAnimation { duration: Prefs.ms(120) } }
        Behavior on scale { NumberAnimation { duration: Prefs.ms(140); easing.type: Easing.OutBack } }
        Row {
            id: abRow
            anchors.centerIn: parent
            spacing: 6
            Text { anchors.verticalCenter: parent.verticalCenter; text: ab.glyph; color: Theme.textVariant
                   font.family: Prefs.iconFont; font.pixelSize: Theme.fs(15) }
            Text { anchors.verticalCenter: parent.verticalCenter; text: ab.text; color: Theme.text; font.pixelSize: Theme.fs(12) }
        }
        MouseArea { id: abm; anchors.fill: parent; hoverEnabled: true; enabled: ab.enabled
                    cursorShape: ab.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor; onClicked: ab.clicked() }
    }

    component SmallBtn: Rectangle {
        id: sb
        property string glyph
        property bool active: true
        signal clicked()
        implicitWidth: 26; implicitHeight: 26; radius: Theme.r(8)
        opacity: active ? 1 : Theme.disabledOpacity
        color: !active ? "transparent" : sbm.pressed ? Theme.surfacePressed : sbm.containsMouse ? Theme.surfaceHigher : "transparent"
        scale: sbm.pressed && active ? 0.88 : 1
        Behavior on color { ColorAnimation { duration: Prefs.ms(110) } }
        Behavior on scale { NumberAnimation { duration: Prefs.ms(110) } }
        Text { anchors.centerIn: parent; text: sb.glyph; color: Theme.text; font.pixelSize: Theme.fs(12) }
        MouseArea { id: sbm; anchors.fill: parent; hoverEnabled: true; cursorShape: sb.active ? Qt.PointingHandCursor : Qt.ArrowCursor; onClicked: if (sb.active) sb.clicked() }
    }

    readonly property bool island: Prefs.style === "island"

    // ---- навигация: разделы вкладками; открыт один раздел, последний выбранный запоминается ----
    readonly property string page: panel && panel.settingsPage ? panel.settingsPage : "look"
    readonly property var pages: [
        { id: "look", label: Tr.t("Вид"), icon: 0xF03D8 }, { id: "island", label: Tr.t("Остров"), icon: 0xF0402 },
        { id: "bar", label: Tr.t("Бар"), icon: 0xF0E73 }, { id: "dock", label: Tr.t("Док"), icon: 0xF10A9 },
        { id: "notify", label: Tr.t("Уведомления"), icon: 0xF009A }, { id: "lock", label: Tr.t("Блокировка"), icon: 0xF033E },
        { id: "wall", label: Tr.t("Обои"), icon: 0xF024F }, { id: "widgets", label: Tr.t("Виджеты"), icon: 0xF0954 },
        { id: "weather", label: Tr.t("Погода"), icon: 0xF0595 }, { id: "behavior", label: Tr.t("Поведение"), icon: 0xF0493 },
        { id: "niri", label: Tr.t("Устройства"), icon: 0xF0379 }, { id: "plugins", label: Tr.t("Плагины"), icon: 0xF0431 }
    ]
    Flow {
        Layout.fillWidth: true
        spacing: 6
        Repeater {
            model: sv.pages
            delegate: Rectangle {
                id: tab
                required property var modelData
                readonly property bool on: sv.page === modelData.id
                width: tabRow.implicitWidth + 22; height: 30; radius: Theme.r(15)
                color: on ? Prefs.accent : tabMouse.pressed ? Theme.surfacePressed : tabMouse.containsMouse ? Theme.surfaceHigher : Theme.surfaceHigh
                scale: tabMouse.pressed ? 0.95 : 1
                Behavior on color { ColorAnimation { duration: Prefs.ms(140) } }
                Behavior on scale { NumberAnimation { duration: Prefs.ms(140); easing.type: Easing.OutBack } }
                Row {
                    id: tabRow
                    anchors.centerIn: parent
                    spacing: 6
                    Text {
                        Behavior on color { ColorAnimation { duration: Prefs.ms(140) } }
                        anchors.verticalCenter: parent.verticalCenter
                        text: String.fromCodePoint(tab.modelData.icon)
                        color: tab.on ? Theme.accentText : Theme.textVariant
                        font.family: Prefs.iconFont; font.pixelSize: Theme.fs(13)
                    }
                    Text {
                        Behavior on color { ColorAnimation { duration: Prefs.ms(140) } }
                        anchors.verticalCenter: parent.verticalCenter
                        text: tab.modelData.label
                        color: tab.on ? Theme.accentText : Theme.text
                        font.pixelSize: Theme.fs(12)
                    }
                }
                MouseArea { id: tabMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: if (sv.panel) sv.panel.settingsPage = tab.modelData.id }
            }
        }
    }

    ColumnLayout {   // раздел «behavior»
        visible: sv.page === "behavior"
        Layout.fillWidth: true
        spacing: 14
        // ---- поведение ----
        Header { text: Tr.t("ПОВЕДЕНИЕ") }
        ChoiceRow {
            label: Tr.t("Предупреждать о низком заряде")
            options: [{ label: Tr.t("нет"), value: 0 }, { label: "15%", value: 15 }, { label: "20%", value: 20 }, { label: "30%", value: 30 }]
            current: Prefs.battWarn
            onPicked: (v) => Prefs.set("battWarn", v)
        }
        ChoiceRow {
            visible: Prefs.battWarn > 0
            label: Tr.t("Срочно — при")
            options: [{ label: "5%", value: 5 }, { label: "10%", value: 10 }, { label: "15%", value: 15 }]
            current: Prefs.battCrit
            onPicked: (v) => Prefs.set("battCrit", v)
        }
        ToggleRow {
            icon: String.fromCodePoint(0xF0214)
            label: Tr.t("Искать файлы")
            hint: Prefs.fileSearch ? Tr.t("В поиске панели — файлы и папки домашней папки (свой индекс, обновляется раз в 30 мин; скрытые не ищутся)")
                                   : Tr.t("Выключено")
            checked: Prefs.fileSearch
            onToggled: Prefs.set("fileSearch", !Prefs.fileSearch)
        }
        ChoiceRow {
            label: Tr.t("Искать в интернете")
            options: [{ label: "DuckDuckGo", value: "duckduckgo" }, { label: "Google", value: "google" },
                      { label: Tr.t("Яндекс"), value: "yandex" }, { label: "Bing", value: "bing" }, { label: Tr.t("нет"), value: "off" }]
            current: Prefs.webSearch
            onPicked: (v) => Prefs.set("webSearch", v)
        }
        ChoiceRow {
            label: NightLight.available ? Tr.t("Ночной свет") : Tr.t("Ночной свет — нужен wlsunset (sudo pacman -S wlsunset)")
            options: [{ label: Tr.t("выкл"), value: "off" }, { label: Tr.t("всегда"), value: "on" },
                      { label: Tr.t("от заката до восхода"), value: "auto" }]
            current: Prefs.night
            onPicked: (v) => NightLight.setMode(v)
        }
        ChoiceRow {
            visible: Prefs.night !== "off"
            label: Tr.t("Теплота экрана")
            options: [{ label: Tr.t("слабо"), value: 5500 }, { label: Tr.t("средне"), value: 4500 },
                      { label: Tr.t("сильно"), value: 3500 }, { label: Tr.t("очень сильно"), value: 2700 }]
            current: Prefs.nightTemp
            onPicked: (v) => Prefs.set("nightTemp", v)
        }
        ToggleRow {
            icon: String.fromCodePoint(0xF011C)
            label: Tr.t("KDE Connect (телефон)")
            hint: Prefs.kdeconnect ? Tr.t("Категория «Телефон», заряд в баре, «На телефон» для выделенного текста") : Tr.t("Выключено")
            checked: Prefs.kdeconnect
            onToggled: Prefs.set("kdeconnect", !Prefs.kdeconnect)
        }
        ChoiceRow {
            label: Tr.t("Вид панели")
            options: [{ label: Tr.t("остров сверху"), value: "island" }, { label: Tr.t("рейка у края"), value: "edge" }]
            current: Prefs.style
            onPicked: (v) => Prefs.set("style", v)
        }
        ToggleRow {
            label: Tr.t("Свой верхний бар")
            hint: Prefs.bar ? Tr.t("Капсулы слева и справа, остров с часами по центру. Выключишь — верни бар DMS, иначе бара не будет совсем")
                            : Tr.t("Выключен. Если бар DMS тоже выключен, сверху сейчас пусто")
            checked: Prefs.bar
            onToggled: Prefs.set("bar", !Prefs.bar)
        }
        ToggleRow {
            label: sv.island ? Tr.t("Открывать наведением на остров") : Tr.t("Открывать наведением на край")
            hint: sv.island ? Tr.t("Когда в острове нет музыки или таймера; иначе наведение показывает управление")
                            : Tr.t("Правый край экрана, по центру")
            checked: Prefs.edgeTrigger
            onToggled: Prefs.set("edgeTrigger", !Prefs.edgeTrigger)
        }
        ToggleRow {
            visible: sv.island ? !Prefs.bar : Prefs.edgeTrigger   // с баром остров с часами виден всегда
            label: sv.island ? Tr.t("Показывать остров в покое") : Tr.t("Показывать полоску у края")
            hint: sv.island ? Tr.t("Выключено — остров появляется только с активностью или при наведении") : ""
            checked: Prefs.edgePill
            onToggled: Prefs.set("edgePill", !Prefs.edgePill)
        }
        ChoiceRow {
            visible: Prefs.edgeTrigger
            label: Tr.t("Задержка перед открытием")
            options: [{ label: Tr.t("сразу"), value: 0 }, { label: Tr.t("0.12 с"), value: 120 },
                      { label: Tr.t("0.3 с"), value: 300 }, { label: Tr.t("0.6 с"), value: 600 }]
            current: Prefs.hoverDelay
            onPicked: (v) => Prefs.set("hoverDelay", v)
        }

    }
    ColumnLayout {   // раздел «look»
        visible: sv.page === "look"
        Layout.fillWidth: true
        spacing: 14
        // ---- вид ----
        Header { text: Tr.t("ВИД") }
        ChoiceRow {   // язык интерфейса: «авто» — по системе ($LANG)
            label: "Язык / Language"   // без перевода: видно на любом языке
            options: [{ label: Tr.t("авто"), value: "auto" }, { label: "Русский", value: "ru" }, { label: "English", value: "en" }]   // без перевода
            current: Prefs.lang
            onPicked: (v) => Prefs.set("lang", v)
        }
        ActionBtn {
            glyph: String.fromCodePoint(0xF0674)
            text: Tr.t("Мастер первого запуска")
            onClicked: Quickshell.execDetached(["qs", "-c", "glide-shell", "ipc", "call", "panel", "welcome", ""])
        }
        ChoiceRow {
            label: Tr.t("Анимации")
            options: [{ label: Tr.t("выкл"), value: 0 }, { label: Tr.t("быстрые"), value: 0.6 },
                      { label: Tr.t("обычные"), value: 1 }, { label: Tr.t("плавные"), value: 1.5 }]
            current: Prefs.anim
            onPicked: (v) => Prefs.set("anim", v)
        }
        ColorRow {
            label: Tr.t("Акцентный цвет (или свой — HEX и Enter)")
            colors: ["#7b61ff", "#4f7cff", "#2bb3e6", "#1fbf9f", "#34c77b", "#f5a623", "#ff7a45", "#ef5b8d"]
            current: Prefs.accent
            onPicked: (v) => Prefs.set("accent", v)
        }
        ChoiceRow {
            label: Tr.t("Тон фона")
            options: [{ label: Tr.t("графит Glide"), value: "glide" }, { label: Tr.t("AMOLED-чёрный"), value: "amoled" },
                      { label: Tr.t("мягкий"), value: "soft" }]
            current: Prefs.themeTone
            onPicked: (v) => Prefs.set("themeTone", v)
        }
        ChoiceRow {
            label: Tr.t("Скругления")
            options: [{ label: Tr.t("острые"), value: 0.35 }, { label: Tr.t("сдержанные"), value: 0.7 },
                      { label: Tr.t("обычные"), value: 1 }, { label: Tr.t("круглые"), value: 1.4 }]
            current: Prefs.themeRadius
            onPicked: (v) => Prefs.set("themeRadius", v)
        }
        ChoiceRow {
            label: Tr.t("Размер текста")
            options: [{ label: Tr.t("мельче"), value: 0.9 }, { label: Tr.t("обычный"), value: 1 }, { label: Tr.t("крупнее"), value: 1.1 }]
            current: Prefs.themeFont
            onPicked: (v) => Prefs.set("themeFont", v)
        }
        ChoiceRow {
            label: Tr.t("Фон бара, острова, дока и панели")
            options: [{ label: Tr.t("сплошной"), value: 1 }, { label: "90%", value: 0.9 }, { label: "80%", value: 0.8 }, { label: "70%", value: 0.7 }]
            current: Prefs.themeOpacity
            onPicked: (v) => Prefs.set("themeOpacity", v)
        }
        ChoiceRow {
            visible: Prefs.anim > 0
            label: Tr.t("Упругость анимаций острова")
            options: [{ label: Tr.t("без отскока"), value: 0 }, { label: Tr.t("мягкая"), value: 0.5 },
                      { label: Tr.t("обычная"), value: 1 }, { label: Tr.t("упругая"), value: 1.6 }]
            current: Prefs.bounce
            onPicked: (v) => Prefs.set("bounce", v)
        }
        ChoiceRow {
            label: Tr.t("Ширина панели")
            options: [{ label: Tr.t("узкая"), value: 340 }, { label: Tr.t("обычная"), value: 380 },
                      { label: Tr.t("широкая"), value: 440 }, { label: Tr.t("очень"), value: 520 }]
            current: Prefs.width
            onPicked: (v) => Prefs.set("width", v)
        }
        ChoiceRow {
            label: Tr.t("Категорий на странице рейки")
            options: [{ label: "4", value: 4 }, { label: "5", value: 5 }, { label: "6", value: 6 },
                      { label: "8", value: 8 }, { label: "10", value: 10 }]
            current: Prefs.perPage
            onPicked: (v) => Prefs.set("perPage", v)
        }
        ToggleRow {
            label: Tr.t("Затемнять фон")
            checked: Prefs.dim
            onToggled: Prefs.set("dim", !Prefs.dim)
        }

    }
    ColumnLayout {   // раздел «island»
        visible: sv.page === "island"
        Layout.fillWidth: true
        spacing: 14
        // ---- остров ----
        Header { visible: sv.island || Prefs.bar; text: Tr.t("ОСТРОВ") }
        ToggleRow {
            visible: sv.island && !Prefs.bar
            label: Tr.t("Поверх бара")
            hint: Tr.t("Выключено — остров стоит сразу под верхним баром")
            checked: Prefs.islandOverBar
            onToggled: Prefs.set("islandOverBar", !Prefs.islandOverBar)
        }
        ChoiceRow {
            visible: Prefs.bar
            label: Tr.t("Активности в острове")
            options: [{ label: Tr.t("компактно"), value: "inline" }, { label: Tr.t("прижать к верху"), value: "raise" },
                      { label: Tr.t("строками"), value: "stack" }]
            current: Prefs.islandMode
            onPicked: (v) => Prefs.set("islandMode", v)
        }
        Text {
            visible: Prefs.bar
            Layout.fillWidth: true
            text: Prefs.islandMode === "inline" ? Tr.t("Музыка, уведомления и прочее — в строке часов: остров не ниже бара. Подробности — при наведении")
                : Prefs.islandMode === "raise" ? Tr.t("Строками под часами, но на время активности остров поднимается вплотную к краю экрана")
                : Tr.t("Каждая активность — отдельной строкой под часами")
            color: Theme.textMuted; font.pixelSize: Theme.fs(11)
            wrapMode: Text.WordWrap
        }
        // ---- строка часов (верх острова) ----
        Header { visible: Prefs.bar; text: Tr.t("СТРОКА ЧАСОВ") }
        ChoiceRow {
            visible: Prefs.bar
            label: Tr.t("Дата у часов")
            options: [{ label: Tr.t("пн, 19 октября"), value: "long" }, { label: Tr.t("пн 19.10"), value: "short" },
                      { label: Tr.t("без даты"), value: "none" }]
            current: Prefs.clockDate
            onPicked: (v) => Prefs.set("clockDate", v)
        }
        ToggleRow {
            visible: Prefs.bar
            icon: String.fromCodePoint(0xF051B)
            label: Tr.t("Секунды на часах")
            checked: Prefs.clockSeconds
            onToggled: Prefs.set("clockSeconds", !Prefs.clockSeconds)
        }
        // ---- значки у часов: какие, с какой стороны, в каком порядке ----
        Header { visible: Prefs.bar; text: Tr.t("ЗНАЧКИ У ЧАСОВ") }
        Text {
            visible: Prefs.bar
            Layout.fillWidth: true
            text: Tr.t("Видны, только когда есть что показать (VPN — пока он включён, микрофон — пока выключен и т. п.). ←→ — сторона от часов, ↑↓ — порядок")
            color: Theme.textMuted; font.pixelSize: Theme.fs(11)
            wrapMode: Text.WordWrap
        }
        Repeater {
            model: Prefs.bar ? Prefs.islandIcons : []
            delegate: IconSetting {
                required property var modelData
                required property int index
                Layout.fillWidth: true
                ic: modelData; pos: index; count: Prefs.islandIcons.length
            }
        }
        Item { visible: Prefs.bar; implicitHeight: 4 }
        // ---- строки острова: что показывать и в каком порядке (сверху — главнее в компактном виде) ----
        Header { visible: sv.island || Prefs.bar; text: Tr.t("СТРОКИ ОСТРОВА") }
        Text {
            visible: sv.island || Prefs.bar
            Layout.fillWidth: true
            text: Tr.t("Сверху вниз — как строки под часами; в компактном виде остров показывает первую, что сейчас есть")
            color: Theme.textMuted; font.pixelSize: Theme.fs(11)
            wrapMode: Text.WordWrap
        }
        Repeater {
            model: (sv.island || Prefs.bar) ? Prefs.islandOrder : []
            delegate: IslandRow {
                required property string modelData
                required property int index
                Layout.fillWidth: true
                kind: modelData; pos: index; count: Prefs.islandOrder.length
            }
        }
        Item { visible: sv.island || Prefs.bar; implicitHeight: 4 }
        ChoiceRow {
            visible: (sv.island || Prefs.bar) && Prefs.islandMusic
            label: Tr.t("Эквалайзер")
            options: [{ label: Tr.t("плавный"), value: "smooth" }, { label: Tr.t("экономный"), value: "eco" },
                      { label: Tr.t("неподвижный"), value: "off" }]
            current: Prefs.eqMode
            onPicked: (v) => Prefs.set("eqMode", v)
        }
        Text {
            visible: (sv.island || Prefs.bar) && Prefs.islandMusic && Prefs.eqMode === "smooth"
            Layout.fillWidth: true
            text: Tr.t("Плавный эквалайзер перерисовывает остров 60 раз в секунду, пока играет музыка (~10% ядра)")
            color: Theme.textMuted; font.pixelSize: Theme.fs(11)
            wrapMode: Text.WordWrap
        }
        ChoiceRow {
            visible: (sv.island || Prefs.bar) && Prefs.islandMusic
            label: Tr.t("Прятать музыку после паузы")
            options: [{ label: Tr.t("сразу"), value: 0 }, { label: Tr.t("6 с"), value: 6 },
                      { label: Tr.t("30 с"), value: 30 }, { label: Tr.t("не прятать"), value: -1 }]
            current: Prefs.musicGrace
            onPicked: (v) => Prefs.set("musicGrace", v)
        }
        ToggleRow {
            visible: sv.island || Prefs.bar
            icon: String.fromCodePoint(0xF0100)
            label: Tr.t("Камера и микрофон — цветом острова")
            hint: Tr.t("Пока приложение пишет камеру, остров зелёный, микрофон — янтарный")
            checked: Prefs.islandPrivacy
            onToggled: Prefs.set("islandPrivacy", !Prefs.islandPrivacy)
        }
        ChoiceRow {
            visible: (sv.island || Prefs.bar) && Prefs.islandFlash
            label: Tr.t("Сколько держать подтверждение")
            options: [{ label: Tr.t("1.5 с"), value: 1500 }, { label: Tr.t("2.2 с"), value: 2200 },
                      { label: Tr.t("3.5 с"), value: 3500 }, { label: Tr.t("5 с"), value: 5000 }]
            current: Prefs.flashMs
            onPicked: (v) => Prefs.set("flashMs", v)
        }

    }
    ColumnLayout {   // раздел «dock»
        visible: sv.page === "dock"
        Layout.fillWidth: true
        spacing: 14
        // ---- док ----
        Header { text: Tr.t("ДОК") }
        ToggleRow {
            icon: String.fromCodePoint(0xF05AF)
            label: Tr.t("Свой док")
            hint: Prefs.dock ? Tr.t("Правый клик по значку — окна и действия, колесо — листать окна") : Tr.t("Выключен")
            checked: Prefs.dock
            onToggled: Prefs.set("dock", !Prefs.dock)
        }
        ChoiceRow {
            visible: Prefs.dock
            label: Tr.t("Когда показывать")
            options: [{ label: Tr.t("умно"), value: "smart" }, { label: Tr.t("по наведению"), value: "autohide" },
                      { label: Tr.t("всегда"), value: "always" }]
            current: Prefs.dockMode
            onPicked: (v) => Prefs.set("dockMode", v)
        }
        Text {
            visible: Prefs.dock
            Layout.fillWidth: true
            text: Prefs.dockMode === "smart" ? Tr.t("Виден на пустом воркспейсе; иначе — подведи мышь к нижнему краю")
                : Prefs.dockMode === "autohide" ? Tr.t("Появляется, когда мышь у нижнего края экрана")
                : Tr.t("Всегда виден, окна не заходят под него")
            color: Theme.textMuted; font.pixelSize: Theme.fs(11)
            wrapMode: Text.WordWrap
        }
        ToggleRow {
            visible: Prefs.dock
            icon: String.fromCodePoint(0xF0379)
            label: Tr.t("Док на всех мониторах")
            hint: Quickshell.screens.length > 1 ? Tr.t("Выключено — только на мониторе с островом (в фокусе)")
                                                : Tr.t("Сейчас монитор один; для внешних")
            checked: Prefs.dockAllScreens
            onToggled: Prefs.set("dockAllScreens", !Prefs.dockAllScreens)
        }
        ChoiceRow {
            visible: Prefs.dock
            label: Tr.t("Размер значков")
            options: [{ label: Tr.t("мелкие"), value: 32 }, { label: Tr.t("средние"), value: 40 }, { label: Tr.t("крупные"), value: 48 }]
            current: Prefs.dockIcon
            onPicked: (v) => Prefs.set("dockIcon", v)
        }
        ToggleRow {
            visible: Prefs.dock
            icon: String.fromCodePoint(0xF056E)
            label: Tr.t("Кнопки «Приложения» и «Обзор»")
            checked: Prefs.dockButtons
            onToggled: Prefs.set("dockButtons", !Prefs.dockButtons)
        }

    }
    ColumnLayout {   // раздел «wall»: обои — HTML-сцена webpaper или картинка (и цвета темы из неё)
        id: wallPage
        visible: sv.page === "wall"
        Layout.fillWidth: true
        spacing: 14
        readonly property var wp: sv.panel ? sv.panel.wall : null
        readonly property bool img: Prefs.wallMode === "image"
        onVisibleChanged: if (visible && wp) wp.rescan()   // картинки могли добавить в папку
        Header { text: Tr.t("ОБОИ") }
        ChoiceRow {
            label: Tr.t("Обои")
            options: [{ label: Tr.t("сцена webpaper"), value: "scene" }, { label: Tr.t("картинка, GIF, видео"), value: "image" }]
            current: Prefs.wallMode
            onPicked: (v) => Prefs.set("wallMode", v)
        }
        ToggleRow {
            visible: !wallPage.img
            icon: String.fromCodePoint(0xF0E09)
            label: Tr.t("Сцена в цветах акцента")
            hint: Prefs.themeWallpaper ? Tr.t("Фон и текст — чёрный и белый, цветные — оттенки акцента")
                                       : Tr.t("Сцена в последней палитре DMS")
            checked: Prefs.themeWallpaper
            onToggled: Prefs.set("themeWallpaper", !Prefs.themeWallpaper)
        }
        TextRow {
            visible: !wallPage.img
            label: Tr.t("HTML-сцена (Enter — применить)")
            placeholder: Tr.t("как в службе webpaper (её index.html)")
            value: Prefs.wallScene
            onSubmitted: (v) => Prefs.set("wallScene", v)
        }
        TextRow {
            visible: wallPage.img
            label: Tr.t("Папка или файл")
            placeholder: "~/Изображения/Обои"
            value: Prefs.wallPath
            onSubmitted: (v) => Prefs.set("wallPath", v || "~/Изображения/Обои")
        }
        // картинки папки: щелчок — на экран
        Flow {
            id: thumbs
            visible: wallPage.img && !!wallPage.wp && wallPage.wp.files.length > 0
            Layout.fillWidth: true
            spacing: 8
            readonly property real cell: Math.floor((width - 2 * spacing) / 3)
            Repeater {
                model: wallPage.wp ? wallPage.wp.files : []
                delegate: Rectangle {
                    id: th
                    required property var modelData
                    readonly property bool on: wallPage.wp && wallPage.wp.current === modelData.path
                    width: thumbs.cell; height: Math.round(thumbs.cell * 9 / 16)
                    radius: Theme.r(10)
                    color: Theme.surface
                    border.width: on ? 2 : thm.containsMouse ? 1 : 0
                    border.color: on ? Prefs.accent : Theme.outlineHover
                    scale: thm.pressed ? 0.95 : 1
                    Behavior on scale { NumberAnimation { duration: Prefs.ms(140); easing.type: Easing.OutBack } }
                    Behavior on border.color { ColorAnimation { duration: Prefs.ms(140) } }
                    Image {
                        anchors.fill: parent
                        anchors.margins: th.on ? 3 : 0
                        source: "file://" + th.modelData.thumb
                        fillMode: Image.PreserveAspectCrop
                        sourceSize.width: 320
                        asynchronous: true
                    }
                    Rectangle {   // GIF и видео — метка в углу
                        visible: th.modelData.kind && th.modelData.kind !== "image"
                        anchors.right: parent.right; anchors.bottom: parent.bottom; anchors.margins: 6
                        width: kindText.implicitWidth + 10; height: 18; radius: Theme.r(9)
                        color: Qt.rgba(0, 0, 0, 0.6)
                        Text { id: kindText; anchors.centerIn: parent; color: "#ffffff"; font.pixelSize: Theme.fs(10); font.bold: true
                               text: th.modelData.kind === "gif" ? "GIF" : Tr.t("▶ видео") }
                    }
                    MouseArea { id: thm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: wallPage.wp.show(th.modelData.path) }
                }
            }
        }
        EmptyState {
            visible: wallPage.img && !!wallPage.wp && wallPage.wp.files.length === 0
            Layout.fillWidth: true
            glyph: 0xF024F
            text: Tr.t("Здесь пока нет картинок")
            hint: Tr.t("Положи картинки (jpg, png, webp), GIF или видео (mp4, webm) в ") + Prefs.wallPath + Tr.t(" — или укажи другую папку или файл")
        }
        RowLayout {
            visible: wallPage.img
            Layout.fillWidth: true
            spacing: 8
            ActionBtn { glyph: String.fromCodePoint(0xF0770); text: Tr.t("Открыть папку")
                        onClicked: if (sv.panel) sv.panel.runRaw(["sh", "-c", 'p=$1; case $p in "~"|"~/"*) p=$HOME${p#"~"};; esac; [ -f "$p" ] && p=${p%/*}; mkdir -p "$p" && exec xdg-open "$p"', "sh", Prefs.wallPath], "", "") }
            ActionBtn { glyph: String.fromCodePoint(0xF04AD); text: Tr.t("Следующая"); enabled: !!wallPage.wp && wallPage.wp.files.length > 1
                        onClicked: wallPage.wp.next() }
            Item { Layout.fillWidth: true }
        }
        ChoiceRow {
            visible: wallPage.img
            label: Tr.t("Менять картинку")
            options: [{ label: Tr.t("нет"), value: 0 }, { label: Tr.t("15 мин"), value: 15 }, { label: Tr.t("30 мин"), value: 30 },
                      { label: Tr.t("1 ч"), value: 60 }, { label: Tr.t("3 ч"), value: 180 }]
            current: Prefs.wallEvery
            onPicked: (v) => Prefs.set("wallEvery", v)
        }
        ChoiceRow {   // GIF и видео: перекодируются под экран с этой частотой (меньше — легче для процессора)
            visible: wallPage.img && !!wallPage.wp && wallPage.wp.files.some(f => f.kind && f.kind !== "image")
            label: Tr.t("Анимация: кадров в секунду")
            options: [{ label: "15", value: 15 }, { label: "24", value: 24 }, { label: "30", value: 30 }, { label: "60", value: 60 }]
            current: Prefs.wallFps
            onPicked: (v) => Prefs.set("wallFps", v)
        }
        ToggleRow {
            visible: wallPage.img && !!wallPage.wp && wallPage.wp.files.some(f => f.kind && f.kind !== "image")
            icon: String.fromCodePoint(0xF0079)
            label: Tr.t("От батареи — анимация на паузе")
            hint: Tr.t("И всегда стоит, пока обои закрыты окнами или экран заперт")
            checked: Prefs.wallBatteryPause
            onToggled: Prefs.set("wallBatteryPause", !Prefs.wallBatteryPause)
        }
        ChoiceRow {
            visible: wallPage.img
            label: Tr.t("Как вписать")
            options: [{ label: Tr.t("заполнить экран"), value: "fill" }, { label: Tr.t("целиком"), value: "fit" }]
            current: Prefs.wallFit
            onPicked: (v) => Prefs.set("wallFit", v)
        }
        ToggleRow {
            visible: wallPage.img
            icon: String.fromCodePoint(0xF03D8)
            label: Tr.t("Цвета темы из обоев")
            hint: Prefs.wallTheme ? Tr.t("Акцент и тон берутся из картинки — для оболочки, замка и экрана входа")
                                  : Tr.t("Акцент и тон — как выбраны в «Виде»")
            checked: Prefs.wallTheme
            onToggled: Prefs.set("wallTheme", !Prefs.wallTheme)
        }
    }
    // ---- виджеты рабочего стола (Prefs.widgets) ----
    readonly property var widgetTypes: [
        { type: "clock", name: Tr.t("Часы"), glyph: 0xF0954, def: { anchor: "c", dy: -60, size: 1, showDate: true } },
        { type: "date", name: Tr.t("Дата"), glyph: 0xF00ED, def: { anchor: "t", size: 1 } },
        { type: "weather", name: Tr.t("Погода"), glyph: 0xF0599, def: { anchor: "tr", size: 1, forecast: true } },
        { type: "music", name: Tr.t("Музыка"), glyph: 0xF075A, def: { anchor: "bl", size: 1 } },
        { type: "system", name: Tr.t("Система"), glyph: 0xF0EE0, def: { anchor: "br", size: 1 } },
        { type: "text", name: Tr.t("Текст"), glyph: 0xF0284, def: { anchor: "b", size: 1, text: Tr.t("Хорошего дня") } }
    ]
    function wType(t) { return widgetTypes.find(x => x.type === t) || widgetTypes[0] }
    readonly property var customs: sv.panel && sv.panel.desk ? sv.panel.desk.customs : []
    function wMeta(w) { return w.type === "custom" ? customs.find(x => x.id === w.custom) || null : null }
    function wName(w) { var m = wMeta(w); return w.type === "custom" ? (m ? m.name : w.custom + Tr.t(" (не найден)")) : wType(w.type).name }
    function wGlyph(w) { var m = wMeta(w); return w.type === "custom" ? (m && m.icon ? parseInt(m.icon, 16) : 0xF0B6F) : wType(w.type).glyph }
    function wAddCustom(id) {
        var w = { id: "w" + Date.now(), type: "custom", custom: id, screen: "", anchor: "c", dx: 0, dy: 0, size: 1, color: "text", opacity: 1, opts: {} }
        Prefs.set("widgets", Prefs.widgets.concat([w]))
        sv.openWidget = w.id
    }
    function wSetOpt(w, key, value) { var o = Object.assign({}, w.opts || {}); o[key] = value; wSet(w.id, "opts", o) }
    function wOpt(w, s) { var o = w.opts || {}; return o[s.key] !== undefined ? o[s.key] : s.default }
    function wAdd(t) {
        var w = Object.assign({ id: "w" + Date.now(), type: t, screen: "", dx: 0, dy: 0, color: "text", opacity: 1 }, wType(t).def)
        Prefs.set("widgets", Prefs.widgets.concat([w]))
        sv.openWidget = w.id
    }
    function wSet(id, key, value) {
        Prefs.set("widgets", Prefs.widgets.map(w => { if (w.id !== id) return w; var n = Object.assign({}, w); n[key] = value; return n }))
    }
    function wDel(id) { Prefs.set("widgets", Prefs.widgets.filter(w => w.id !== id)) }
    property string openWidget: ""
    // правая кнопка по виджету в правке рабочего стола — открыть его здесь раскрытым
    Connections {
        target: sv.panel
        function onWidgetToOpenChanged() { if (sv.panel.widgetToOpen) { sv.openWidget = sv.panel.widgetToOpen; sv.panel.widgetToOpen = "" } }
    }
    readonly property var anchorNames: ({ tl: Tr.t("слева сверху"), t: Tr.t("сверху"), tr: Tr.t("справа сверху"), l: Tr.t("слева"), c: Tr.t("по центру"),
                                          r: Tr.t("справа"), bl: Tr.t("слева снизу"), b: Tr.t("снизу"), br: Tr.t("справа снизу") })

    ColumnLayout {   // раздел «widgets»
        visible: sv.page === "widgets"
        Layout.fillWidth: true
        spacing: 12
        Header { text: Tr.t("ВИДЖЕТЫ НА РАБОЧЕМ СТОЛЕ") }
        Text {
            Layout.fillWidth: true
            text: Tr.t("Поверх обоев, под окнами. Добавь и настрой — положение, размер и цвет у каждого свои.")
            color: Theme.textMuted; font.pixelSize: Theme.fs(11)
            wrapMode: Text.WordWrap
        }
        ActionBtn {
            visible: Prefs.widgets.length > 0
            glyph: String.fromCodePoint(0xF01BE)
            text: Tr.t("Изменить расположение мышью")
            onClicked: { if (sv.panel) { sv.panel.close(); sv.panel.editDesktop() } }
        }
        Flow {
            Layout.fillWidth: true
            spacing: 6
            Repeater {
                model: sv.widgetTypes
                delegate: ActionBtn {
                    required property var modelData
                    glyph: String.fromCodePoint(modelData.glyph)
                    text: "+ " + modelData.name
                    onClicked: sv.wAdd(modelData.type)
                }
            }
        }
        // свои: папки в ~/.config/glide-shell/widgets (пример — examples/widgets в Glide Shell, формат — README)
        Text { text: Tr.t("Свои виджеты"); color: Theme.text; font.pixelSize: Theme.fs(13) }
        Flow {
            Layout.fillWidth: true
            spacing: 6
            Repeater {
                model: sv.customs
                delegate: ActionBtn {
                    required property var modelData
                    glyph: String.fromCodePoint(modelData.icon ? parseInt(modelData.icon, 16) : 0xF0B6F)
                    text: "+ " + modelData.name
                    onClicked: sv.wAddCustom(modelData.id)
                }
            }
            ActionBtn {
                glyph: String.fromCodePoint(0xF0770); text: Tr.t("Папка виджетов")
                onClicked: if (sv.panel) sv.panel.runRaw(["sh", "-c", 'd="${XDG_CONFIG_HOME:-$HOME/.config}/glide-shell/widgets"; mkdir -p "$d" && exec xdg-open "$d"'], "", "")
            }
            ActionBtn {
                glyph: String.fromCodePoint(0xF0450); text: Tr.t("Обновить")
                onClicked: if (sv.panel && sv.panel.desk) sv.panel.desk.rescan()
            }
        }
        Repeater {
            model: Prefs.widgets
            delegate: Rectangle {
                id: wc
                required property var modelData
                readonly property var w: modelData
                readonly property bool open: sv.openWidget === w.id
                Layout.fillWidth: true
                implicitHeight: wcol.implicitHeight + 16
                radius: Theme.radiusMd
                color: Theme.surface
                border.color: open ? Prefs.accent : Theme.outline
                Behavior on border.color { ColorAnimation { duration: Prefs.ms(140) } }
                ColumnLayout {
                    id: wcol
                    x: 10; y: 8
                    width: parent.width - 20
                    spacing: 10
                    RowLayout {   // заголовок: щелчок — раскрыть настройки
                        Layout.fillWidth: true
                        spacing: 8
                        Text { text: String.fromCodePoint(sv.wGlyph(wc.w)); color: Prefs.accent
                               font.family: Prefs.iconFont; font.pixelSize: Theme.fs(17) }
                        Column {
                            Layout.fillWidth: true
                            Text { text: sv.wName(wc.w); color: Theme.text; font.pixelSize: Theme.fs(13); font.weight: Font.Medium }
                            Text { text: (sv.anchorNames[wc.w.anchor] || "") + (wc.w.screen ? " · " + wc.w.screen : "")
                                   color: Theme.textMuted; font.pixelSize: Theme.fs(11) }
                        }
                        SmallBtn { glyph: String.fromCodePoint(0xF0A79); onClicked: sv.wDel(wc.w.id) }
                        SmallBtn { glyph: String.fromCodePoint(wc.open ? 0xF0143 : 0xF0140)
                                   onClicked: sv.openWidget = wc.open ? "" : wc.w.id }
                    }
                    // ---- настройки (раскрыты) ----
                    RowLayout {   // положение: сетка 3×3 и сдвиг
                        visible: wc.open
                        Layout.fillWidth: true
                        spacing: 16
                        Grid {
                            columns: 3; spacing: 4
                            Repeater {
                                model: ["tl", "t", "tr", "l", "c", "r", "bl", "b", "br"]
                                delegate: Rectangle {
                                    required property var modelData
                                    readonly property bool sel: (wc.w.anchor || "c") === modelData
                                    width: 26; height: 18; radius: Theme.r(5)
                                    color: sel ? Prefs.accent : am.pressed ? Theme.surfacePressed : am.containsMouse ? Theme.surfaceHigher : Theme.surfaceHigh
                                    Behavior on color { ColorAnimation { duration: Prefs.ms(120) } }
                                    MouseArea { id: am; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                                onClicked: { sv.wSet(wc.w.id, "anchor", parent.modelData) } }
                                }
                            }
                        }
                        Column {
                            spacing: 4
                            Repeater {
                                model: [{ key: "dx", name: Tr.t("Сдвиг →") }, { key: "dy", name: Tr.t("Сдвиг ↓") }]
                                delegate: Row {
                                    required property var modelData
                                    spacing: 4
                                    Text { width: 64; anchors.verticalCenter: parent.verticalCenter; text: modelData.name
                                           color: Theme.textSecondary; font.pixelSize: Theme.fs(11) }
                                    SmallBtn { glyph: "−"; onClicked: sv.wSet(wc.w.id, modelData.key, (Number(wc.w[modelData.key]) || 0) - 16) }
                                    Text { width: 40; anchors.verticalCenter: parent.verticalCenter; horizontalAlignment: Text.AlignHCenter
                                           text: (Number(wc.w[modelData.key]) || 0); color: Theme.text; font.pixelSize: Theme.fs(12) }
                                    SmallBtn { glyph: "+"; onClicked: sv.wSet(wc.w.id, modelData.key, (Number(wc.w[modelData.key]) || 0) + 16) }
                                }
                            }
                        }
                    }
                    ChoiceRow {
                        visible: wc.open
                        label: Tr.t("Размер")
                        options: [{ label: Tr.t("мелкий"), value: 0.75 }, { label: Tr.t("обычный"), value: 1 }, { label: Tr.t("крупный"), value: 1.4 }, { label: Tr.t("огромный"), value: 2 }]
                        current: wc.w.size || 1
                        onPicked: (v) => sv.wSet(wc.w.id, "size", v)
                    }
                    ChoiceRow {
                        visible: wc.open && wc.w.type !== "music" && wc.w.type !== "system"
                        label: wc.w.type === "custom" ? Tr.t("Цвет (api.tint)") : Tr.t("Цвет")
                        options: [{ label: Tr.t("белый"), value: "text" }, { label: Tr.t("акцент"), value: "accent" }, { label: Tr.t("приглушённый"), value: "muted" }]
                        current: wc.w.color || "text"
                        onPicked: (v) => sv.wSet(wc.w.id, "color", v)
                    }
                    ChoiceRow {
                        visible: wc.open
                        label: Tr.t("Непрозрачность")
                        options: [{ label: "100%", value: 1 }, { label: "80%", value: 0.8 }, { label: "60%", value: 0.6 }, { label: "40%", value: 0.4 }]
                        current: wc.w.opacity === undefined ? 1 : wc.w.opacity
                        onPicked: (v) => sv.wSet(wc.w.id, "opacity", v)
                    }
                    ChoiceRow {
                        visible: wc.open && Quickshell.screens.length > 1
                        label: Tr.t("Монитор")
                        options: [{ label: Tr.t("главный"), value: "" }].concat(Quickshell.screens.map(s => ({ label: s.name, value: s.name })))
                        current: wc.w.screen || ""
                        onPicked: (v) => sv.wSet(wc.w.id, "screen", v)
                    }
                    // ---- своё у типа ----
                    ToggleRow {
                        visible: wc.open && wc.w.type === "clock"
                        icon: String.fromCodePoint(0xF0954); label: Tr.t("Секунды")
                        checked: !!wc.w.seconds; onToggled: sv.wSet(wc.w.id, "seconds", !wc.w.seconds)
                    }
                    ToggleRow {
                        visible: wc.open && wc.w.type === "clock"
                        icon: String.fromCodePoint(0xF00ED); label: Tr.t("Дата под часами")
                        checked: !!wc.w.showDate; onToggled: sv.wSet(wc.w.id, "showDate", !wc.w.showDate)
                    }
                    ToggleRow {
                        visible: wc.open && (wc.w.type === "clock" || wc.w.type === "text")
                        icon: String.fromCodePoint(0xF0284); label: Tr.t("Жирный шрифт")
                        checked: !!wc.w.bold; onToggled: sv.wSet(wc.w.id, "bold", !wc.w.bold)
                    }
                    ChoiceRow {
                        visible: wc.open && wc.w.type === "date"
                        label: Tr.t("Вид даты")
                        options: [{ label: Tr.t("среда, 21 октября"), value: "long" }, { label: Tr.t("21 октября"), value: "short" }, { label: "21.10.2026", value: "numeric" }]
                        current: wc.w.format || "long"
                        onPicked: (v) => sv.wSet(wc.w.id, "format", v)
                    }
                    ToggleRow {
                        visible: wc.open && wc.w.type === "weather"
                        icon: String.fromCodePoint(0xF0599); label: Tr.t("Прогноз на 3 дня")
                        checked: !!wc.w.forecast; onToggled: sv.wSet(wc.w.id, "forecast", !wc.w.forecast)
                    }
                    TextRow {
                        visible: wc.open && wc.w.type === "text"
                        label: Tr.t("Текст (Enter — применить)")
                        value: wc.w.text || ""
                        onSubmitted: (v) => sv.wSet(wc.w.id, "text", v)
                    }
                    // свои: поля из widget.json (text — строка, toggle — переключатель, choice — выбор)
                    Repeater {
                        model: wc.open && wc.w.type === "custom" && sv.wMeta(wc.w) ? sv.wMeta(wc.w).settings : []
                        delegate: ColumnLayout {
                            id: opt
                            required property var modelData
                            Layout.fillWidth: true
                            ToggleRow {
                                visible: opt.modelData.type === "toggle"
                                icon: String.fromCodePoint(0xF0493); label: opt.modelData.label || opt.modelData.key
                                checked: !!sv.wOpt(wc.w, opt.modelData)
                                onToggled: sv.wSetOpt(wc.w, opt.modelData.key, !sv.wOpt(wc.w, opt.modelData))
                            }
                            ChoiceRow {
                                visible: opt.modelData.type === "choice"
                                label: opt.modelData.label || opt.modelData.key
                                options: opt.modelData.options || []
                                current: sv.wOpt(wc.w, opt.modelData)
                                onPicked: (v) => sv.wSetOpt(wc.w, opt.modelData.key, v)
                            }
                            TextRow {
                                visible: opt.modelData.type !== "toggle" && opt.modelData.type !== "choice"
                                label: (opt.modelData.label || opt.modelData.key) + Tr.t(" (Enter — применить)")
                                value: String(sv.wOpt(wc.w, opt.modelData) ?? "")
                                onSubmitted: (v) => sv.wSetOpt(wc.w, opt.modelData.key, v)
                            }
                        }
                    }
                    Text {
                        visible: wc.open && wc.w.type === "custom" && !!sv.wMeta(wc.w) && sv.wMeta(wc.w).description !== ""
                        Layout.fillWidth: true
                        text: sv.wMeta(wc.w) ? sv.wMeta(wc.w).description : ""
                        color: Theme.textMuted; font.pixelSize: Theme.fs(11); wrapMode: Text.WordWrap
                    }
                }
            }
        }
        EmptyState {
            visible: Prefs.widgets.length === 0
            Layout.fillWidth: true
            glyph: 0xF0954
            text: Tr.t("Виджетов пока нет")
            hint: Tr.t("Добавь кнопками выше — например, часы по центру рабочего стола")
        }
    }

    ColumnLayout {   // раздел «weather»
        visible: sv.page === "weather"
        Layout.fillWidth: true
        spacing: 14
        // ---- блокировка ----
        Header { text: Tr.t("ПОГОДА") }
        ToggleRow {
            icon: String.fromCodePoint(0xF0595)
            label: Tr.t("Погода")
            hint: Prefs.weather ? Tr.t("Open-Meteo, раз в 30 минут. Город: ") + (Prefs.weatherCity || Tr.t("сам (по IP или часовому поясу)"))
                                  + Tr.t(" — сменить в «Сегодня»") : Tr.t("Выключена")
            checked: Prefs.weather
            onToggled: Prefs.set("weather", !Prefs.weather)
        }
        ToggleRow {
            visible: Prefs.weather && Prefs.bar
            icon: String.fromCodePoint(0xF050F)
            label: Tr.t("Температура у часов")
            checked: sv.iconOn("weather")
            onToggled: sv.setIcon("weather", { on: !sv.iconOn("weather") })
        }
        Header { text: Tr.t("КАЛЕНДАРЬ") }
        ToggleRow {
            icon: String.fromCodePoint(0xF00F0)
            label: Tr.t("Праздники и переносы (Россия)")
            hint: Prefs.holidays ? Tr.t("Производственный календарь с isdayoff.ru (раз в месяц), без сети — праздники по закону") : Tr.t("Выключены")
            checked: Prefs.holidays
            onToggled: Prefs.set("holidays", !Prefs.holidays)
        }

    }
    ColumnLayout {   // раздел «notify»
        visible: sv.page === "notify"
        Layout.fillWidth: true
        spacing: 14
        Header { text: Tr.t("УВЕДОМЛЕНИЯ") }
        ToggleRow {
            visible: Prefs.notifications
            icon: String.fromCodePoint(0xF0193)
            label: Tr.t("Хранить историю после перезапуска")
            hint: Tr.t("~/.local/state/glide-shell/notifications.json, только для тебя (0600)")
            checked: Prefs.notifKeep
            onToggled: Prefs.set("notifKeep", !Prefs.notifKeep)
        }
        ToggleRow {
            icon: String.fromCodePoint(0xF009A)
            label: Tr.t("Свои уведомления (вместо DMS)")
            hint: Tr.t("В острове и в панели. Имя на шине одно: пока работает DMS, уведомления остаются у него")
            checked: Prefs.notifications
            onToggled: Prefs.set("notifications", !Prefs.notifications)
        }
        ToggleRow {
            icon: String.fromCodePoint(0xF099D)
            label: Tr.t("Своё окно пароля polkit (вместо DMS)")
            hint: Tr.t("Когда программе нужны права администратора. Агент в сеансе один: пока работает DMS, он у него")
            checked: Prefs.polkit
            onToggled: Prefs.set("polkit", !Prefs.polkit)
        }
        ToggleRow {
            icon: String.fromCodePoint(0xF0594)
            label: Tr.t("«Не беспокоить» ночью")
            hint: Prefs.dndSchedule ? Tr.t("С ") + Prefs.dndFrom + Tr.t(":00 до ") + Prefs.dndTo + Tr.t(":00 — без всплывающих (срочные покажутся)") : Tr.t("Выключено")
            checked: Prefs.dndSchedule
            onToggled: Prefs.set("dndSchedule", !Prefs.dndSchedule)
        }
        ChoiceRow {
            visible: Prefs.dndSchedule
            label: Tr.t("С")
            options: [{ label: "21:00", value: 21 }, { label: "22:00", value: 22 }, { label: "23:00", value: 23 }, { label: "0:00", value: 0 }]
            current: Prefs.dndFrom
            onPicked: (v) => Prefs.set("dndFrom", v)
        }
        ChoiceRow {
            visible: Prefs.dndSchedule
            label: Tr.t("До")
            options: [{ label: "6:00", value: 6 }, { label: "7:00", value: 7 }, { label: "8:00", value: 8 }, { label: "9:00", value: 9 }]
            current: Prefs.dndTo
            onPicked: (v) => Prefs.set("dndTo", v)
        }
        ToggleRow {
            icon: String.fromCodePoint(0xF0379)
            label: Tr.t("«Не беспокоить» при демонстрации экрана")
            hint: Tr.t("Пока идёт демонстрация в звонке или запись через портал — чужие сообщения не всплывают")
            checked: Prefs.dndCasting
            onToggled: Prefs.set("dndCasting", !Prefs.dndCasting)
        }

    }
    ColumnLayout {   // раздел «lock»
        visible: sv.page === "lock"
        Layout.fillWidth: true
        spacing: 14
        Header { text: Tr.t("БЛОКИРОВКА") }
        ToggleRow {
            icon: String.fromCodePoint(0xF033E)
            label: Tr.t("Блокировать перед сном")
            hint: Tr.t("Крышка, кнопка питания, «Сон» — после пробуждения нужен пароль")
            checked: Prefs.lockBeforeSleep
            onToggled: Prefs.set("lockBeforeSleep", !Prefs.lockBeforeSleep)
        }
        ChoiceRow {
            label: Tr.t("Гасить экран без дела")
            options: [{ label: Tr.t("никогда"), value: 0 }, { label: Tr.t("2 мин"), value: 2 }, { label: Tr.t("5 мин"), value: 5 },
                      { label: Tr.t("10 мин"), value: 10 }, { label: Tr.t("15 мин"), value: 15 }]
            current: Prefs.idleOff
            onPicked: (v) => Prefs.set("idleOff", v)
        }
        ChoiceRow {
            label: Tr.t("Блокировать без дела")
            options: [{ label: Tr.t("никогда"), value: 0 }, { label: Tr.t("5 мин"), value: 5 }, { label: Tr.t("10 мин"), value: 10 },
                      { label: Tr.t("15 мин"), value: 15 }, { label: Tr.t("30 мин"), value: 30 }]
            current: Prefs.idleLock
            onPicked: (v) => Prefs.set("idleLock", v)
        }
        Text {
            Layout.fillWidth: true
            text: Tr.t("Пока включено «Не засыпать» или идёт видео, экран не гаснет и не блокируется. ")
                + Tr.t("На экране блокировки он гаснет через минуту.")
            color: Theme.textMuted; font.pixelSize: Theme.fs(11)
            wrapMode: Text.WordWrap
        }

        // ---- вид экрана блокировки ----
        Header { text: Tr.t("ЭКРАН БЛОКИРОВКИ") }
        Rectangle {   // предпросмотр: тот же экран обычным окном, без блокировки (Esc — закрыть)
            Layout.fillWidth: true
            implicitHeight: 34; radius: Theme.radiusSm
            color: pvm.pressed ? Theme.surfacePressed : pvm.containsMouse ? Theme.surfaceHigher : Theme.surfaceHigh
            scale: pvm.pressed ? 0.98 : 1
            Behavior on color { ColorAnimation { duration: Prefs.ms(120) } }
            Behavior on scale { NumberAnimation { duration: Prefs.ms(140); easing.type: Easing.OutBack } }
            Text { anchors.centerIn: parent; text: Tr.t("Предпросмотр экрана блокировки"); color: Theme.text; font.pixelSize: Theme.fs(13) }
            MouseArea {
                id: pvm
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: Quickshell.execDetached(["qs", "-c", "glide-shell", "ipc", "call", "lock", "preview"])
            }
        }
        ChipChoice {
            label: Tr.t("Анимация после пароля")
            hint: Tr.t("И на экране входа. Посмотреть — «Предпросмотр» выше: введи пароль, и экран уйдёт выбранным стилем")
            options: [{ label: Tr.t("подъём"), value: "rise" }, { label: Tr.t("круг"), value: "iris" },
                      { label: Tr.t("шторки"), value: "curtains" }, { label: Tr.t("плитки"), value: "tiles" },
                      { label: Tr.t("сквозь"), value: "zoom" }, { label: Tr.t("в остров"), value: "island" },
                      { label: Tr.t("случайная"), value: "random" }]
            current: Prefs.unlockStyle
            onPicked: (v) => Prefs.set("unlockStyle", v)
        }
        ChoiceRow {
            label: Tr.t("Размер часов")
            options: [{ label: Tr.t("мелкие"), value: 56 }, { label: Tr.t("средние"), value: 80 }, { label: Tr.t("крупные"), value: 112 },
                      { label: Tr.t("огромные"), value: 140 }]
            current: Prefs.lockClockSize
            onPicked: (v) => Prefs.set("lockClockSize", v)
        }
        ToggleRow {
            icon: String.fromCodePoint(0xF0264)
            label: Tr.t("Жирные цифры")
            hint: Tr.t("Выключено — тонкие")
            checked: Prefs.lockClockBold
            onToggled: Prefs.set("lockClockBold", !Prefs.lockClockBold)
        }
        ChoiceRow {
            label: Tr.t("Фон")
            options: [{ label: Tr.t("сияние акцента"), value: "glow" }, { label: Tr.t("сплошной"), value: "solid" },
                      { label: Tr.t("своя картинка"), value: "image" }]
            current: Prefs.lockBackground
            onPicked: (v) => Prefs.set("lockBackground", v)
        }
        TextRow {
            visible: Prefs.lockBackground === "image"
            label: Tr.t("Картинка")
            placeholder: "~/Изображения/фон.jpg → Enter"
            value: Prefs.lockImage
            onSubmitted: (v) => Prefs.set("lockImage", v)
        }
        TextRow {
            label: Tr.t("Приветствие под датой")
            placeholder: Tr.t("Например: Привет, Паша → Enter (пусто — без него)")
            value: Prefs.lockGreeting
            onSubmitted: (v) => Prefs.set("lockGreeting", v)
        }
        Text { text: Tr.t("Показывать"); color: Theme.text; Layout.topMargin: 2 }
        ToggleRow { icon: String.fromCodePoint(0xF0004); label: Tr.t("Имя и аватар"); checked: Prefs.lockShowUser; onToggled: Prefs.set("lockShowUser", !Prefs.lockShowUser) }
        ToggleRow { icon: String.fromCodePoint(0xF075A); label: Tr.t("Что играет (с кнопками)"); checked: Prefs.lockShowMedia; onToggled: Prefs.set("lockShowMedia", !Prefs.lockShowMedia) }
        ToggleRow { icon: String.fromCodePoint(0xF009A); label: Tr.t("Число непрочитанных уведомлений"); checked: Prefs.lockShowUnread; onToggled: Prefs.set("lockShowUnread", !Prefs.lockShowUnread) }
        ToggleRow { icon: String.fromCodePoint(0xF0079); label: Tr.t("Батарея"); checked: Prefs.lockShowBattery; onToggled: Prefs.set("lockShowBattery", !Prefs.lockShowBattery) }
        ToggleRow { icon: String.fromCodePoint(0xF030C); label: Tr.t("Раскладка"); checked: Prefs.lockShowLayout; onToggled: Prefs.set("lockShowLayout", !Prefs.lockShowLayout) }

    }
    ColumnLayout {   // раздел «bar»
        visible: sv.page === "bar"
        Layout.fillWidth: true
        spacing: 14
        // ---- бар ----
        Header { visible: Prefs.bar; text: Tr.t("БАР") }
        ChoiceRow {
            visible: Prefs.bar
            label: Tr.t("Несколько мониторов")
            options: [{ label: Tr.t("объединение"), value: "unite" }, { label: Tr.t("продолжение"), value: "extend" },
                      { label: Tr.t("дублирование"), value: "mirror" }, { label: Tr.t("стандарт"), value: "standard" }]
            current: Prefs.monitorMode
            onPicked: (v) => Prefs.set("monitorMode", v)
        }
        Text {
            visible: Prefs.bar
            Layout.fillWidth: true
            text: (Prefs.monitorMode === "unite" ? Tr.t("Один бар на весь стол: левая капсула — у левого края крайнего левого монитора, правая — у правого края крайнего правого, остров — на главном")
                 : Prefs.monitorMode === "extend" ? Tr.t("Весь бар — на главном мониторе; на соседних — его продолжение: их рабочие столы и окно")
                 : Prefs.monitorMode === "mirror" ? Tr.t("Полный бар на каждом мониторе, у каждого — свои рабочие столы; остров — на главном")
                 : Tr.t("Бар только на главном мониторе"))
                  + (Quickshell.screens.length > 1 ? "" : Tr.t(". Сейчас монитор один — разницы нет"))
            color: Theme.textMuted; font.pixelSize: Theme.fs(11)
            wrapMode: Text.WordWrap
        }
        ChoiceRow {
            visible: Prefs.bar || Prefs.dock
            label: Tr.t("Главный монитор")
            options: [{ label: Tr.t("в фокусе"), value: "" }].concat(Quickshell.screens.map(s => ({ label: s.name, value: s.name })))
            current: Prefs.mainScreen
            onPicked: (v) => Prefs.set("mainScreen", v)
        }
        ToggleRow {
            visible: Prefs.bar
            icon: String.fromCodePoint(0xF056E)
            label: Tr.t("Все воркспейсы")
            hint: Tr.t("Выключено — только занятые и текущий")
            checked: Prefs.barAllWorkspaces
            onToggled: Prefs.set("barAllWorkspaces", !Prefs.barAllWorkspaces)
        }
        ToggleRow {
            visible: Prefs.bar
            icon: String.fromCodePoint(0xF003B)
            label: Tr.t("Иконки приложений на воркспейсах")
            checked: Prefs.barWsIcons
            onToggled: Prefs.set("barWsIcons", !Prefs.barWsIcons)
        }
        Header { visible: Prefs.bar; text: Tr.t("БОКОВЫЕ ОСТРОВА") }
        Text {
            visible: Prefs.bar
            Layout.fillWidth: true
            text: Tr.t("Что показывать в левом и правом островах бара и в каком порядке. Место — щелчок по «левый / правый / скрыт», порядок — ↑↓ (в своём острове)")
            color: Theme.textMuted; font.pixelSize: Theme.fs(11)
            wrapMode: Text.WordWrap
        }
        Repeater {
            model: Prefs.bar ? Prefs.barItems : []
            delegate: BarItemRow {
                required property var modelData
                required property int index
                Layout.fillWidth: true
                it: modelData; pos: index
            }
        }

    }
    ColumnLayout {   // раздел «niri»: мониторы, клавиатура, тачпад, мышь, горячие клавиши (tools/glide-niri.py)
        id: niriPage
        visible: sv.page === "niri"
        Layout.fillWidth: true
        spacing: 14
        readonly property string tool: Quickshell.shellDir + "/tools/glide-niri.py"
        property var cfg: null            // {managed, input, binds}
        property var outs: []             // niri msg -j outputs
        property var pending: null        // {name, back: [аргументы niri msg output, чтобы вернуть]}
        property int secsLeft: 0
        property string bindFilter: ""
        onVisibleChanged: if (visible) reload()
        function reload() { rd.running = false; rd.running = true; od.running = false; od.running = true }
        Process {
            id: rd
            command: ["python3", "-I", niriPage.tool, "read"]
            stdout: StdioCollector { onStreamFinished: { try { niriPage.cfg = JSON.parse(text) } catch (e) {} } }
        }
        Process {
            id: od
            command: ["niri", "msg", "-j", "outputs"]
            stdout: StdioCollector { onStreamFinished: { try { var o = JSON.parse(text); niriPage.outs = Object.keys(o).sort().map(k => o[k]) } catch (e) {} } }
        }
        // ввод: правка → glide-niri.py set-input (проверка niri validate, при ошибке — откат)
        Process {
            id: wr
            property string patch: ""
            command: ["python3", "-I", niriPage.tool, "set-input", patch]
            stdout: StdioCollector {
                onStreamFinished: {
                    var r = {}; try { r = JSON.parse(text) } catch (e) {}
                    if (!r.ok && sv.panel) sv.panel.flash("!", Tr.t("niri не принял настройку — вернул как было"), Theme.error)
                    niriPage.reload()
                }
            }
        }
        function setInput(patch) {
            var c = JSON.parse(JSON.stringify(cfg))   // сразу показать, файл догонит
            for (var sec in patch) {
                if (typeof patch[sec] === "object") Object.assign(c.input[sec], patch[sec]); else c.input[sec] = patch[sec]
            }
            cfg = c
            wr.patch = JSON.stringify(patch); wr.running = false; wr.running = true
        }
        // мониторы: сразу через niri msg output, затем 15 с «оставить?»; не подтвердили — вернуть
        function outRun(name, args) { Quickshell.execDetached(["niri", "msg", "output", name].concat(args)) }
        function outChange(o, args, back) {
            if (pending && pending.name !== o.name) outKeep()
            if (!pending) pending = { name: o.name, back: [] }
            pending.back.push(back)
            outRun(o.name, args)
            secsLeft = 15; countdown.restart()
            Qt.callLater(() => { od.running = false; od.running = true })
        }
        function outRevert() {
            if (!pending) return
            for (var i = pending.back.length - 1; i >= 0; i--) outRun(pending.name, pending.back[i])
            pending = null; countdown.stop()
            revertRead.restart()
        }
        Timer { id: revertRead; interval: 400; onTriggered: { od.running = false; od.running = true } }
        function outKeep() {
            countdown.stop(); pending = null
            var items = outs.map(o => {
                var m = o.modes[o.current_mode] || o.modes[0]
                return { name: o.name, mode: m ? m.width + "x" + m.height + "@" + (m.refresh_rate / 1000).toFixed(3) : "",
                         scale: o.logical ? o.logical.scale : 1, transform: o.logical ? (niriPage.tfNames[o.logical.transform] || "normal") : "normal",
                         x: o.logical ? o.logical.x : 0, y: o.logical ? o.logical.y : 0, off: !o.logical }
            })
            Quickshell.execDetached(["python3", "-I", tool, "save-outputs", JSON.stringify(items)])
        }
        Timer { id: countdown; interval: 1000; repeat: true
                onTriggered: { niriPage.secsLeft--; if (niriPage.secsLeft <= 0) niriPage.outRevert() } }
        readonly property var tfNames: ({ Normal: "normal", _90: "90", _180: "180", _270: "270" })

        Header { text: Tr.t("МОНИТОРЫ") }
        Rectangle {   // подтверждение после смены режима или масштаба
            visible: !!niriPage.pending
            Layout.fillWidth: true
            implicitHeight: 52; radius: Theme.r(14)
            color: Qt.rgba(Prefs.accent.r, Prefs.accent.g, Prefs.accent.b, 0.14)
            border.color: Prefs.accent
            RowLayout {
                anchors.fill: parent; anchors.leftMargin: 14; anchors.rightMargin: 8
                Text { Layout.fillWidth: true; text: Tr.t("Оставить новые настройки? Вернутся сами через ") + niriPage.secsLeft + Tr.t(" с")
                       color: Theme.text; font.pixelSize: Theme.fs(13); wrapMode: Text.WordWrap }
                ActionBtn { glyph: String.fromCodePoint(0xF012C); text: Tr.t("Оставить"); onClicked: niriPage.outKeep() }
                ActionBtn { glyph: String.fromCodePoint(0xF006A); text: Tr.t("Вернуть"); onClicked: niriPage.outRevert() }
            }
        }
        Repeater {
            model: niriPage.outs
            delegate: ColumnLayout {
                id: oc
                required property var modelData
                readonly property var o: modelData
                readonly property var lg: o.logical || ({ scale: 1, transform: "Normal" })
                Layout.fillWidth: true
                spacing: 10
                Text {
                    Layout.fillWidth: true
                    text: oc.o.name + " · " + [oc.o.make, oc.o.model].filter(x => x && !/^0x/.test(x)).join(" ")
                    color: Theme.textSecondary; font.pixelSize: Theme.fs(12); font.bold: true; elide: Text.ElideRight
                }
                ChoiceRow {
                    label: Tr.t("Масштаб")
                    options: [{ label: "100%", value: 1 }, { label: "125%", value: 1.25 }, { label: "150%", value: 1.5 },
                              { label: "175%", value: 1.75 }, { label: "200%", value: 2 }]
                    current: oc.lg.scale
                    onPicked: (v) => niriPage.outChange(oc.o, ["scale", String(v)], ["scale", String(oc.lg.scale)])
                }
                ChipChoice {
                    visible: oc.o.modes.length > 1
                    label: Tr.t("Разрешение и частота")
                    options: oc.o.modes.map((m, i) => ({ label: m.width + "×" + m.height + " · " + Math.round(m.refresh_rate / 1000) + Tr.t(" Гц"), value: i }))
                    current: oc.o.current_mode
                    onPicked: (i) => {
                        var m = oc.o.modes[i], c = oc.o.modes[oc.o.current_mode]
                        niriPage.outChange(oc.o, ["mode", m.width + "x" + m.height + "@" + (m.refresh_rate / 1000).toFixed(3)],
                                           ["mode", c.width + "x" + c.height + "@" + (c.refresh_rate / 1000).toFixed(3)])
                    }
                }
                ChoiceRow {
                    label: Tr.t("Поворот")
                    options: [{ label: Tr.t("обычно"), value: "normal" }, { label: "90°", value: "90" },
                              { label: "180°", value: "180" }, { label: "270°", value: "270" }]
                    current: niriPage.tfNames[oc.lg.transform] || "normal"
                    onPicked: (v) => niriPage.outChange(oc.o, ["transform", v], ["transform", niriPage.tfNames[oc.lg.transform] || "normal"])
                }
            }
        }
        Text {
            Layout.fillWidth: true
            visible: niriPage.outs.length > 1
            text: Tr.t("Взаимное расположение мониторов niri подбирает сам; поменять — в glide-outputs.kdl (position x= y=)")
            color: Theme.textMuted; font.pixelSize: Theme.fs(11); wrapMode: Text.WordWrap
        }

        Header { text: Tr.t("КЛАВИАТУРА") }
        Text {
            Layout.fillWidth: true
            visible: !!niriPage.cfg && !niriPage.cfg.managed
            text: Tr.t("При первой правке блок input из config.kdl переносится в ~/.config/niri/glide-settings.kdl (в config.kdl он закомментирован, копия — рядом) — дальше им управляют эти настройки")
            color: Theme.textMuted; font.pixelSize: Theme.fs(11); wrapMode: Text.WordWrap
        }
        TextRow {
            visible: !!niriPage.cfg
            label: Tr.t("Раскладки (через запятую, Enter)")
            placeholder: "us,ru"
            value: niriPage.cfg ? niriPage.cfg.input.keyboard.layout : ""
            onSubmitted: (v) => niriPage.setInput({ keyboard: { layout: v.replace(/\s+/g, "") } })
        }
        ChoiceRow {
            visible: !!niriPage.cfg
            label: Tr.t("Переключение раскладки")
            options: [{ label: "Super+Space", value: "grp:win_space_toggle" }, { label: "Alt+Shift", value: "grp:alt_shift_toggle" },
                      { label: "Ctrl+Shift", value: "grp:ctrl_shift_toggle" }, { label: "Caps Lock", value: "grp:caps_toggle" }]
            current: niriPage.cfg ? niriPage.cfg.input.keyboard.options : ""
            onPicked: (v) => niriPage.setInput({ keyboard: { options: v } })
        }
        ChoiceRow {
            visible: !!niriPage.cfg
            label: Tr.t("Задержка повтора клавиш")
            options: [{ label: Tr.t("короткая"), value: 200 }, { label: Tr.t("обычная"), value: 300 },
                      { label: Tr.t("длинная"), value: 500 }, { label: Tr.t("как было"), value: null }]
            current: niriPage.cfg ? niriPage.cfg.input.keyboard.repeat_delay : null
            onPicked: (v) => niriPage.setInput({ keyboard: { repeat_delay: v } })
        }
        ChoiceRow {
            visible: !!niriPage.cfg
            label: Tr.t("Скорость повтора")
            options: [{ label: Tr.t("медленно"), value: 20 }, { label: Tr.t("обычно"), value: 30 },
                      { label: Tr.t("быстро"), value: 50 }, { label: Tr.t("как было"), value: null }]
            current: niriPage.cfg ? niriPage.cfg.input.keyboard.repeat_rate : null
            onPicked: (v) => niriPage.setInput({ keyboard: { repeat_rate: v } })
        }
        ToggleRow {
            visible: !!niriPage.cfg
            icon: String.fromCodePoint(0xF03A0)
            label: Tr.t("NumLock при входе")
            checked: !!niriPage.cfg && niriPage.cfg.input.keyboard.numlock
            onToggled: niriPage.setInput({ keyboard: { numlock: !niriPage.cfg.input.keyboard.numlock } })
        }

        Header { visible: !!niriPage.cfg; text: Tr.t("ТАЧПАД") }
        Repeater {
            model: niriPage.cfg ? [{ k: "tap", l: Tr.t("Касание — щелчок"), g: 0xF0B5A }, { k: "natural_scroll", l: Tr.t("Естественная прокрутка"), g: 0xF0CEF },
                                   { k: "dwt", l: Tr.t("Не мешать при наборе текста"), g: 0xF030C },
                                   { k: "disabled_on_external_mouse", l: Tr.t("Выключать, когда подключена мышь"), g: 0xF037D }] : []
            delegate: ToggleRow {
                required property var modelData
                icon: String.fromCodePoint(modelData.g)
                label: modelData.l
                checked: !!niriPage.cfg && niriPage.cfg.input.touchpad[modelData.k]
                onToggled: { var p = {}; p[modelData.k] = !niriPage.cfg.input.touchpad[modelData.k]; niriPage.setInput({ touchpad: p }) }
            }
        }
        ChoiceRow {
            visible: !!niriPage.cfg
            label: Tr.t("Скорость указателя (тачпад)")
            options: [{ label: Tr.t("медленно"), value: -0.4 }, { label: Tr.t("обычно"), value: 0 },
                      { label: Tr.t("быстрее"), value: 0.3 }, { label: Tr.t("быстро"), value: 0.6 }]
            current: niriPage.cfg ? niriPage.cfg.input.touchpad.accel_speed : 0
            onPicked: (v) => niriPage.setInput({ touchpad: { accel_speed: v } })
        }

        Header { visible: !!niriPage.cfg; text: Tr.t("МЫШЬ") }
        ToggleRow {
            visible: !!niriPage.cfg
            icon: String.fromCodePoint(0xF0CEF)
            label: Tr.t("Естественная прокрутка")
            checked: !!niriPage.cfg && niriPage.cfg.input.mouse.natural_scroll
            onToggled: niriPage.setInput({ mouse: { natural_scroll: !niriPage.cfg.input.mouse.natural_scroll } })
        }
        ToggleRow {
            visible: !!niriPage.cfg
            icon: String.fromCodePoint(0xF037D)
            label: Tr.t("Без ускорения указателя")
            hint: Tr.t("Указатель движется ровно как мышь — удобно в играх")
            checked: !!niriPage.cfg && niriPage.cfg.input.mouse.accel_profile === "flat"
            onToggled: niriPage.setInput({ mouse: { accel_profile: niriPage.cfg.input.mouse.accel_profile === "flat" ? "adaptive" : "flat" } })
        }
        ChoiceRow {
            visible: !!niriPage.cfg
            label: Tr.t("Скорость указателя (мышь)")
            options: [{ label: Tr.t("медленно"), value: -0.4 }, { label: Tr.t("обычно"), value: 0 },
                      { label: Tr.t("быстрее"), value: 0.3 }, { label: Tr.t("быстро"), value: 0.6 }]
            current: niriPage.cfg ? niriPage.cfg.input.mouse.accel_speed : 0
            onPicked: (v) => niriPage.setInput({ mouse: { accel_speed: v } })
        }
        ToggleRow {
            visible: !!niriPage.cfg
            icon: String.fromCodePoint(0xF0659)
            label: Tr.t("Фокус за мышью")
            hint: Tr.t("Окно под указателем становится активным без щелчка")
            checked: !!niriPage.cfg && niriPage.cfg.input.focus_follows_mouse
            onToggled: niriPage.setInput({ focus_follows_mouse: !niriPage.cfg.input.focus_follows_mouse })
        }

        Header { visible: !!niriPage.cfg; text: Tr.t("ГОРЯЧИЕ КЛАВИШИ") }
        TextRow {
            visible: !!niriPage.cfg
            label: Tr.t("Поиск по клавишам и действиям")
            placeholder: Tr.t("например, screenshot или Mod+T")
            value: niriPage.bindFilter
            onSubmitted: (v) => niriPage.bindFilter = v
        }
        Repeater {
            model: {
                if (!niriPage.cfg) return []
                var f = niriPage.bindFilter.toLowerCase()
                var all = niriPage.cfg.binds.filter(b => !f || (b.key + " " + b.title + " " + b.action).toLowerCase().indexOf(f) >= 0)
                return all.slice(0, 60)
            }
            delegate: RowLayout {
                required property var modelData
                Layout.fillWidth: true
                spacing: 10
                Rectangle {
                    Layout.preferredWidth: Math.min(170, keyT.implicitWidth + 16)
                    implicitHeight: 26; radius: Theme.r(8)
                    color: Theme.surfaceHigh; border.color: Theme.outline
                    Text { id: keyT; anchors.centerIn: parent; width: Math.min(implicitWidth, 154); elide: Text.ElideRight
                           text: parent.parent.modelData.key; color: Theme.text; font.pixelSize: Theme.fs(12); font.family: "JetBrainsMono Nerd Font" }
                }
                Text { Layout.fillWidth: true; text: parent.modelData.title || parent.modelData.action
                       color: Theme.textSecondary; font.pixelSize: Theme.fs(12); elide: Text.ElideRight }
            }
        }
        Text {
            Layout.fillWidth: true
            visible: !!niriPage.cfg
            text: Tr.t("Изменить клавиши — в ~/.config/niri/config.kdl (раздел binds)")
            color: Theme.textMuted; font.pixelSize: Theme.fs(11); wrapMode: Text.WordWrap
        }
    }
    ColumnLayout {   // раздел «plugins»
        visible: sv.page === "plugins"
        Layout.fillWidth: true
        spacing: 14
        // ---- категории ----
        Header { text: Tr.t("ПОРЯДОК КАТЕГОРИЙ") }
        Repeater {
            model: sv.panel ? sv.panel.categories : []
            delegate: RowLayout {
                required property var modelData
                required property int index
                Layout.fillWidth: true
                spacing: 6
                Text { text: modelData.icon; color: Prefs.accent; font.family: Prefs.iconFont; font.pixelSize: Theme.fs(15); Layout.preferredWidth: 22 }
                Text { text: modelData.name; color: Theme.text; Layout.fillWidth: true; elide: Text.ElideRight }
                SmallBtn { glyph: "▲"; active: index > 0; onClicked: sv.panel.moveCategory(modelData.id, -1) }
                SmallBtn { glyph: "▼"; active: index < sv.panel.categories.length - 1
                           onClicked: sv.panel.moveCategory(modelData.id, 1) }
            }
        }

        // ---- плагины ----
        Header { text: Tr.t("ПЛАГИНЫ") }
        Repeater {
            model: sv.panel ? sv.panel.allPlugins : []
            delegate: ToggleRow {
                required property var modelData
                icon: modelData.icon || ""
                label: modelData.name
                checked: !modelData.disabled
                onToggled: sv.panel.togglePlugin(modelData.id)
            }
        }

        Rectangle {   // сброс — со второго нажатия, как опасные кнопки плагинов
            id: resetBtn
            Behavior on border.color { ColorAnimation { duration: Prefs.ms(140) } }
            property bool armed: false
            Layout.fillWidth: true
            Layout.topMargin: 6
            implicitHeight: 40
            radius: Theme.radiusSm
            color: armed ? Theme.errorContainer : (rma.containsMouse ? Theme.errorHover : Theme.surfaceHigh)
            border.color: armed ? Theme.error : "transparent"
            scale: rma.pressed ? 0.98 : 1
            Behavior on scale { NumberAnimation { duration: Prefs.ms(140); easing.type: Easing.OutBack } }
            Behavior on color { ColorAnimation { duration: Prefs.ms(120) } }
            Text {
                anchors.centerIn: parent
                text: resetBtn.armed ? Tr.t("Нажми ещё раз, чтобы сбросить") : Tr.t("Сбросить настройки панели")
                color: Theme.error
            }
            Timer { id: disarmReset; interval: 3000; onTriggered: resetBtn.armed = false }
            MouseArea {
                id: rma
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (resetBtn.armed) { resetBtn.armed = false; Prefs.reset() }
                    else { resetBtn.armed = true; disarmReset.restart() }
                }
            }
        }
        Text {
            Layout.fillWidth: true
            text: Tr.t("Файл: ~/.config/glide-shell/config.json")
            color: Theme.textMuted
            font.pixelSize: Theme.fs(11)
        }
    }
}
