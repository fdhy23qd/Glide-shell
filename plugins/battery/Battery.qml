import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import qs

// Батарея (battery.py читает /sys): износ — ёмкость сейчас от новой, циклы, мощность, модель. Обновляется раз в 5 с,
// только пока раздел виден.
ColumnLayout {
    id: bv
    property var api
    property string pluginDir: ""
    property var list: []
    property bool loaded: false
    spacing: 8
    Process {
        id: rd
        command: ["python3", "-I", bv.pluginDir + "/battery.py"]
        stdout: StdioCollector { onStreamFinished: { try { bv.list = JSON.parse(text) } catch (e) { bv.list = [] } bv.loaded = true } }
    }
    Timer { running: !!bv.api && bv.api.shown && bv.pluginDir !== ""; interval: 5000; repeat: true; triggeredOnStart: true
            onTriggered: rd.running = true }

    function statusText(s) {
        return s === "Charging" ? Tr.t("заряжается") : s === "Discharging" ? Tr.t("разряжается") : s === "Full" ? Tr.t("заряжена")
             : s === "Not charging" ? Tr.t("не заряжается (держит уровень)") : s ? s : ""
    }
    function healthColor(h) { return h === null ? Theme.textVariant : h >= 80 ? Theme.success : h >= 60 ? Theme.warning : Theme.error }
    function healthWord(h) {
        return h === null ? "" : h >= 80 ? Tr.t("хорошее") : h >= 60 ? Tr.t("заметный износ") : Tr.t("сильный износ — пора менять")
    }

    EmptyState {
        visible: bv.loaded && bv.list.length === 0
        Layout.fillWidth: true
        compact: true
        glyph: 0xF0091
        text: Tr.t("Батареи нет")
        hint: Tr.t("Это компьютер без батареи или драйвер её не показывает")
    }
    Repeater {
        model: bv.list
        delegate: Rectangle {
            id: card
            required property var modelData
            readonly property var b: modelData
            Layout.fillWidth: true
            implicitHeight: col.implicitHeight + 24
            radius: Theme.r(16)
            color: Theme.surface
            border.color: Theme.outline
            ColumnLayout {
                id: col
                x: 14; y: 12; width: parent.width - 28
                spacing: 8
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10
                    Text {
                        text: card.b.health !== null ? Math.round(card.b.health) + "%" : "—"
                        color: bv.healthColor(card.b.health); font.pixelSize: Theme.fs(28); font.weight: Font.DemiBold
                        font.features: ({ "tnum": 1 })
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1
                        Text { text: Tr.t("Здоровье: ") + (bv.healthWord(card.b.health) || Tr.t("драйвер не сообщает")); color: Theme.text
                               font.pixelSize: Theme.fs(13); font.bold: true; Layout.fillWidth: true; elide: Text.ElideRight }
                        Text { text: Tr.t("ёмкость сейчас от той, что была новой"); color: Theme.textSecondary; font.pixelSize: Theme.fs(11)
                               Layout.fillWidth: true; elide: Text.ElideRight }
                    }
                }
                Rectangle {   // полоса: зелёная — сколько осталось от новой
                    visible: card.b.health !== null
                    Layout.fillWidth: true
                    implicitHeight: 6; radius: Theme.r(3)
                    color: Theme.surfaceHigh
                    Rectangle { height: parent.height; radius: parent.radius; width: parent.width * Math.min(1, (card.b.health || 0) / 100)
                                color: bv.healthColor(card.b.health) }
                }
                GridLayout {
                    Layout.fillWidth: true
                    columns: 2; columnSpacing: 12; rowSpacing: 4
                    Repeater {
                        model: [
                            [Tr.t("Заряд"), card.b.percent !== null ? card.b.percent + "% · " + bv.statusText(card.b.status) : ""],
                            [Tr.t("Ёмкость"), card.b.full_wh !== null ? card.b.full_wh + Tr.t(" из ") + card.b.design_wh + Tr.t(" Вт·ч") : ""],
                            [Tr.t("Циклов зарядки"), card.b.cycles !== null ? String(card.b.cycles) : ""],
                            [card.b.status === "Charging" ? Tr.t("Получает") : Tr.t("Тратит"), card.b.watts !== null ? card.b.watts + Tr.t(" Вт") : ""],
                            [Tr.t("Напряжение"), card.b.volts !== null ? card.b.volts + Tr.t(" В") : ""],
                            [Tr.t("Модель"), [card.b.maker, card.b.model, card.b.tech].filter(x => x).join(" · ")]
                        ].filter(r => r[1])
                        delegate: Item {
                            required property var modelData
                            Layout.columnSpan: 2
                            Layout.fillWidth: true
                            implicitHeight: 18
                            Text { text: modelData[0]; color: Theme.textSecondary; font.pixelSize: Theme.fs(12) }
                            Text { anchors.right: parent.right; text: modelData[1]; color: Theme.text; font.pixelSize: Theme.fs(12)
                                   font.features: ({ "tnum": 1 }) }
                        }
                    }
                }
            }
        }
    }
}
