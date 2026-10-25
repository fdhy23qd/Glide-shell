import QtQuick
import QtQuick.Layouts
import Quickshell

// Вкладка «Автоматизация» в настройках: список правил и редактор (движок — Automation.qml, правила — Prefs.automations).
// Грузится Loader-ом из SettingsView и берёт оттуда общие элементы (SettingsView.ChipChoice и т. п.).
ColumnLayout {
    id: av
    property var panel
    readonly property var eng: panel ? panel.automation : null
    readonly property var rules: eng ? eng.rules : []
    property string openId: ""             // какое правило раскрыто
    spacing: 14

    function nf(c) { return String.fromCodePoint(c) }
    // modelData из Repeater — копия, вложенные массивы в ней не настоящие (Array.isArray = false): в обычный массив
    function arr(x) { return x && typeof x !== "string" && typeof x.length === "number" ? Array.prototype.slice.call(x) : [] }
    function rule(id) { return rules.find(r => r.id === id) }
    function setWhen(r, patch) { eng.update(r.id, { when: Object.assign({}, r.when || {}, patch) }) }
    function setOnly(r, patch) { eng.update(r.id, { only: Object.assign({}, r.only || {}, patch) }) }
    function setAct(r, i, patch) { var t = av.arr(r.then).slice(); t[i] = Object.assign({}, t[i], patch); eng.update(r.id, { then: t }) }
    function delAct(r, i) { var t = av.arr(r.then).slice(); t.splice(i, 1); eng.update(r.id, { then: t }) }
    function moveAct(r, i, d) {
        var t = av.arr(r.then).slice(), j = i + d
        if (j < 0 || j >= t.length) return
        var x = t[i]; t[i] = t[j]; t[j] = x
        eng.update(r.id, { then: t })
    }
    function addAct(r, type) {
        var a = { type: type }
        if (type === "dnd" || type === "awake" || type === "night") a.value = "on"
        if (type === "mute") a.value = "off"
        if (type === "volume") a.percent = 50
        if (type === "wait") a.seconds = 5
        eng.update(r.id, { then: av.arr(r.then).concat([a]) })
    }
    // одной строкой — для свёрнутого правила
    function summary(r) {
        var t = eng.triggerOf(r.when ? r.when.type : "")
        var w = t ? t.label : "?"
        if (r.when && r.when.app) w += " " + r.when.app
        if (r.when && r.when.type === "time") w += " " + (r.when.at || "—")
        if (r.when && r.when.type === "batteryBelow") w += " " + (r.when.percent || "?") + "%"
        var n = av.arr(r.then).length
        return w + "  →  " + (n ? av.arr(r.then).map(a => { var x = eng.actionOf(a.type); return x ? x.label : a.type }).join(", ") : Tr.t("ничего"))
    }
    readonly property var openApps: {
        var a = []
        for (var k in Niri.windows) { var id = Niri.windows[k].app_id; if (id && a.indexOf(id) < 0) a.push(id) }
        return a.sort()
    }
    readonly property var dayNames: [Tr.t("Пн"), Tr.t("Вт"), Tr.t("Ср"), Tr.t("Чт"), Tr.t("Пт"), Tr.t("Сб"), Tr.t("Вс")]
    readonly property var switchOpts: [{ label: Tr.t("Включён"), value: "on" }, { label: Tr.t("Выключен"), value: "off" },
                                       { label: Tr.t("Переключить"), value: "toggle" }]

    SettingsView.Header { text: Tr.t("АВТОМАТИЗАЦИЯ") }
    Text {
        Layout.fillWidth: true
        text: Tr.t("Правила «когда → если → сделать»: например, открыт Discord — включить «не беспокоить», телефон подключился — запустить Steam. Поля с текстом сохраняются по Enter.")
        color: Theme.textSecondary; font.pixelSize: Theme.fs(12); wrapMode: Text.WordWrap
    }
    Rectangle {   // пауза после зацикливания
        visible: !!av.eng && av.eng.paused
        Layout.fillWidth: true
        implicitHeight: pauseRow.implicitHeight + 20
        radius: Theme.radiusMd
        color: Qt.rgba(Theme.error.r, Theme.error.g, Theme.error.b, 0.12)
        border.color: Theme.error
        RowLayout {
            id: pauseRow
            anchors.fill: parent; anchors.margins: 10
            Text {
                Layout.fillWidth: true
                text: Tr.t("Автоматизация на паузе: правила сработали слишком часто (одно — больше 6 раз за минуту или все — больше 20 за 10 секунд). Похоже, они запускают сами себя по кругу.")
                color: Theme.text; font.pixelSize: Theme.fs(12); wrapMode: Text.WordWrap
            }
            SettingsView.ActionBtn { glyph: av.nf(0xF040A); text: Tr.t("Продолжить"); onClicked: av.eng.resume() }
        }
    }

    Repeater {
        model: av.rules
        delegate: Rectangle {
            id: card
            required property var modelData
            required property int index
            readonly property var r: modelData
            readonly property bool open: av.openId === r.id
            Layout.fillWidth: true
            implicitHeight: cardCol.implicitHeight + 20
            radius: Theme.radiusMd
            color: Theme.surface
            border.color: open ? Prefs.accent : Theme.outline
            opacity: r.on || open ? 1 : 0.7
            Behavior on border.color { ColorAnimation { duration: Prefs.ms(150) } }

            ColumnLayout {
                id: cardCol
                x: 10; y: 10
                width: card.width - 20
                spacing: 10

                RowLayout {   // заголовок правила
                    Layout.fillWidth: true
                    spacing: 8
                    SettingsView.Switch { checked: card.r.on; onToggled: av.eng.update(card.r.id, { on: !card.r.on }) }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        TextInput {
                            id: nameIn
                            Layout.fillWidth: true
                            text: card.r.name || ""
                            color: Theme.text; font.pixelSize: Theme.fs(13); font.bold: true
                            clip: true
                            onEditingFinished: if (text.trim() && text.trim() !== card.r.name) av.eng.update(card.r.id, { name: text.trim() })
                            HoverHandler { cursorShape: Qt.IBeamCursor }
                        }
                        Text {
                            Layout.fillWidth: true
                            text: av.summary(card.r)
                            color: Theme.textSecondary; font.pixelSize: Theme.fs(11)
                            elide: Text.ElideRight
                        }
                    }
                    SettingsView.SmallBtn { glyph: av.nf(0xF040A); onClicked: av.eng.test(card.r.id) }   // выполнить сейчас
                    SettingsView.SmallBtn { glyph: card.open ? "▴" : "▾"; onClicked: av.openId = card.open ? "" : card.r.id }
                    SettingsView.SmallBtn { glyph: "✕"; onClicked: { if (card.open) av.openId = ""; av.eng.remove(card.r.id) } }
                }

                // ---- редактор ----
                ColumnLayout {
                    visible: card.open
                    Layout.fillWidth: true
                    spacing: 10

                    SettingsView.ChipChoice {
                        label: Tr.t("Когда")
                        options: av.eng ? av.eng.triggers.map(t => ({ label: t.label, value: t.type })) : []
                        current: card.r.when ? card.r.when.type : ""
                        onPicked: (v) => av.eng.update(card.r.id, { when: { type: v } })
                    }
                    readonly property var tparams: { var t = av.eng ? av.eng.triggerOf(card.r.when ? card.r.when.type : "") : null; return t ? t.params : [] }
                    AppField {
                        apps: av.openApps
                        visible: parent.tparams.indexOf("app") >= 0
                        value: card.r.when && card.r.when.app ? card.r.when.app : ""
                        onPicked: (v) => av.setWhen(card.r, { app: v })
                    }
                    SettingsView.TextRow {
                        visible: parent.tparams.indexOf("at") >= 0
                        label: Tr.t("Время (ЧЧ:ММ)")
                        placeholder: "08:30"
                        value: card.r.when && card.r.when.at ? card.r.when.at : ""
                        onSubmitted: (v) => { if (av.eng.minutes(v) >= 0) av.setWhen(card.r, { at: v }) }
                    }
                    ColumnLayout {   // дни недели (ничего не выбрано — каждый день)
                        id: daysBox
                        visible: parent.tparams.indexOf("days") >= 0
                        Layout.fillWidth: true
                        spacing: 6
                        readonly property var days: card.r.when ? av.arr(card.r.when.days) : []
                        Text { text: Tr.t("Дни (ничего не выбрано — каждый день)"); color: Theme.text }
                        Flow {
                            Layout.fillWidth: true
                            spacing: 6
                            Repeater {
                                model: 7
                                delegate: Chip {
                                    required property int index
                                    readonly property int day: index + 1
                                    label: av.dayNames[index]
                                    on: daysBox.days.indexOf(day) >= 0
                                    onClicked: {
                                        var d = daysBox.days.filter(x => x !== day)
                                        if (!on) d.push(day)
                                        av.setWhen(card.r, { days: d.sort() })
                                    }
                                }
                            }
                        }
                    }
                    SettingsView.TextRow {
                        visible: parent.tparams.indexOf("percent") >= 0
                        label: Tr.t("Процент заряда")
                        placeholder: "20"
                        value: card.r.when && card.r.when.percent ? String(card.r.when.percent) : ""
                        onSubmitted: (v) => { var n = parseInt(v); if (n > 0 && n < 100) av.setWhen(card.r, { percent: n }) }
                    }

                    // ---- если ----
                    SettingsView.ChipChoice {
                        label: Tr.t("Только если")
                        options: [{ label: Tr.t("Всегда"), value: "" }, { label: Tr.t("От сети"), value: "ac" }, { label: Tr.t("От батареи"), value: "battery" }]
                        current: card.r.only && card.r.only.power ? card.r.only.power : ""
                        onPicked: (v) => av.setOnly(card.r, { power: v })
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10
                        SettingsView.TextRow {
                            label: Tr.t("С (ЧЧ:ММ)")
                            placeholder: Tr.t("в любое время")
                            value: card.r.only && card.r.only.from ? card.r.only.from : ""
                            onSubmitted: (v) => { if (v === "" || av.eng.minutes(v) >= 0) av.setOnly(card.r, { from: v }) }
                        }
                        SettingsView.TextRow {
                            label: Tr.t("До (ЧЧ:ММ)")
                            placeholder: Tr.t("в любое время")
                            value: card.r.only && card.r.only.to ? card.r.only.to : ""
                            onSubmitted: (v) => { if (v === "" || av.eng.minutes(v) >= 0) av.setOnly(card.r, { to: v }) }
                        }
                    }

                    // ---- сделать ----
                    Text { text: Tr.t("Сделать (по порядку)"); color: Theme.text }
                    Repeater {
                        model: av.arr(card.r.then)
                        delegate: Rectangle {
                            id: step
                            required property var modelData
                            required property int index
                            readonly property var a: modelData
                            readonly property var spec: av.eng.actionOf(a.type)
                            readonly property var params: spec ? spec.params : []
                            Layout.fillWidth: true
                            implicitHeight: stepCol.implicitHeight + 16
                            radius: Theme.radiusSm
                            color: Theme.surfaceHigh
                            ColumnLayout {
                                id: stepCol
                                x: 8; y: 8
                                width: step.width - 16
                                spacing: 6
                                RowLayout {
                                    Layout.fillWidth: true
                                    Text {
                                        Layout.fillWidth: true
                                        text: (step.index + 1) + ". " + (step.spec ? step.spec.label : step.a.type)
                                        color: Theme.text; font.pixelSize: Theme.fs(12); font.bold: true
                                    }
                                    SettingsView.SmallBtn { glyph: "↑"; active: step.index > 0; onClicked: av.moveAct(card.r, step.index, -1) }
                                    SettingsView.SmallBtn { glyph: "↓"; active: step.index < av.arr(card.r.then).length - 1; onClicked: av.moveAct(card.r, step.index, 1) }
                                    SettingsView.SmallBtn { glyph: "✕"; onClicked: av.delAct(card.r, step.index) }
                                }
                                Flow {
                                    visible: step.params.indexOf("switch") >= 0
                                    Layout.fillWidth: true
                                    spacing: 6
                                    Repeater {
                                        model: av.switchOpts
                                        delegate: Chip {
                                            required property var modelData
                                            label: modelData.label
                                            on: step.a.value === modelData.value
                                            onClicked: av.setAct(card.r, step.index, { value: modelData.value })
                                        }
                                    }
                                }
                                AppField {
                        apps: av.openApps
                                    visible: step.params.indexOf("app") >= 0
                                    value: step.a.app || ""
                                    onPicked: (v) => av.setAct(card.r, step.index, { app: v })
                                }
                                SettingsView.TextRow {
                                    visible: step.params.indexOf("percent") >= 0
                                    label: Tr.t("Громкость, %")
                                    value: step.a.percent !== undefined ? String(step.a.percent) : ""
                                    onSubmitted: (v) => { var n = parseInt(v); if (n >= 0 && n <= 100) av.setAct(card.r, step.index, { percent: n }) }
                                }
                                SettingsView.TextRow {
                                    visible: step.params.indexOf("text") >= 0
                                    label: Tr.t("Текст")
                                    value: step.a.text || ""
                                    onSubmitted: (v) => av.setAct(card.r, step.index, { text: v })
                                }
                                SettingsView.TextRow {
                                    visible: step.params.indexOf("cmd") >= 0
                                    label: step.a.type === "niri" ? Tr.t("Действие niri (как после «niri msg action»)") : Tr.t("Команда (sh -c)")
                                    placeholder: step.a.type === "niri" ? "focus-workspace 2" : "notify-send hi"
                                    value: step.a.cmd || ""
                                    onSubmitted: (v) => av.setAct(card.r, step.index, { cmd: v })
                                }
                                SettingsView.TextRow {
                                    visible: step.params.indexOf("seconds") >= 0
                                    label: Tr.t("Секунд")
                                    value: step.a.seconds !== undefined ? String(step.a.seconds) : ""
                                    onSubmitted: (v) => { var n = parseInt(v); if (n >= 0 && n <= 3600) av.setAct(card.r, step.index, { seconds: n }) }
                                }
                            }
                        }
                    }
                    Text { text: Tr.t("Добавить действие:"); color: Theme.textSecondary; font.pixelSize: Theme.fs(12) }
                    Flow {
                        Layout.fillWidth: true
                        spacing: 6
                        Repeater {
                            model: av.eng ? av.eng.actions : []
                            delegate: Chip {
                                required property var modelData
                                label: "+ " + modelData.label
                                onClicked: av.addAct(card.r, modelData.type)
                            }
                        }
                    }
                }
            }
        }
    }
    SettingsView.ActionBtn {
        glyph: av.nf(0xF0415)
        text: Tr.t("Новое правило")
        onClicked: av.openId = av.eng.add()
    }

    // ---- журнал ----
    SettingsView.Header { visible: !!av.eng && av.eng.log.length > 0; text: Tr.t("ПОСЛЕДНИЕ СРАБАТЫВАНИЯ") }
    Repeater {
        model: av.eng ? av.eng.log.slice(0, 8) : []
        delegate: Text {
            required property var modelData
            Layout.fillWidth: true
            text: Qt.formatTime(new Date(modelData.time), "HH:mm:ss") + "  " + (modelData.ok ? "✓ " : "✗ ") + modelData.name
                  + (modelData.detail ? " — " + modelData.detail : "")
            color: modelData.ok ? Theme.textSecondary : Theme.error
            font.pixelSize: Theme.fs(11)
            elide: Text.ElideRight
        }
    }

    // ---- маленькие элементы ----
    // чип выбора (несколько вариантов, «вкл» — акцентом)
    component Chip: Rectangle {
        id: chip
        property string label
        property bool on: false
        signal clicked()
        width: chipText.implicitWidth + 24; height: 28; radius: height / 2
        color: on ? (chipMa.pressed ? Theme.accentPressed : chipMa.containsMouse ? Theme.accentLight : Prefs.accent)
                  : (chipMa.pressed ? Theme.surfacePressed : chipMa.containsMouse ? Theme.surfaceHigher : Theme.surface)
        border.color: on ? "transparent" : Theme.outline
        scale: chipMa.pressed ? 0.95 : 1
        Behavior on color { ColorAnimation { duration: Prefs.ms(140) } }
        Behavior on scale { NumberAnimation { duration: Prefs.ms(140); easing.type: Easing.OutBack } }
        Text { id: chipText; anchors.centerIn: parent; text: chip.label; color: chip.on ? Theme.accentText : Theme.textSecondary; font.pixelSize: Theme.fs(12) }
        MouseArea { id: chipMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: chip.clicked() }
    }
    // приложение: id вручную (Enter) или одним щелчком из открытых сейчас
    component AppField: ColumnLayout {
        id: af
        property string value
        property var apps: []              // открытые сейчас (inline-компонент не видит id файла)
        signal picked(string v)
        Layout.fillWidth: true
        spacing: 6
        SettingsView.TextRow {
            label: Tr.t("Приложение (id, например org.telegram.desktop)")
            value: af.value
            onSubmitted: (v) => af.picked(v)
        }
        Flow {
            Layout.fillWidth: true
            spacing: 6
            Repeater {
                model: af.apps
                delegate: Chip {
                    required property string modelData
                    label: modelData
                    on: modelData.toLowerCase() === af.value.toLowerCase()
                    onClicked: af.picked(modelData)
                }
            }
        }
    }
}
