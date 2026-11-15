import QtQuick
import QtQuick.Layouts
import Quickshell
import qs

// Телефон через Glide Link или KDE Connect (ядро — Phones.qml): карточка устройства и действия. Кнопки — только те,
// что поддерживает телефон и пока он на связи; уведомления телефона приходят в общий центр уведомлений сами.
// Glide Link добавляет экран и звук (в обе стороны): кнопка подсвечена, пока трансляция идёт, повторное нажатие — стоп;
// сопряжение (запрос с кодом, найденные в сети, по IP, «Забыть») и SMS — прямо здесь (SmsView.qml).
ColumnLayout {
    id: ph
    property var api
    readonly property var kc: Phones
    readonly property var d: kc.phone
    readonly property bool on: !!d && d.reachable
    readonly property bool link: kc.isLink(d)
    property string view: "main"   // main | sms | files
    property var commands: []      // команды ПК, которые телефон запускает кнопкой (Glide Link)
    spacing: 10
    Component.onCompleted: loadCommands()
    onLinkChanged: loadCommands()

    function loadCommands() {
        if (!ph.link) return
        kc.request({ cmd: "commands" }, r => { if (r.ok) ph.commands = r.commands || [] })
    }
    function addCommand(name, line) {
        if (!name.trim() || !line.trim()) return
        kc.request({ cmd: "commands-add", name: name.trim(), command: line.trim() }, r => ph.loadCommands())
    }
    function removeCommand(c) {
        var go = () => kc.request({ cmd: "commands-remove", key: c.key }, r => ph.loadCommands())
        if (ph.api) ph.api.confirm(Tr.t("Убрать команду «") + c.name + "»?", { yes: Tr.t("Убрать") }, ok => { if (ok) go() })
    }

    function nf(code) { return String.fromCodePoint(code) }
    function act(action, text) { kc.act(ph.d, action, text); if (ph.api && action !== "text") ph.api.close() }
    // трансляция: идёт — остановить, нет — начать (экран/звук телефона сначала подтверждают на самом телефоне)
    function stream(what, start, stop) {
        if (kc.streaming(ph.d, what)) { kc.act(ph.d, stop); return }
        kc.act(ph.d, start)
        if (ph.api) ph.api.flash("󰄜", start === "screen" || start === "audio" ? Tr.t("Подтвердите трансляцию на телефоне") : Tr.t("Трансляция на телефон"))
    }

    Loader {
        active: ph.view === "sms" && ph.link
        visible: active
        Layout.fillWidth: true
        sourceComponent: SmsView { device: ph.d; onBack: ph.view = "main" }
    }
    Loader {
        active: ph.view === "files" && ph.link
        visible: active
        Layout.fillWidth: true
        sourceComponent: FilesView { device: ph.d; api: ph.api; onBack: ph.view = "main" }
    }

    ColumnLayout {
    id: mainView
    visible: ph.view === "main"
    Layout.fillWidth: true
    spacing: 10

    // ---- запросы сопряжения (Glide Link): тот же код должен быть на телефоне ----
    Repeater {
        model: Prefs.glidelink ? ph.kc.linkPairing : []
        delegate: Rectangle {
            id: pr
            required property var modelData
            Layout.fillWidth: true
            implicitHeight: prCol.implicitHeight + 28
            radius: Theme.radiusLg
            color: Theme.surface
            border.width: 2
            border.color: pr.modelData.keyChanged ? Theme.error : Theme.accent
            ColumnLayout {
                id: prCol
                x: 16; y: 14
                width: parent.width - 32
                spacing: 8
                Text {
                    Layout.fillWidth: true
                    text: Tr.t("Сопряжение с «") + pr.modelData.name + "»"
                    color: Theme.text; font.pixelSize: Theme.fs(14); font.bold: true
                    elide: Text.ElideRight
                }
                Text {
                    visible: pr.modelData.keyChanged
                    Layout.fillWidth: true
                    text: Tr.t("Это устройство уже было сопряжено с другим ключом. Принимайте, только если сами его сбрасывали.")
                    color: Theme.error; font.pixelSize: Theme.fs(12)
                    wrapMode: Text.Wrap
                }
                Text {
                    text: pr.modelData.code.length === 6 ? pr.modelData.code.slice(0, 3) + " " + pr.modelData.code.slice(3) : pr.modelData.code
                    color: Theme.text; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: Theme.fs(28); font.bold: true
                }
                Text {
                    Layout.fillWidth: true
                    text: Tr.t("Сверь код с экраном телефона")
                    color: Theme.textSecondary; font.pixelSize: Theme.fs(12)
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    Act { glyph: ph.nf(0xF012C); label: Tr.t("Коды совпадают"); active: true; onClicked: ph.kc.act(pr.modelData, "accept") }
                    Act { glyph: ph.nf(0xF0156); label: Tr.t("Отклонить"); onClicked: ph.kc.act(pr.modelData, "reject") }
                }
            }
        }
    }

    // ---- несколько телефонов — выбор ----
    Flow {
        visible: ph.kc.devices.length > 1
        Layout.fillWidth: true
        spacing: 6
        Repeater {
            model: ph.kc.devices
            delegate: Rectangle {
                id: chip
                required property var modelData
                readonly property bool cur: ph.d && ph.d.id === chip.modelData.id && ph.d.backend === chip.modelData.backend
                implicitWidth: chipText.implicitWidth + 24
                implicitHeight: 30
                radius: 15
                color: chip.cur ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.22) : chm.containsMouse ? Theme.surfaceHigher : Theme.surfaceHigh
                Text {
                    id: chipText
                    anchors.centerIn: parent
                    text: (chip.modelData.reachable ? "● " : "○ ") + chip.modelData.name
                    color: chip.cur ? Theme.accent : Theme.text; font.pixelSize: Theme.fs(12)
                }
                MouseArea { id: chm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: ph.kc.selectedId = chip.modelData.id }
            }
        }
    }

    EmptyState {
        visible: (!Prefs.kdeconnect && !Prefs.glidelink) || ph.kc.devices.length === 0
        Layout.fillWidth: true
        glyph: 0xF011C
        text: !Prefs.kdeconnect && !Prefs.glidelink ? Tr.t("Телефон выключен в настройках") : Tr.t("Нет сопряжённых телефонов")
        hint: !Prefs.kdeconnect && !Prefs.glidelink ? Tr.t("Включить: настройки → «Поведение»")
            : Tr.t("Запусти glide-link daemon и сопряги телефон в приложении Glide Link — или KDE Connect")
    }

    // ---- карточка устройства ----
    Rectangle {
        Behavior on border.color { ColorAnimation { duration: Prefs.ms(140) } }
        visible: !!ph.d
        Layout.fillWidth: true
        implicitHeight: 64
        radius: Theme.radiusLg
        color: Theme.surface
        border.color: ph.on ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.5) : Theme.outline
        Text {
            Behavior on color { ColorAnimation { duration: Prefs.ms(140) } }
            x: 16; anchors.verticalCenter: parent.verticalCenter
            text: ph.kc.glyph(ph.d)
            color: ph.on ? Theme.accent : Theme.textMuted
            font.family: Prefs.iconFont; font.pixelSize: Theme.fs(28)
        }
        Column {
            x: 54; anchors.verticalCenter: parent.verticalCenter
            width: parent.width - 54 - 110
            Text {
                width: parent.width
                text: ph.d ? ph.d.name : ""
                color: Theme.text; font.pixelSize: Theme.fs(14); font.bold: true
                elide: Text.ElideRight
            }
            Text {
                Behavior on color { ColorAnimation { duration: Prefs.ms(140) } }
                width: parent.width
                elide: Text.ElideRight
                text: !ph.d ? "" : (!ph.on ? Tr.t("не на связи") : Tr.t("на связи") + (ph.d.network ? " · " + ph.d.network : ""))
                      + " · " + (ph.link ? "Glide Link" : "KDE Connect")
                color: ph.on ? Theme.textSecondary : Theme.textMuted; font.pixelSize: Theme.fs(12)
            }
        }
        Row {   // заряд
            visible: ph.on && ph.d.battery !== undefined
            anchors.right: parent.right; anchors.rightMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            spacing: 5
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: ph.kc.batteryGlyph(ph.d)
                color: ph.d && ph.d.charging ? Theme.success : ph.d && ph.d.battery <= 15 ? Theme.error : Theme.textVariant
                font.family: Prefs.iconFont; font.pixelSize: Theme.fs(18)
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: ph.d && ph.d.battery !== undefined ? ph.d.battery + "%" : ""
                color: Theme.text; font.pixelSize: Theme.fs(13)
            }
        }
    }

    // ---- действия ----
    GridLayout {
        visible: ph.on
        Layout.fillWidth: true
        columns: 2
        columnSpacing: 8; rowSpacing: 8
        Act { visible: ph.kc.has(ph.d, "findmyphone"); glyph: ph.nf(0xF009E); label: Tr.t("Найти телефон"); onClicked: ph.act("ring") }
        Act { visible: ph.kc.has(ph.d, "ping"); glyph: ph.nf(0xF0E1E); label: Tr.t("Пинг"); onClicked: ph.act("ping") }
        Act { visible: ph.kc.has(ph.d, "clipboard"); glyph: ph.nf(0xF014C); label: Tr.t("Отправить буфер"); onClicked: ph.act("clipboard") }
        Act { visible: ph.kc.has(ph.d, "share"); glyph: ph.nf(0xF0552); label: Tr.t("Файлы на телефон"); onClicked: ph.act("files") }
        // файлы телефона и SMS: у Glide Link — свои окна здесь, у KDE Connect — его приложения (SFTP, kdeconnect-sms)
        Act { visible: ph.kc.has(ph.d, ph.link ? "files" : "sftp"); glyph: ph.nf(0xF024B); label: Tr.t("Файлы телефона"); onClicked: ph.link ? ph.view = "files" : ph.act("browse") }
        Act { visible: ph.kc.has(ph.d, "sms"); glyph: ph.nf(0xF0361); label: Tr.t("Сообщения"); onClicked: ph.link ? ph.view = "sms" : ph.act("sms") }
        // только Glide Link: экран и звук
        Act {
            visible: ph.link && ph.kc.has(ph.d, "screen")
            active: ph.kc.streaming(ph.d, "screen_in")
            glyph: ph.nf(0xF0379); label: active ? Tr.t("Закрыть экран") : Tr.t("Экран телефона")
            onClicked: ph.stream("screen_in", "screen", "screen-stop")
        }
        Act {
            visible: ph.link && ph.kc.has(ph.d, "audio")
            active: ph.kc.streaming(ph.d, "audio_in")
            glyph: ph.nf(0xF057E); label: active ? Tr.t("Выключить звук") : Tr.t("Звук телефона")
            onClicked: ph.stream("audio_in", "audio", "audio-stop")
        }
        Act {
            visible: ph.link && ph.kc.has(ph.d, "screen")
            active: ph.kc.streaming(ph.d, "screen_out")
            glyph: ph.nf(0xF1A44); label: active ? Tr.t("Остановить показ") : Tr.t("Экран ПК на телефон")
            onClicked: ph.stream("screen_out", "screen-share", "screen-stop")
        }
        Act {
            visible: ph.link && ph.kc.has(ph.d, "audio")
            active: ph.kc.streaming(ph.d, "audio_out")
            glyph: ph.nf(0xF04C3); label: active ? Tr.t("Остановить звук") : Tr.t("Звук ПК на телефон")
            onClicked: ph.stream("audio_out", "audio-share", "audio-stop")
        }
    }

    // ---- текст или ссылка на телефон ----
    Rectangle {
        visible: ph.on && ph.kc.has(ph.d, "share")
        Layout.fillWidth: true
        implicitHeight: 38; radius: Theme.radiusMd
        color: Theme.surface
        border.width: shareIn.activeFocus ? 2 : 1
        border.color: shareIn.activeFocus ? Theme.accent : shareHover.hovered ? Theme.outlineHover : Theme.outline
        Behavior on border.color { ColorAnimation { duration: Prefs.ms(150) } }
        HoverHandler { id: shareHover; cursorShape: Qt.IBeamCursor }
        TextInput {
            id: shareIn
            anchors.left: parent.left; anchors.right: parent.right
            anchors.leftMargin: 14; anchors.rightMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            color: Theme.text; font.pixelSize: Theme.fs(13)
            clip: true
            onAccepted: if (text.trim()) { ph.act("text", text); text = ""; if (ph.api) ph.api.flash("󰄜", Tr.t("Отправлено на телефон")) }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: !shareIn.text
                text: Tr.t("Текст или ссылка на телефон → Enter")
                color: Theme.textMuted; font.pixelSize: Theme.fs(12)
            }
        }
    }

    // ---- Glide Link: найденные в сети, по IP, забыть ----
    Text {
        visible: Prefs.glidelink && ph.kc.linkFound.length > 0
        text: Tr.t("Найдены в сети")
        color: Theme.textSecondary; font.pixelSize: Theme.fs(12); font.bold: true
        Layout.topMargin: 4
    }
    Repeater {
        model: Prefs.glidelink ? ph.kc.linkFound : []
        delegate: RowLayout {
            id: fr
            required property var modelData
            Layout.fillWidth: true
            spacing: 8
            Text {
                Layout.fillWidth: true
                text: fr.modelData.name + "  ·  " + fr.modelData.address
                color: Theme.text; font.pixelSize: Theme.fs(13)
                elide: Text.ElideRight
            }
            Act { Layout.fillWidth: false; Layout.preferredWidth: 130; glyph: ph.nf(0xF0337); label: Tr.t("Сопрячь"); onClicked: { ph.kc.act(fr.modelData, "pair"); if (ph.api) ph.api.flash("󰄜", Tr.t("Сверь код на телефоне")) } }
        }
    }
    RowLayout {
        visible: Prefs.glidelink && ph.kc.linkUp
        Layout.fillWidth: true
        spacing: 8
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 38; radius: Theme.radiusMd
            color: Theme.surface
            border.width: ipIn.activeFocus ? 2 : 1
            border.color: ipIn.activeFocus ? Theme.accent : Theme.outline
            TextInput {
                id: ipIn
                anchors.left: parent.left; anchors.right: parent.right
                anchors.leftMargin: 14; anchors.rightMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                color: Theme.text; font.pixelSize: Theme.fs(13)
                clip: true
                onAccepted: if (text.trim()) { ph.kc.connectTo(text.trim()); text = ""; if (ph.api) ph.api.flash("󰄜", Tr.t("Подключаюсь — сверь код на телефоне")) }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: !ipIn.text
                    text: Tr.t("Подключить по IP телефона → Enter")
                    color: Theme.textMuted; font.pixelSize: Theme.fs(12)
                }
            }
        }
        Act {
            visible: ph.link
            Layout.fillWidth: false; Layout.preferredWidth: 110
            glyph: ph.nf(0xF0A7A); label: Tr.t("Забыть")
            onClicked: if (ph.api) ph.api.confirm(Tr.t("Забыть «") + ph.d.name + Tr.t("»? Для нового подключения придётся снова сверить код."),
                                                 { yes: Tr.t("Забыть") }, ok => { if (ok) ph.kc.act(ph.d, "unpair") })
        }
    }
    // ---- команды ПК для кнопок на телефоне (Glide Link) ----
    ColumnLayout {
        visible: ph.link && ph.kc.has(ph.d, "runcommand")
        Layout.fillWidth: true
        Layout.topMargin: 4
        spacing: 6
        Text {
            text: Tr.t("Команды для телефона")
            color: Theme.textSecondary; font.pixelSize: Theme.fs(12); font.bold: true
        }
        Text {
            Layout.fillWidth: true
            text: Tr.t("Появятся кнопками в Glide Link на телефоне и запустятся здесь. Сам телефон команды не видит — только названия.")
            color: Theme.textMuted; font.pixelSize: Theme.fs(11)
            wrapMode: Text.Wrap
        }
        Repeater {
            model: ph.commands
            delegate: Rectangle {
                id: cr
                required property var modelData
                Layout.fillWidth: true
                implicitHeight: 40
                radius: Theme.radiusMd
                color: Theme.surfaceHigh
                Column {
                    x: 12; anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 54
                    Text { width: parent.width; text: cr.modelData.name; color: Theme.text; font.pixelSize: Theme.fs(12); elide: Text.ElideRight }
                    Text { width: parent.width; text: cr.modelData.command; color: Theme.textMuted; font.pixelSize: Theme.fs(10); font.family: "JetBrainsMono Nerd Font"; elide: Text.ElideRight }
                }
                Text {
                    anchors.right: parent.right; anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    text: ph.nf(0xF0A7A)
                    color: crm.containsMouse ? Theme.error : Theme.textMuted
                    font.family: Prefs.iconFont; font.pixelSize: Theme.fs(15)
                    MouseArea { id: crm; anchors.fill: parent; anchors.margins: -6; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: ph.removeCommand(cr.modelData) }
                }
            }
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            Field { id: cmdName; Layout.preferredWidth: 120; hint: Tr.t("Название") }
            Field { id: cmdLine; Layout.fillWidth: true; hint: Tr.t("Команда, напр. loginctl lock-session"); onAccepted: cmdAdd.clicked() }
            Act {
                id: cmdAdd
                Layout.fillWidth: false; Layout.preferredWidth: 44
                glyph: ph.nf(0xF0415); label: ""
                onClicked: { ph.addCommand(cmdName.text, cmdLine.text); cmdName.text = ""; cmdLine.text = "" }
            }
        }
    }
    }   // mainView

    component Field: Rectangle {
        id: f
        property string hint
        property alias text: input.text
        signal accepted()
        implicitHeight: 38
        radius: Theme.radiusMd
        color: Theme.surface
        border.width: input.activeFocus ? 2 : 1
        border.color: input.activeFocus ? Theme.accent : Theme.outline
        Behavior on border.color { ColorAnimation { duration: Prefs.ms(150) } }
        TextInput {
            id: input
            anchors.left: parent.left; anchors.right: parent.right
            anchors.leftMargin: 12; anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            color: Theme.text; font.pixelSize: Theme.fs(12)
            clip: true
            onAccepted: f.accepted()
            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: !input.text
                text: f.hint
                color: Theme.textMuted; font.pixelSize: Theme.fs(11)
                elide: Text.ElideRight; width: parent.width
            }
        }
    }

    component Act: Rectangle {
        id: a
        property string glyph
        property string label
        property bool active: false   // идёт трансляция — подсветка акцентом
        signal clicked()
        Layout.fillWidth: true
        Layout.preferredWidth: 1
        implicitHeight: 44
        radius: Theme.radiusMd
        color: a.active ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, am.containsMouse ? 0.32 : 0.22)
             : am.pressed ? Theme.surfacePressed : am.containsMouse ? Theme.surfaceHigher : Theme.surfaceHigh
        opacity: enabled ? 1 : Theme.disabledOpacity
        scale: am.pressed ? 0.96 : 1
        Behavior on color { ColorAnimation { duration: Prefs.ms(120) } }
        Behavior on scale { NumberAnimation { duration: Prefs.ms(140); easing.type: Easing.OutBack } }
        Row {
            x: 12; anchors.verticalCenter: parent.verticalCenter
            width: parent.width - 24
            spacing: 10
            Text { anchors.verticalCenter: parent.verticalCenter; text: a.glyph; color: Theme.accent; font.family: Prefs.iconFont; font.pixelSize: Theme.fs(17) }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 30
                text: a.label; color: Theme.text; font.pixelSize: Theme.fs(12)
                elide: Text.ElideRight
            }
        }
        MouseArea { id: am; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: a.clicked() }
    }
}
