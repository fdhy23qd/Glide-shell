import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import Quickshell.Services.Pam

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
        live:  { glyph: 0xF0996, label: Tr.t("Активности приложений"), hint: Tr.t("Загрузки, сборки, отсчёты — от плагинов и программ"), pref: "islandLive" },
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
        updates: { glyph: 0xF03D4, label: Tr.t("Обновления Arch"), hint: Tr.t("число пакетов, когда есть обновления; щелчок — обновить в терминале") },
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
    // ---- изменение плагинов по паролю (Prefs.pluginLock): что ждёт подтверждения ----
    property string guardFor: ""      // id плагина или «lock» — снять защиту
    property string guardName: ""
    property bool guardTurnOn: false
    property string guardErr: ""
    function guarded(what, name, turnOn) {
        if (!Prefs.pluginLock && what !== "lock") { sv.panel.togglePlugin(what); return }
        guardFor = what; guardName = name || ""; guardTurnOn = !!turnOn; guardErr = ""; guardInput.text = ""
    }
    function guardCancel() { plPam.abort(); guardFor = ""; guardInput.text = ""; guardErr = "" }
    function guardSubmit() {
        if (plPam.active || !guardInput.text) return
        plPam.pw = guardInput.text
        plPam.start()
    }
    PamContext {
        id: plPam
        property string pw: ""
        config: "login"
        configDirectory: "/etc/pam.d"
        onResponseRequiredChanged: if (responseRequired) respond(pw)
        onCompleted: result => {
            pw = ""
            if (result === PamResult.Success) {
                if (sv.guardFor === "lock") Prefs.set("pluginLock", false); else sv.panel.togglePlugin(sv.guardFor)
                sv.guardFor = ""; guardInput.text = ""
            } else {
                sv.guardErr = result === PamResult.MaxTries ? Tr.t("Слишком много попыток") : Tr.t("Неверный пароль")
                guardInput.text = ""
            }
        }
        onError: err => { pw = ""; sv.guardErr = Tr.t("Ошибка проверки пароля") }
    }
    function pluginBarMeta(id) {   // элемент бара из плагина: его значок и имя
        var pl = id.indexOf("plugin:") === 0 && sv.panel ? sv.panel.pluginById(id.slice(7)) : null
        return pl ? { glyph: (pl.icon || "•").codePointAt(0), label: pl.name, hint: Tr.t("из плагина") } : ({})
    }
    component BarItemRow: Rectangle {
        id: bi
        property var it
        property int pos
        readonly property var meta: sv.barMeta[it.id] || sv.pluginBarMeta(it.id)
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
        layout:  { glyph: 0xF030C, label: Tr.t("Раскладка"), hint: Tr.t("EN / RU, если раскладок несколько") },
        ptimer:  { glyph: 0xF0425, label: Tr.t("Выключение по таймеру"), hint: Tr.t("остаток, пока таймер идёт") }
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
        // ---- обновления из git (Updates.qml, tools/glide-update.py) ----
        Header { text: Tr.t("ОБНОВЛЕНИЯ") }
        ToggleRow {
            icon: String.fromCodePoint(0xF06B0)
            label: Tr.t("Проверять обновления")
            hint: Tr.t("Раз в 6 часов — git fetch в папке, откуда поставлена оболочка; о новой версии — одно уведомление")
            checked: Prefs.updateCheck
            onToggled: Prefs.set("updateCheck", !Prefs.updateCheck)
        }
        ToggleRow {
            visible: ArchUpdates.supported
            icon: String.fromCodePoint(0xF03D6)
            label: Tr.t("Обновления Arch Linux в баре")
            hint: ArchUpdates.st.error ? Tr.t("Не удалось проверить: ") + ArchUpdates.st.error
                : Tr.t("Раз в 3 часа — свежие базы в свою папку (система не меняется), AUR — через yay/paru. Сейчас: ") + (ArchUpdates.st.count || 0)
            checked: Prefs.archUpdates
            onToggled: { Prefs.set("archUpdates", !Prefs.archUpdates); if (!Prefs.archUpdates) ArchUpdates.check() }
        }
        Repeater {
            model: [{ id: "shell", name: "Glide Shell" }, { id: "apps", name: Tr.t("Приложения Glide") }]
            delegate: Rectangle {
                id: uc
                required property var modelData
                readonly property var s: Updates[modelData.id]
                readonly property bool working: !!s.running || (Updates.applying && Updates.busy)
                visible: modelData.id === "shell" || !!s.git
                Layout.fillWidth: true
                implicitHeight: ucCol.implicitHeight + 24
                radius: Theme.r(16)
                color: Theme.surface
                border.color: s.behind > 0 ? Prefs.accent : Theme.outline
                Behavior on border.color { ColorAnimation { duration: Prefs.ms(160) } }
                ColumnLayout {
                    id: ucCol
                    x: 14; y: 12; width: parent.width - 28
                    spacing: 6
                    Text {
                        text: uc.modelData.name + (uc.s.current ? "  " + uc.s.current : "")
                        color: Theme.text; font.pixelSize: Theme.fs(14); font.bold: true
                    }
                    Text {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        font.pixelSize: Theme.fs(12)
                        color: uc.s.behind > 0 ? Prefs.accent : uc.s.error ? Theme.error : Theme.textSecondary
                        text: !uc.s.git ? (uc.s.source ? Tr.t("Поставлено не из git-папки — обновить можно, скачав заново (git clone) и запустив sh setup.sh")
                                                       : Tr.t("Не знаю, откуда поставлено: один раз запусти sh install.sh из папки с исходниками"))
                            : uc.s.local ? Tr.t("Папка без удалённого репозитория — проверять негде")
                            : uc.working ? (uc.modelData.id === "shell" ? Tr.t("Обновляется… оболочка перезапустится сама")
                                                                        : Tr.t("Обновляется… сборка займёт пару минут"))
                            : uc.s.error ? Tr.t("Не удалось проверить: ") + uc.s.error
                            : uc.s.behind > 0 ? Tr.t("Доступно: ") + (uc.s.latest || "") + " (" + uc.s.behind + Tr.t(" изм.)")
                                + (uc.s.canUpdate ? "" : Tr.t(" — но в папке свои правки или коммиты, обновляй вручную: git pull"))
                            : Tr.t("Установлена последняя версия")
                    }
                    Repeater {   // что нового
                        model: (uc.s.changes || []).slice(0, 6)
                        delegate: Text {
                            required property var modelData
                            Layout.fillWidth: true
                            text: "•  " + modelData
                            color: Theme.textVariant; font.pixelSize: Theme.fs(12)
                            wrapMode: Text.WordWrap; maximumLineCount: 2; elide: Text.ElideRight
                        }
                    }
                    Text {
                        visible: !!uc.s.checked
                        text: Tr.t("Проверено: ") + (uc.s.checked ? Tr.date(new Date(uc.s.checked * 1000), "d MMMM, HH:mm") : "")
                        color: Theme.textMuted; font.pixelSize: Theme.fs(11)
                    }
                    RowLayout {
                        visible: !!uc.s.git && !uc.s.local
                        spacing: 8
                        ActionBtn {
                            glyph: String.fromCodePoint(0xF0450)
                            text: Updates.checking ? Tr.t("Проверяю…") : Tr.t("Проверить")
                            enabled: !Updates.checking && !uc.working
                            onClicked: Updates.check(true)
                        }
                        ActionBtn {
                            visible: uc.s.behind > 0
                            glyph: String.fromCodePoint(0xF01DA)
                            text: Tr.t("Обновить")
                            enabled: !!uc.s.canUpdate && !Updates.busy
                            onClicked: Updates.apply(uc.modelData.id)
                        }
                    }
                }
            }
        }
        // ---- резервная копия настроек (tools/glide-backup.py) ----
        Header { text: Tr.t("РЕЗЕРВНАЯ КОПИЯ") }
        Text {
            Layout.fillWidth: true
            text: Tr.t("Все настройки, свои плагины и виджеты, настройки niri из «Устройств» — одним файлом в домашней папке. История буфера, уведомления и ключи в копию не попадают.")
            color: Theme.textMuted; font.pixelSize: Theme.fs(11); wrapMode: Text.WordWrap
        }
        RowLayout {
            id: bkRow
            spacing: 8
            property var found: []
            property string pending: ""          // файл, который восстановим вторым нажатием
            function reload() { bkList.running = false; bkList.running = true }
            Component.onCompleted: reload()
            Process {
                id: bkList
                command: ["python3", "-I", Quickshell.shellDir + "/tools/glide-backup.py", "list"]
                stdout: StdioCollector { onStreamFinished: { try { bkRow.found = JSON.parse(text) } catch (e) { bkRow.found = [] } } }
            }
            Process {
                id: bkSave
                command: ["python3", "-I", Quickshell.shellDir + "/tools/glide-backup.py", "export"]
                stdout: StdioCollector { onStreamFinished: { if (sv.panel && text.trim()) sv.panel.flash(String.fromCodePoint(0xF0193), Tr.t("Сохранено: ") + text.trim().replace(Quickshell.env("HOME"), "~"), Theme.success); bkRow.reload() } }
            }
            Process {
                id: bkLoad
                property string file: ""
                command: ["python3", "-I", Quickshell.shellDir + "/tools/glide-backup.py", "import", file]
                stdout: StdioCollector { onStreamFinished: { if (text.indexOf('"ok": true') >= 0) Quickshell.execDetached(["systemctl", "--user", "restart", "glide-shell.service"]) } }
                stderr: StdioCollector { onStreamFinished: if (text.trim() && sv.panel) sv.panel.flash("!", text.trim().split("\n").pop(), Theme.error) }
            }
            ActionBtn { glyph: String.fromCodePoint(0xF0193); text: Tr.t("Сохранить настройки в файл"); onClicked: { bkSave.running = false; bkSave.running = true } }
        }
        Flow {
            visible: bkRow.found.length > 0
            Layout.fillWidth: true
            spacing: 6
            Repeater {
                model: bkRow.found
                delegate: ActionBtn {
                    required property var modelData
                    glyph: String.fromCodePoint(0xF0B6A)
                    text: bkRow.pending === modelData.path ? Tr.t("Ещё раз — восстановить") : modelData.name.replace("glide-shell-settings-", "").replace(".tar.gz", "")
                    onClicked: {
                        if (bkRow.pending !== modelData.path) { bkRow.pending = modelData.path; bkPend.restart(); return }
                        bkRow.pending = ""; bkLoad.file = modelData.path; bkLoad.running = false; bkLoad.running = true
                    }
                }
            }
            Timer { id: bkPend; interval: 4000; onTriggered: bkRow.pending = "" }
        }
        Text {
            visible: bkRow.found.length > 0
            Layout.fillWidth: true
            text: Tr.t("Восстановить — щелчок по копии и ещё раз; текущие настройки перед этим сохраняются рядом (…-before-import), оболочка перезапустится")
            color: Theme.textMuted; font.pixelSize: Theme.fs(11); wrapMode: Text.WordWrap
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
            label: Tr.t("Тема")
            options: [{ label: Tr.t("тёмная"), value: "dark" }, { label: Tr.t("светлая"), value: "light" },
                      { label: Tr.t("авто (по солнцу)"), value: "auto" }]
            current: Prefs.themeMode
            onPicked: (v) => Prefs.set("themeMode", v)
        }
        Text {
            visible: Prefs.themeMode === "auto"
            Layout.fillWidth: true
            text: Tr.t("Светлая с восхода до заката (время — из погоды: ") + NightLight.sunrise + "–" + NightLight.sunset + ")"
            color: Theme.textMuted; font.pixelSize: Theme.fs(11); wrapMode: Text.WordWrap
        }
        ToggleRow {
            icon: String.fromCodePoint(0xF03D8)
            label: Tr.t("Тема и акцент — приложениям")
            hint: Tr.t("Светлая/тёмная схема и акцент для GTK-, Qt-приложений и браузеров (через системную настройку)")
            checked: Prefs.themeApps
            onToggled: Prefs.set("themeApps", !Prefs.themeApps)
        }
        ToggleRow {
            visible: Prefs.themeApps
            icon: String.fromCodePoint(0xF03D8)
            label: Tr.t("И старые GTK3-приложения")
            hint: Tr.t("Меняет тему Adwaita ↔ Adwaita-dark (только если стоит одна из них)")
            checked: Prefs.themeGtk3
            onToggled: Prefs.set("themeGtk3", !Prefs.themeGtk3)
        }
        ChoiceRow {
            visible: Prefs.themeMode !== "light"
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
    // значок виджета: сам символ («󰖌») или его код («F051F») — оба вида допустимы
    function iconCode(s) { return /^[0-9a-fA-F]{4,6}$/.test(s) ? parseInt(s, 16) : String(s).codePointAt(0) }
    function wGlyph(w) { var m = wMeta(w); return w.type === "custom" ? (m && m.icon ? sv.iconCode(m.icon) : 0xF0B6F) : wType(w.type).glyph }
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
                    glyph: String.fromCodePoint(modelData.icon ? sv.iconCode(modelData.icon) : 0xF0B6F)
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
        Text {
            visible: Prefs.notifMuted.length > 0
            Layout.fillWidth: true
            text: Tr.t("Без всплывашек (уведомления только в истории; отключить приложение — колокольчик у его уведомлений в панели):")
            color: Theme.textSecondary; font.pixelSize: Theme.fs(12); wrapMode: Text.WordWrap
        }
        Flow {
            visible: Prefs.notifMuted.length > 0
            Layout.fillWidth: true
            spacing: 6
            Repeater {
                model: Prefs.notifMuted
                delegate: ActionBtn {
                    required property string modelData
                    glyph: String.fromCodePoint(0xF009B)
                    text: modelData + "  ✕"
                    onClicked: Prefs.notifMute(modelData, false)
                }
            }
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
        function reload() { rd.running = false; rd.running = true; od.running = false; od.running = true; asList.running = false; asList.running = true }
        Process {
            id: rd
            command: ["python3", "-I", niriPage.tool, "read"]
            stdout: StdioCollector { onStreamFinished: { try { niriPage.cfg = JSON.parse(text) } catch (e) {} } }
        }
        Process {
            id: od
            command: ["niri", "msg", "-j", "outputs"]
            stdout: StdioCollector {
                onStreamFinished: {
                    try {
                        var o = JSON.parse(text), inner = n => /^(eDP|LVDS|DSI)/.test(n) ? 0 : 1   // встроенный экран — первым
                        niriPage.outs = Object.keys(o).sort((a, b) => inner(a) - inner(b) || a.localeCompare(b)).map(k => o[k])
                        niriPage.outs.forEach(x => { if (x.logical) niriPage.lastOn[x.name] = niriPage.outItem(x) })
                    } catch (e) {}
                }
            }
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
        // команды niri msg output — строго по очереди; список мониторов перечитать, когда очередь опустела
        // (иначе перечитывали раньше, чем niri применил, и «Оставить» сохраняло прежнее состояние)
        property var outQueue: []
        function outRun(name, args) { outQueue = outQueue.concat([["niri", "msg", "output", name].concat(args)]); if (!ow.running) outNext() }
        function outNext() {
            if (outQueue.length) { ow.command = outQueue[0]; outQueue = outQueue.slice(1); ow.running = true }
            else { od.running = false; od.running = true }
        }
        Process { id: ow; onExited: niriPage.outNext() }
        function outChange(o, args, back) {
            if (pending && pending.name !== o.name) outKeep()
            if (!pending) pending = { name: o.name, back: [] }
            pending.back.push(back)
            outRun(o.name, args)
            secsLeft = 15; countdown.restart()
        }
        function outRevert() {
            if (!pending) return
            for (var i = pending.back.length - 1; i >= 0; i--) outRun(pending.name, pending.back[i])
            pending = null; countdown.stop()
        }
        Timer { id: keepLater; interval: 150; onTriggered: niriPage.outKeep() }
        property var lastOn: ({})   // последние настройки включённых мониторов — выключенный сохраняется с ними
        function outItem(o) {
            var m = o.modes[o.current_mode] || o.modes[0]
            return { name: o.name, mode: m ? m.width + "x" + m.height + "@" + (m.refresh_rate / 1000).toFixed(3) : "",
                     scale: o.logical ? o.logical.scale : 1, transform: o.logical ? (niriPage.tfNames[o.logical.transform] || "normal") : "normal",
                     x: o.logical ? o.logical.x : 0, y: o.logical ? o.logical.y : 0, vrr: !!o.vrr_enabled }
        }
        function outKeep() {
            countdown.stop(); pending = null
            if (ow.running || outQueue.length || od.running) { keepLater.restart(); return }   // сначала — свежий список
            var items = outs.map(o => o.logical ? outItem(o) : Object.assign({}, lastOn[o.name] || { name: o.name }, { off: true }))
            Quickshell.execDetached(["python3", "-I", tool, "save-outputs", JSON.stringify(items)])
        }
        Timer { id: countdown; interval: 1000; repeat: true
                onTriggered: { niriPage.secsLeft--; if (niriPage.secsLeft <= 0) niriPage.outRevert() } }
        readonly property var tfNames: ({ Normal: "normal", _90: "90", _180: "180", _270: "270" })
        function sideOf(a, b) {   // a относительно b: left | right | above | below
            if (a.x >= b.x + b.width) return "right"
            if (a.x + a.width <= b.x) return "left"
            return a.y + a.height / 2 < b.y + b.height / 2 ? "above" : "below"
        }
        function placeAt(a, b, side) {   // новое место a вплотную к b, выровнять по верху/левому краю
            return side === "right" ? { x: b.x + b.width, y: b.y } : side === "left" ? { x: b.x - a.width, y: b.y }
                 : side === "above" ? { x: b.x, y: b.y - a.height } : { x: b.x, y: b.y + b.height }
        }

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
                ToggleRow {   // выключить можно любой, кроме последнего включённого
                    visible: niriPage.outs.length > 1
                    label: Tr.t("Включён")
                    hint: !oc.o.logical ? Tr.t("Монитор выключен — niri его не использует")
                          : niriPage.outs.filter(x => x.logical).length < 2 ? Tr.t("Последний включённый монитор выключить нельзя") : ""
                    checked: !!oc.o.logical
                    onToggled: {
                        if (oc.o.logical && niriPage.outs.filter(x => x.logical).length < 2) return
                        niriPage.outChange(oc.o, [oc.o.logical ? "off" : "on"], [oc.o.logical ? "on" : "off"])
                    }
                }
                ChoiceRow {
                    visible: !!oc.o.logical
                    label: Tr.t("Масштаб")
                    options: [{ label: "100%", value: 1 }, { label: "125%", value: 1.25 }, { label: "150%", value: 1.5 },
                              { label: "175%", value: 1.75 }, { label: "200%", value: 2 }]
                    current: oc.lg.scale
                    onPicked: (v) => niriPage.outChange(oc.o, ["scale", String(v)], ["scale", String(oc.lg.scale)])
                }
                ChipChoice {
                    visible: !!oc.o.logical && oc.o.modes.length > 1
                    label: Tr.t("Разрешение и частота")
                    options: oc.o.modes.map((m, i) => ({ label: m.width + "×" + m.height + " · " + Math.round(m.refresh_rate / 1000) + Tr.t(" Гц"), value: i }))
                    current: oc.o.current_mode
                    onPicked: (i) => {
                        var m = oc.o.modes[i], c = oc.o.modes[oc.o.current_mode]
                        niriPage.outChange(oc.o, ["mode", m.width + "x" + m.height + "@" + (m.refresh_rate / 1000).toFixed(3)],
                                           ["mode", c.width + "x" + c.height + "@" + (c.refresh_rate / 1000).toFixed(3)])
                    }
                }
                ToggleRow {
                    visible: !!oc.o.logical && oc.o.vrr_supported
                    label: Tr.t("Переменная частота (VRR)")
                    hint: Tr.t("Меньше разрывов в играх и видео; на некоторых мониторах мерцает")
                    checked: oc.o.vrr_enabled
                    onToggled: niriPage.outChange(oc.o, ["vrr", oc.o.vrr_enabled ? "off" : "on"], ["vrr", oc.o.vrr_enabled ? "on" : "off"])
                }
                ChoiceRow {   // где стоит относительно соседнего монитора
                    readonly property var ref: niriPage.outs.find(x => x.name !== oc.o.name && x.logical) || null
                    visible: !!oc.o.logical && !!ref
                    label: Tr.t("Расположение относительно ") + (ref ? ref.name : "")
                    options: [{ label: Tr.t("слева"), value: "left" }, { label: Tr.t("справа"), value: "right" },
                              { label: Tr.t("сверху"), value: "above" }, { label: Tr.t("снизу"), value: "below" }]
                    current: ref ? niriPage.sideOf(oc.lg, ref.logical) : ""
                    onPicked: (v) => {
                        var p = niriPage.placeAt(oc.lg, ref.logical, v)
                        niriPage.outChange(oc.o, ["position", "set", String(p.x), String(p.y)], ["position", "set", String(oc.lg.x), String(oc.lg.y)])
                    }
                }
                ChoiceRow {
                    visible: !!oc.o.logical
                    label: Tr.t("Поворот")
                    options: [{ label: Tr.t("обычно"), value: "normal" }, { label: "90°", value: "90" },
                              { label: "180°", value: "180" }, { label: "270°", value: "270" }]
                    current: niriPage.tfNames[oc.lg.transform] || "normal"
                    onPicked: (v) => niriPage.outChange(oc.o, ["transform", v], ["transform", niriPage.tfNames[oc.lg.transform] || "normal"])
                }
            }
        }
        Item {   // схема расположения включённых мониторов
            id: omap
            readonly property var on: niriPage.outs.filter(o => o.logical)
            readonly property real x0: Math.min.apply(null, on.map(o => o.logical.x))
            readonly property real y0: Math.min.apply(null, on.map(o => o.logical.y))
            readonly property real w: Math.max.apply(null, on.map(o => o.logical.x + o.logical.width)) - x0
            readonly property real h: Math.max.apply(null, on.map(o => o.logical.y + o.logical.height)) - y0
            readonly property real k: on.length ? Math.min(width / w, 120 / h) : 1
            visible: on.length > 1
            Layout.fillWidth: true
            implicitHeight: on.length ? h * k : 0
            Repeater {
                model: omap.on
                delegate: Rectangle {
                    required property var modelData
                    readonly property var lg: modelData.logical
                    x: (omap.width - omap.w * omap.k) / 2 + (lg.x - omap.x0) * omap.k + 2
                    y: (lg.y - omap.y0) * omap.k + 2
                    width: lg.width * omap.k - 4; height: lg.height * omap.k - 4
                    radius: Theme.r(8)
                    color: modelData.name === (niriPage.pending ? niriPage.pending.name : "") ? Qt.rgba(Prefs.accent.r, Prefs.accent.g, Prefs.accent.b, 0.25) : Theme.surfaceHigh
                    border.color: Theme.outline
                    Behavior on x { NumberAnimation { duration: Prefs.ms(220); easing.type: Easing.OutCubic } }
                    Behavior on y { NumberAnimation { duration: Prefs.ms(220); easing.type: Easing.OutCubic } }
                    Text { anchors.centerIn: parent; text: modelData.name; color: Theme.textSecondary; font.pixelSize: Theme.fs(11) }
                }
            }
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

        // ---- окна, анимации, курсор, угол (glide-niri.py set-look) ----
        Process {
            id: lk
            property string patch: ""
            command: ["python3", "-I", niriPage.tool, "set-look", patch]
            stdout: StdioCollector {
                onStreamFinished: {
                    var r = {}; try { r = JSON.parse(text) } catch (e) {}
                    if (!r.ok && sv.panel) sv.panel.flash("!", Tr.t("niri не принял настройку — вернул как было"), Theme.error)
                    niriPage.reload()
                }
            }
        }
        function setLook(patch) {
            var c = JSON.parse(JSON.stringify(cfg))
            for (var k in patch) {
                if (typeof patch[k] === "object" && patch[k] !== null) Object.assign(c.look[k], patch[k]); else c.look[k] = patch[k]
            }
            cfg = c
            lk.patch = JSON.stringify(patch); lk.running = false; lk.running = true
        }
        readonly property var look: cfg ? cfg.look : null
        Header { visible: !!niriPage.look; text: Tr.t("ОКНА") }
        ChoiceRow {
            visible: !!niriPage.look
            label: Tr.t("Зазоры между окнами")
            options: [{ label: "0", value: 0 }, { label: "4", value: 4 }, { label: "6", value: 6 }, { label: "10", value: 10 },
                      { label: "16", value: 16 }, { label: "24", value: 24 }]
            current: niriPage.look ? niriPage.look.gaps : 0
            onPicked: (v) => niriPage.setLook({ gaps: v })
        }
        ChoiceRow {
            visible: !!niriPage.look
            label: Tr.t("Скругление углов окон")
            options: [{ label: Tr.t("нет"), value: 0 }, { label: "8", value: 8 }, { label: "12", value: 12 },
                      { label: "16", value: 16 }, { label: "20", value: 20 }]
            current: niriPage.look ? niriPage.look.radius : 0
            onPicked: (v) => niriPage.setLook({ radius: v })
        }
        ToggleRow {
            visible: !!niriPage.look
            icon: String.fromCodePoint(0xF0E5F)
            label: Tr.t("Рамка вокруг активного окна")
            checked: !!niriPage.look && niriPage.look.ring.on
            onToggled: niriPage.setLook({ ring: { on: !niriPage.look.ring.on } })
        }
        ChoiceRow {
            visible: !!niriPage.look && niriPage.look.ring.on
            label: Tr.t("Толщина рамки")
            options: [{ label: "1", value: 1 }, { label: "2", value: 2 }, { label: "3", value: 3 }, { label: "4", value: 4 }, { label: "6", value: 6 }]
            current: niriPage.look ? niriPage.look.ring.width : 2
            onPicked: (v) => niriPage.setLook({ ring: { width: v } })
        }
        ToggleRow {
            visible: !!niriPage.look && niriPage.look.ring.on
            icon: String.fromCodePoint(0xF03D8)
            label: Tr.t("Рамка — цветом акцента Glide")
            hint: Tr.t("Меняется вместе с акцентом в «Виде»")
            checked: Prefs.niriAccent
            onToggled: { Prefs.set("niriAccent", !Prefs.niriAccent)
                         if (!Prefs.niriAccent) niriPage.setLook({ ring: { color: Prefs.accent.toString() }, border: { color: Prefs.accent.toString() } }) }
        }
        ToggleRow {
            visible: !!niriPage.look
            icon: String.fromCodePoint(0xF0E5F)
            label: Tr.t("Обводка у всех окон")
            hint: Tr.t("Тонкая рамка и у неактивных окон")
            checked: !!niriPage.look && niriPage.look.border.on
            onToggled: niriPage.setLook({ border: { on: !niriPage.look.border.on } })
        }
        ChoiceRow {
            visible: !!niriPage.look
            label: Tr.t("Ширина нового окна")
            options: [{ label: "⅓", value: 0.33333 }, { label: "½", value: 0.5 }, { label: "⅔", value: 0.66667 }, { label: Tr.t("во всю"), value: 1.0 }]
            current: niriPage.look ? [0.33333, 0.5, 0.66667, 1.0].reduce((a, b) => Math.abs(b - niriPage.look.colw) < Math.abs(a - niriPage.look.colw) ? b : a) : 0.5
            onPicked: (v) => niriPage.setLook({ colw: v })
        }
        ChoiceRow {
            visible: !!niriPage.look
            label: Tr.t("Активное окно — по центру")
            options: [{ label: Tr.t("нет"), value: "never" }, { label: Tr.t("если не влезает"), value: "on-overflow" }, { label: Tr.t("всегда"), value: "always" }]
            current: niriPage.look ? niriPage.look.center : "never"
            onPicked: (v) => niriPage.setLook({ center: v })
        }
        ToggleRow {
            visible: !!niriPage.look
            icon: String.fromCodePoint(0xF0A8A)
            label: Tr.t("Обзор окон — мышью в левый верхний угол")
            checked: !!niriPage.look && niriPage.look.hotcorner
            onToggled: niriPage.setLook({ hotcorner: !niriPage.look.hotcorner })
        }
        Header { visible: !!niriPage.look; text: Tr.t("АНИМАЦИИ NIRI") }
        ChoiceRow {
            visible: !!niriPage.look
            label: Tr.t("Окна и рабочие столы")
            options: [{ label: Tr.t("обычные"), value: "normal" }, { label: Tr.t("быстрые"), value: "fast" }, { label: Tr.t("выкл"), value: "off" }]
            current: niriPage.look ? niriPage.look.anim : "normal"
            onPicked: (v) => niriPage.setLook({ anim: v })
        }
        Header { visible: !!niriPage.look; text: Tr.t("КУРСОР") }
        ChipChoice {
            visible: !!niriPage.cfg && niriPage.cfg.cursors.length > 0
            label: Tr.t("Тема курсора")
            options: [{ label: Tr.t("по умолчанию"), value: "" }].concat(niriPage.cfg ? niriPage.cfg.cursors.map(c => ({ label: c, value: c })) : [])
            current: niriPage.look ? niriPage.look.cursor.theme : ""
            onPicked: (v) => niriPage.setLook({ cursor: { theme: v } })
        }
        ChoiceRow {
            visible: !!niriPage.look
            label: Tr.t("Размер курсора")
            options: [{ label: Tr.t("обычный"), value: 24 }, { label: Tr.t("крупнее"), value: 32 }, { label: Tr.t("большой"), value: 48 }]
            current: niriPage.look ? niriPage.look.cursor.size : 24
            onPicked: (v) => niriPage.setLook({ cursor: { size: v } })
        }
        ToggleRow {
            visible: !!niriPage.look
            icon: String.fromCodePoint(0xF030C)
            label: Tr.t("Прятать курсор при наборе текста")
            checked: !!niriPage.look && niriPage.look.cursor.hide_typing
            onToggled: niriPage.setLook({ cursor: { hide_typing: !niriPage.look.cursor.hide_typing } })
        }

        // ---- приложения при входе: XDG-автозапуск (tools/glide-autostart.py) ----
        Header { visible: !!niriPage.cfg; text: Tr.t("ПРИЛОЖЕНИЯ ПРИ ВХОДЕ") }
        property var autos: []
        property string addFilter: ""
        Process {
            id: asList
            command: ["python3", "-I", Quickshell.shellDir + "/tools/glide-autostart.py", "list"]
            stdout: StdioCollector { onStreamFinished: { try { niriPage.autos = JSON.parse(text) } catch (e) { niriPage.autos = [] } } }
        }
        Process { id: asAct; onExited: { asList.running = false; asList.running = true } }
        function autostart(args) { asAct.command = ["python3", "-I", Quickshell.shellDir + "/tools/glide-autostart.py"].concat(args); asAct.running = false; asAct.running = true }
        Repeater {
            model: niriPage.cfg ? niriPage.autos : []
            delegate: Rectangle {
                id: ar
                required property var modelData
                Layout.fillWidth: true
                implicitHeight: 44; radius: Theme.r(14)
                color: Theme.surface; border.color: Theme.outline
                opacity: modelData.enabled ? 1 : 0.7
                Behavior on opacity { NumberAnimation { duration: Prefs.ms(160) } }
                IconImage {
                    id: arIcon
                    readonly property string path: (ar.modelData.icon && (ar.modelData.icon.startsWith("/") ? "file://" + ar.modelData.icon
                                                     : Quickshell.iconPath(ar.modelData.icon, true))) || Quickshell.iconPath("application-x-executable", true)
                    visible: path !== ""
                    x: 12; anchors.verticalCenter: parent.verticalCenter
                    implicitSize: 22
                    source: path
                }
                Text {   // значка нет и в теме — глиф приложения
                    visible: !arIcon.visible
                    x: 12; anchors.verticalCenter: parent.verticalCenter
                    text: String.fromCodePoint(0xF003B); color: Theme.textSecondary
                    font.family: Prefs.iconFont; font.pixelSize: Theme.fs(20)
                }
                Column {
                    x: 44; anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 44 - 100
                    Text { width: parent.width; text: ar.modelData.name; color: Theme.text; font.pixelSize: Theme.fs(13); elide: Text.ElideRight }
                    Text { width: parent.width; text: ar.modelData.system ? Tr.t("системное") : Tr.t("добавлено"); color: Theme.textMuted; font.pixelSize: Theme.fs(11) }
                }
                Rectangle {   // убрать (своё)
                    visible: ar.modelData.mine
                    anchors.right: arSw.left; anchors.rightMargin: 6; anchors.verticalCenter: parent.verticalCenter
                    width: 26; height: 26; radius: 13
                    color: arX.pressed ? Theme.surfacePressed : arX.containsMouse ? Theme.surfaceHigher : "transparent"
                    scale: arX.pressed ? 0.88 : 1
                    Behavior on color { ColorAnimation { duration: Prefs.ms(120) } }
                    Behavior on scale { NumberAnimation { duration: Prefs.ms(140); easing.type: Easing.OutBack } }
                    Text { anchors.centerIn: parent; text: String.fromCodePoint(0xF0156); color: Theme.textSecondary
                           font.family: Prefs.iconFont; font.pixelSize: Theme.fs(13) }
                    MouseArea { id: arX; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: niriPage.autostart(["remove", ar.modelData.file]) }
                }
                Switch {
                    id: arSw
                    anchors.right: parent.right; anchors.rightMargin: 10; anchors.verticalCenter: parent.verticalCenter
                    checked: ar.modelData.enabled
                    onToggled: niriPage.autostart(["set", ar.modelData.file, ar.modelData.enabled ? "off" : "on"])
                }
            }
        }
        TextRow {
            visible: !!niriPage.cfg
            label: Tr.t("Добавить приложение (начни вводить имя, Enter)")
            placeholder: Tr.t("например, Telegram")
            value: niriPage.addFilter
            onSubmitted: (v) => niriPage.addFilter = v
        }
        Flow {
            visible: niriPage.addFilter.length > 0
            Layout.fillWidth: true
            spacing: 6
            Repeater {
                model: {
                    var f = niriPage.addFilter.toLowerCase(), have = niriPage.autos.map(a => a.file)
                    return f ? DesktopEntries.applications.values.filter(e => !e.noDisplay && e.name.toLowerCase().indexOf(f) >= 0
                                                                          && have.indexOf(e.id + ".desktop") < 0).slice(0, 8) : []
                }
                delegate: ActionBtn {
                    required property var modelData
                    glyph: String.fromCodePoint(0xF0415)
                    text: modelData.name
                    onClicked: { niriPage.autostart(["add", modelData.id + ".desktop"]); niriPage.addFilter = "" }
                }
            }
        }
        Text {
            Layout.fillWidth: true
            visible: !!niriPage.cfg
            text: Tr.t("Действует со следующего входа. Служебные команды niri (spawn-at-startup) — только для просмотра: ") +
                  (niriPage.cfg ? niriPage.cfg.spawns.map(x => x.split(" ")[0].split("/").pop()).join(", ") : "")
            color: Theme.textMuted; font.pixelSize: Theme.fs(11); wrapMode: Text.WordWrap
        }

        Header { visible: !!niriPage.cfg; text: Tr.t("ГОРЯЧИЕ КЛАВИШИ") }
        // ---- редактор клавиш (glide-niri.py bind): новые и изменённые — в glide-settings.kdl ----
        property var be: null                     // {key, argv, title, old, kind}
        property string appFilter: ""
        Process {
            id: bw
            property string op: ""
            command: ["python3", "-I", niriPage.tool, "bind", op]
            stdout: StdioCollector {
                onStreamFinished: {
                    var r = {}; try { r = JSON.parse(text) } catch (e) {}
                    if (r.ok) { niriPage.be = null; if (sv.panel) sv.panel.flash(String.fromCodePoint(0xF012C), Tr.t("Клавиши сохранены"), Theme.success) }
                    else if (sv.panel) sv.panel.flash("!", Tr.t("niri не принял — проверь сочетание и действие"), Theme.error)
                    niriPage.reload()
                }
            }
        }
        function bindRun(op) { bw.op = JSON.stringify(op); bw.running = false; bw.running = true }
        function keyName(e) {   // событие клавиши Qt → имя niri (Mod — Super)
            var k = e.key, base = ""
            if (k >= Qt.Key_A && k <= Qt.Key_Z) base = String.fromCharCode(k)
            else if (k >= Qt.Key_0 && k <= Qt.Key_9) base = String.fromCharCode(k)
            else if (k >= Qt.Key_F1 && k <= Qt.Key_F24) base = "F" + (k - Qt.Key_F1 + 1)
            else base = ({ [Qt.Key_Left]: "Left", [Qt.Key_Right]: "Right", [Qt.Key_Up]: "Up", [Qt.Key_Down]: "Down",
                           [Qt.Key_Return]: "Return", [Qt.Key_Enter]: "Return", [Qt.Key_Space]: "Space", [Qt.Key_Tab]: "Tab",
                           [Qt.Key_Escape]: "Escape", [Qt.Key_Backspace]: "BackSpace", [Qt.Key_Delete]: "Delete",
                           [Qt.Key_Home]: "Home", [Qt.Key_End]: "End", [Qt.Key_PageUp]: "Page_Up", [Qt.Key_PageDown]: "Page_Down",
                           [Qt.Key_Print]: "Print", [Qt.Key_Minus]: "Minus", [Qt.Key_Equal]: "Equal", [Qt.Key_Comma]: "Comma",
                           [Qt.Key_Period]: "Period", [Qt.Key_Slash]: "Slash", [Qt.Key_Semicolon]: "Semicolon",
                           [Qt.Key_Apostrophe]: "Apostrophe", [Qt.Key_BracketLeft]: "BracketLeft", [Qt.Key_BracketRight]: "BracketRight",
                           [Qt.Key_Backslash]: "Backslash", [Qt.Key_QuoteLeft]: "Grave",
                           [Qt.Key_VolumeUp]: "XF86AudioRaiseVolume", [Qt.Key_VolumeDown]: "XF86AudioLowerVolume", [Qt.Key_VolumeMute]: "XF86AudioMute",
                           [Qt.Key_MediaPlay]: "XF86AudioPlay", [Qt.Key_MediaNext]: "XF86AudioNext", [Qt.Key_MediaPrevious]: "XF86AudioPrev" })[k] || ""
            if (!base) return ""
            var m = []
            if (e.modifiers & Qt.MetaModifier) m.push("Mod")
            if (e.modifiers & Qt.ControlModifier) m.push("Ctrl")
            if (e.modifiers & Qt.AltModifier) m.push("Alt")
            if (e.modifiers & Qt.ShiftModifier) m.push("Shift")
            return m.concat([base]).join("+")
        }
        readonly property var niriActions: [
            { l: Tr.t("Закрыть окно"), a: ["close-window"] }, { l: Tr.t("Во весь экран"), a: ["fullscreen-window"] },
            { l: Tr.t("Развернуть колонку"), a: ["maximize-column"] }, { l: Tr.t("Плавающее окно"), a: ["toggle-window-floating"] },
            { l: Tr.t("Колонку по центру"), a: ["center-column"] }, { l: Tr.t("Следующая ширина колонки"), a: ["switch-preset-column-width"] },
            { l: Tr.t("Обзор окон"), a: ["toggle-overview"] }, { l: Tr.t("Стол ниже"), a: ["focus-workspace-down"] },
            { l: Tr.t("Стол выше"), a: ["focus-workspace-up"] }, { l: Tr.t("Окно — на стол ниже"), a: ["move-column-to-workspace-down"] },
            { l: Tr.t("Окно — на стол выше"), a: ["move-column-to-workspace-up"] }, { l: Tr.t("Колонка левее"), a: ["focus-column-left"] },
            { l: Tr.t("Колонка правее"), a: ["focus-column-right"] }, { l: Tr.t("Скриншот niri"), a: ["screenshot"] },
            { l: Tr.t("Выключить мониторы"), a: ["power-off-monitors"] }, { l: Tr.t("Подсказка по клавишам"), a: ["show-hotkey-overlay"] }
        ].concat([1, 2, 3, 4, 5].map(n => ({ l: Tr.t("Перейти на стол ") + n, a: ["focus-workspace", String(n)] })))
         .concat([1, 2, 3, 4, 5].map(n => ({ l: Tr.t("Окно на стол ") + n, a: ["move-column-to-workspace", String(n)] })))
        readonly property var glideActions: [
            { l: Tr.t("Центр управления"), a: ["panel", "category", "control"] }, { l: Tr.t("Приложения"), a: ["panel", "launcher"] },
            { l: Tr.t("Панель"), a: ["panel", "toggle"] }, { l: Tr.t("Буфер обмена"), a: ["panel", "category", "clipboard"] },
            { l: Tr.t("Уведомления"), a: ["panel", "category", "notify"] }, { l: Tr.t("Сегодня"), a: ["panel", "category", "today"] },
            { l: Tr.t("Настройки"), a: ["panel", "settings"] }, { l: Tr.t("Заблокировать экран"), a: ["lock", "lock"] },
            { l: Tr.t("Ночной свет"), a: ["panel", "night", "toggle"] }, { l: Tr.t("Не засыпать"), a: ["panel", "awake", "toggle"] },
            { l: Tr.t("Запись экрана"), a: ["panel", "record", ""] }
        ]
        function glideArgv(a) { return ["spawn", "qs", "-c", "glide-shell", "ipc", "call"].concat(a) }
        function describe(argv) {   // понятное имя действия для списка
            if (!argv || !argv.length) return ""
            var j = JSON.stringify(argv)
            var n = niriActions.find(x => JSON.stringify(x.a) === j); if (n) return n.l
            var g = glideActions.find(x => JSON.stringify(glideArgv(x.a)) === j); if (g) return "Glide · " + g.l
            if (argv[0] === "spawn" && argv[5] === "call" && argv[6] === "panel" && argv[7] === "launch") {
                var e = DesktopEntries.byId(argv[8]); return Tr.t("Запустить ") + (e ? e.name : argv[8])
            }
            return argv.join(" ")
        }
        ActionBtn {
            visible: !!niriPage.cfg && !niriPage.be
            glyph: String.fromCodePoint(0xF0415); text: Tr.t("Новая клавиша")
            onClicked: niriPage.be = { key: "", argv: [], title: "", old: "", kind: "app" }
        }
        Rectangle {   // карточка редактора
            visible: !!niriPage.be
            Layout.fillWidth: true
            implicitHeight: edCol.implicitHeight + 28
            radius: Theme.r(18)
            color: Theme.surface; border.color: Theme.accent
            ColumnLayout {
                id: edCol
                x: 14; y: 14; width: parent.width - 28
                spacing: 10
                Text { text: niriPage.be && niriPage.be.old ? Tr.t("Изменить: ") + niriPage.be.old : Tr.t("Новая клавиша"); color: Theme.text; font.bold: true; font.pixelSize: Theme.fs(14) }
                // запись сочетания
                Rectangle {
                    id: capBox
                    Layout.fillWidth: true
                    implicitHeight: 40; radius: Theme.r(12)
                    color: Theme.surfaceHigh
                    border.width: capBox.activeFocus ? 2 : 1
                    border.color: capBox.activeFocus ? Theme.accent : Theme.outline
                    activeFocusOnTab: true
                    Keys.onPressed: (e) => {
                        var n = niriPage.keyName(e)
                        if (n) { var b = Object.assign({}, niriPage.be); b.key = n; niriPage.be = b }
                        e.accepted = true
                    }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: capBox.forceActiveFocus() }
                    Text {
                        anchors.centerIn: parent
                        text: niriPage.be && niriPage.be.key ? niriPage.be.key : capBox.activeFocus ? Tr.t("Нажми сочетание…") : Tr.t("Щёлкни и нажми сочетание")
                        color: niriPage.be && niriPage.be.key ? Theme.text : Theme.textMuted
                        font.pixelSize: Theme.fs(14); font.family: niriPage.be && niriPage.be.key ? "JetBrainsMono Nerd Font" : Theme.fontFamily || ""
                    }
                }
                TextRow {
                    label: Tr.t("…или впиши (Enter): Mod+Shift+T, Ctrl+Alt+Delete")
                    value: niriPage.be ? niriPage.be.key : ""
                    onSubmitted: (v) => { var b = Object.assign({}, niriPage.be); b.key = v.replace(/\s+/g, ""); niriPage.be = b }
                }
                Text {   // занятость
                    readonly property var other: niriPage.be && niriPage.cfg ? niriPage.cfg.binds.find(b => b.key.toLowerCase() === niriPage.be.key.toLowerCase()
                                                                                   && b.key.toLowerCase() !== (niriPage.be.old || "").toLowerCase()) : null
                    visible: !!other
                    Layout.fillWidth: true
                    text: other ? Tr.t("Уже занято: ") + (other.title || niriPage.describe(other.argv)) + Tr.t(" — сохранение заменит") : ""
                    color: Theme.warning; font.pixelSize: Theme.fs(12); wrapMode: Text.WordWrap
                }
                ChoiceRow {
                    label: Tr.t("Что делать")
                    options: [{ label: Tr.t("приложение"), value: "app" }, { label: "niri", value: "niri" },
                              { label: "Glide Shell", value: "glide" }, { label: Tr.t("команда"), value: "cmd" }]
                    current: niriPage.be ? niriPage.be.kind : "app"
                    onPicked: (v) => { var b = Object.assign({}, niriPage.be); b.kind = v; niriPage.be = b }
                }
                TextRow {
                    visible: !!niriPage.be && niriPage.be.kind === "app"
                    label: Tr.t("Приложение (начни вводить, Enter)")
                    value: niriPage.appFilter
                    onSubmitted: (v) => niriPage.appFilter = v
                }
                Flow {
                    visible: !!niriPage.be && (niriPage.be.kind !== "cmd")
                    Layout.fillWidth: true
                    spacing: 6
                    Repeater {
                        model: !niriPage.be ? []
                             : niriPage.be.kind === "niri" ? niriPage.niriActions
                             : niriPage.be.kind === "glide" ? niriPage.glideActions.map(x => ({ l: x.l, a: niriPage.glideArgv(x.a) }))
                             : (niriPage.appFilter ? DesktopEntries.applications.values.filter(e => !e.noDisplay && e.name.toLowerCase().indexOf(niriPage.appFilter.toLowerCase()) >= 0).slice(0, 10) : [])
                               .map(e => ({ l: e.name, a: ["spawn", "qs", "-c", "glide-shell", "ipc", "call", "panel", "launch", e.id] }))
                        delegate: Rectangle {
                            id: ac
                            required property var modelData
                            readonly property bool sel: !!niriPage.be && JSON.stringify(niriPage.be.argv) === JSON.stringify(modelData.a)
                            width: acT.implicitWidth + 22; height: 30; radius: 15
                            color: sel ? (acM.containsMouse ? Theme.accentLight : Theme.accent) : acM.pressed ? Theme.surfacePressed : acM.containsMouse ? Theme.surfaceHigher : Theme.surfaceHigh
                            scale: acM.pressed ? 0.95 : 1
                            Behavior on color { ColorAnimation { duration: Prefs.ms(120) } }
                            Behavior on scale { NumberAnimation { duration: Prefs.ms(140); easing.type: Easing.OutBack } }
                            Text { id: acT; anchors.centerIn: parent; text: ac.modelData.l; font.pixelSize: Theme.fs(12)
                                   color: ac.sel ? Theme.accentText : Theme.text }
                            MouseArea { id: acM; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                        onClicked: { var b = Object.assign({}, niriPage.be); b.argv = ac.modelData.a; if (!b.title) b.title = ac.modelData.l; niriPage.be = b } }
                        }
                    }
                }
                TextRow {
                    visible: !!niriPage.be && niriPage.be.kind === "cmd"
                    label: Tr.t("Команда (как в терминале, Enter)")
                    placeholder: "alacritty -e btop"
                    value: niriPage.be && niriPage.be.argv[0] === "spawn-sh" ? niriPage.be.argv[1] : ""
                    onSubmitted: (v) => { var b = Object.assign({}, niriPage.be); b.argv = ["spawn-sh", v]; niriPage.be = b }
                }
                TextRow {
                    label: Tr.t("Подпись в подсказке niri (Enter)")
                    value: niriPage.be ? niriPage.be.title : ""
                    onSubmitted: (v) => { var b = Object.assign({}, niriPage.be); b.title = v; niriPage.be = b }
                }
                Text {
                    Layout.fillWidth: true
                    visible: !!niriPage.be && niriPage.be.argv.length > 0
                    text: niriPage.be ? Tr.t("Действие: ") + niriPage.describe(niriPage.be.argv) : ""
                    color: Theme.textSecondary; font.pixelSize: Theme.fs(12); wrapMode: Text.WordWrap
                }
                RowLayout {
                    spacing: 8
                    ActionBtn { glyph: String.fromCodePoint(0xF012C); text: Tr.t("Сохранить"); enabled: !!niriPage.be && !!niriPage.be.key && niriPage.be.argv.length > 0
                                onClicked: niriPage.bindRun({ key: niriPage.be.key, argv: niriPage.be.argv, title: niriPage.be.title, old: niriPage.be.old }) }
                    ActionBtn { visible: !!niriPage.be && !!niriPage.be.old; glyph: String.fromCodePoint(0xF0A79); text: Tr.t("Удалить")
                                onClicked: niriPage.bindRun({ delete: niriPage.be.old }) }
                    ActionBtn { glyph: String.fromCodePoint(0xF0156); text: Tr.t("Отмена"); onClicked: niriPage.be = null }
                }
            }
        }
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
                var all = niriPage.cfg.binds.filter(b => !f || (b.key + " " + b.title + " " + b.action + " " + niriPage.describe(b.argv)).toLowerCase().indexOf(f) >= 0)
                return all.slice(0, 80)
            }
            delegate: Rectangle {
                id: brow
                required property var modelData
                Layout.fillWidth: true
                implicitHeight: 34; radius: Theme.r(10)
                color: bma.pressed ? Theme.surfacePressed : bma.containsMouse && modelData.editable ? Theme.surfaceHigh : "transparent"
                Behavior on color { ColorAnimation { duration: Prefs.ms(120) } }
                MouseArea {
                    id: bma; anchors.fill: parent; hoverEnabled: true
                    cursorShape: brow.modelData.editable ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: if (brow.modelData.editable) {
                        var a = brow.modelData.argv
                        var kind = a[0] === "spawn" && a[1] === "qs" ? (a[7] === "launch" ? "app" : "glide") : a[0] === "spawn" || a[0] === "spawn-sh" ? "cmd" : "niri"
                        niriPage.be = { key: brow.modelData.key, argv: a[0] === "spawn" && kind === "cmd" ? ["spawn-sh", a.slice(1).join(" ")] : a,
                                        title: brow.modelData.title, old: brow.modelData.key, kind: kind }
                    }
                }
                Rectangle {
                    x: 4; anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(170, keyT.implicitWidth + 16); height: 26; radius: Theme.r(8)
                    color: Theme.surfaceHigh; border.color: Theme.outline
                    Text { id: keyT; anchors.centerIn: parent; width: Math.min(implicitWidth, 154); elide: Text.ElideRight
                           text: brow.modelData.key; color: Theme.text; font.pixelSize: Theme.fs(12); font.family: "JetBrainsMono Nerd Font" }
                }
                Text { x: 184; width: parent.width - 184 - 10; anchors.verticalCenter: parent.verticalCenter
                       text: brow.modelData.title || niriPage.describe(brow.modelData.argv)
                       color: brow.modelData.editable ? Theme.textSecondary : Theme.textMuted; font.pixelSize: Theme.fs(12); elide: Text.ElideRight }
            }
        }
        Text {
            Layout.fillWidth: true
            visible: !!niriPage.cfg
            text: Tr.t("Щелчок по клавише — изменить. Серые — из файлов DMS (он их перезаписывает), их меняют новой клавишей с тем же сочетанием. Сочетания, занятые niri, в поле записи не ловятся — впиши их текстом.")
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
        ToggleRow {
            icon: String.fromCodePoint(0xF033E)
            label: Tr.t("Включать и выключать плагины — по паролю")
            hint: Tr.t("Защита от случайного или чужого изменения. Снять защиту — тоже по паролю. Плагин сам её не снимет.")
            checked: Prefs.pluginLock
            onToggled: Prefs.pluginLock ? sv.guarded("lock", "") : Prefs.set("pluginLock", true)
        }
        Rectangle {   // пароль для изменения плагинов (тот же PAM, что у экрана блокировки)
            id: guardCard
            visible: sv.guardFor !== ""
            Layout.fillWidth: true
            implicitHeight: guardCol.implicitHeight + 24
            radius: Theme.r(16)
            color: Theme.surface
            border.color: sv.guardErr ? Theme.error : Prefs.accent
            onVisibleChanged: if (visible) guardInput.forceActiveFocus()
            ColumnLayout {
                id: guardCol
                x: 14; y: 12; width: parent.width - 28
                spacing: 8
                Text {
                    Layout.fillWidth: true
                    text: sv.guardFor === "lock" ? Tr.t("Пароль, чтобы снять защиту плагинов")
                        : (sv.guardTurnOn ? Tr.t("Пароль, чтобы включить «") : Tr.t("Пароль, чтобы выключить «")) + sv.guardName + "»"
                    color: Theme.text; font.pixelSize: Theme.fs(13); font.weight: Font.DemiBold; wrapMode: Text.WordWrap
                }
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 36; radius: Theme.r(18)
                    color: Theme.background
                    border.width: guardInput.activeFocus ? 2 : 1
                    border.color: guardInput.activeFocus ? Prefs.accent : Theme.outline
                    HoverHandler { cursorShape: Qt.IBeamCursor }
                    TextInput {
                        id: guardInput
                        anchors.fill: parent; anchors.leftMargin: 14; anchors.rightMargin: 14
                        verticalAlignment: TextInput.AlignVCenter
                        echoMode: TextInput.Password; passwordCharacter: "●"
                        readOnly: plPam.active
                        color: Theme.text; font.pixelSize: Theme.fs(13); clip: true
                        onTextChanged: sv.guardErr = ""
                        Keys.onReturnPressed: sv.guardSubmit()
                        Keys.onEnterPressed: sv.guardSubmit()
                        Keys.onEscapePressed: sv.guardCancel()
                    }
                }
                Text {
                    visible: !!sv.guardErr
                    text: sv.guardErr
                    color: Theme.error; font.pixelSize: Theme.fs(12)
                }
                RowLayout {
                    spacing: 8
                    ActionBtn { glyph: String.fromCodePoint(0xF012C); text: plPam.active ? Tr.t("Проверка…") : Tr.t("Подтвердить")
                                enabled: !plPam.active && guardInput.text !== ""; onClicked: sv.guardSubmit() }
                    ActionBtn { glyph: String.fromCodePoint(0xF0156); text: Tr.t("Отмена"); onClicked: sv.guardCancel() }
                }
            }
        }
        Repeater {
            model: sv.panel ? sv.panel.allPlugins : []
            delegate: ColumnLayout {
                id: plRow
                required property var modelData
                // полный манифест — только у включённых: из него схема настроек («settings», как у своих виджетов)
                readonly property var full: !modelData.disabled && sv.panel ? sv.panel.pluginById(modelData.id) : null
                readonly property var schema: full && full.settings ? full.settings : []
                readonly property var vals: Prefs.pluginSettings[modelData.id] || ({})
                function val(o) { return vals[o.key] !== undefined ? vals[o.key] : o["default"] }
                Layout.fillWidth: true
                spacing: 8
                ToggleRow {
                    icon: plRow.modelData.icon || ""
                    label: plRow.modelData.name
                    hint: plRow.modelData.problem ? Tr.t("Не загружен: ") + plRow.modelData.problem : ""
                    checked: !plRow.modelData.disabled && !plRow.modelData.problem
                    onToggled: sv.guarded(plRow.modelData.id, plRow.modelData.name, !!plRow.modelData.disabled)
                }
                Repeater {
                    model: plRow.schema
                    delegate: ColumnLayout {
                        id: pso
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.leftMargin: 30
                        ToggleRow {
                            visible: pso.modelData.type === "toggle"
                            label: pso.modelData.label || pso.modelData.key
                            hint: pso.modelData.hint || ""
                            checked: !!plRow.val(pso.modelData)
                            onToggled: Prefs.setPluginSetting(plRow.modelData.id, pso.modelData.key, !plRow.val(pso.modelData))
                        }
                        ChoiceRow {
                            visible: pso.modelData.type === "choice"
                            label: pso.modelData.label || pso.modelData.key
                            options: pso.modelData.options || []
                            current: plRow.val(pso.modelData)
                            onPicked: (v) => Prefs.setPluginSetting(plRow.modelData.id, pso.modelData.key, v)
                        }
                        ChoiceRow {   // число с небольшим диапазоном (min/max/step, до 12 значений) — выбором
                            readonly property var m: pso.modelData
                            readonly property var steps: {
                                if (m.type !== "number" || m.min === undefined || m.max === undefined) return []
                                var out = [], st = m.step || 1
                                for (var v = m.min; v <= m.max + 1e-9 && out.length <= 12; v += st) out.push({ label: String(+v.toFixed(3)), value: +v.toFixed(3) })
                                return out.length <= 12 ? out : []
                            }
                            visible: steps.length > 0
                            label: m.label || m.key
                            options: steps
                            current: Number(plRow.val(m))
                            onPicked: (v) => Prefs.setPluginSetting(plRow.modelData.id, m.key, v)
                        }
                        TextRow {
                            visible: pso.modelData.type !== "toggle" && pso.modelData.type !== "choice"
                                     && !(pso.modelData.type === "number" && pso.modelData.min !== undefined && pso.modelData.max !== undefined
                                          && (pso.modelData.max - pso.modelData.min) / (pso.modelData.step || 1) < 12)
                            label: (pso.modelData.label || pso.modelData.key) + Tr.t(" (Enter — применить)")
                            value: String(plRow.val(pso.modelData) ?? "")
                            onSubmitted: (v) => Prefs.setPluginSetting(plRow.modelData.id, pso.modelData.key,
                                                                      pso.modelData.type === "number" ? Number(v) : v)
                        }
                    }
                }
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
