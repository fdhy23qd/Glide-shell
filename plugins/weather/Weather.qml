import QtQuick
import QtQuick.Layouts
import qs

// Погода (данные — api.weather, ядро обновляет их раз в 30 минут): сейчас, по часам, на 5 дней.
// Клик по городу — поменять его (пусто — определять самой: по IP или часовому поясу).
ColumnLayout {
    id: wv
    property var api
    readonly property var wx: api ? api.weather : null
    readonly property var d: wx && wx.ok ? wx.data : null
    readonly property color accent: api && api.accent ? api.accent : Theme.accent
    readonly property string iconFont: api && api.iconFont ? api.iconFont : Prefs.iconFont
    readonly property bool shown: api ? api.shown : false
    property bool editing: false
    spacing: 8

    function nf(code) { return String.fromCodePoint(code) }
    onShownChanged: { if (!shown) editing = false; else if (wx) wx.refresh() }
    Component.onCompleted: if (wx) wx.refresh()

    function dayName(iso, i) {
        if (i === 0) return Tr.t("Сегодня")
        if (i === 1) return Tr.t("Завтра")
        var p = iso.split("-")
        var s = Tr.locale.toString(new Date(+p[0], +p[1] - 1, +p[2]), "dddd")
        return s.charAt(0).toUpperCase() + s.slice(1)
    }

    Text {   // нет данных или ошибка
        visible: !wv.d
        Layout.fillWidth: true
        text: !wv.wx || !wv.wx.data ? Tr.t("Загружаю погоду…") : Tr.t("Погода недоступна: ") + (wv.wx.data.error || Tr.t("нет данных"))
        color: Theme.textSecondary; font.pixelSize: Theme.fs(12)
        wrapMode: Text.WordWrap
    }

    // ---- сейчас ----
    RowLayout {
        visible: !!wv.d
        Layout.fillWidth: true
        spacing: 12
        Text {
            text: wv.d ? wv.wx.icon(wv.d.now.code, wv.d.now.day) : ""
            color: wv.accent; font.family: wv.iconFont; font.pixelSize: Theme.fs(44)
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            Text {
                text: wv.d ? wv.wx.temp(wv.d.now.temp) : ""
                color: Theme.text; font.pixelSize: Theme.fs(30); font.weight: Font.Light
            }
            Text {
                Layout.fillWidth: true
                text: wv.d ? wv.wx.describe(wv.d.now.code) : ""
                color: Theme.textVariant; font.pixelSize: Theme.fs(12)
                elide: Text.ElideRight
            }
            Text {
                Layout.fillWidth: true
                text: wv.d ? Tr.t("ощущается ") + wv.wx.temp(wv.d.now.feels) : ""
                color: Theme.textMuted; font.pixelSize: Theme.fs(11)
            }
        }
        ColumnLayout {
            spacing: 3
            Detail { glyph: wv.nf(0xF059D); text: wv.d ? wv.d.now.wind.toFixed(1) + Tr.t(" м/с") : ""; iconFont: wv.iconFont }
            Detail { glyph: wv.nf(0xF058E); text: wv.d ? wv.d.now.humidity + "%" : ""; iconFont: wv.iconFont }
            Detail { glyph: wv.nf(0xF059C); text: wv.d ? wv.d.sunrise + " – " + wv.d.sunset : ""; iconFont: wv.iconFont }
        }
    }

    // ---- по часам ----
    Row {   // колонки поровну на всю ширину
        id: hoursRow
        visible: !!wv.d && wv.d.hours.length > 0
        Layout.fillWidth: true
        Repeater {
            model: wv.d ? wv.d.hours : []
            delegate: Column {
                required property var modelData
                width: hoursRow.width / Math.max(1, wv.d.hours.length)
                spacing: 2
                Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.time; color: Theme.textMuted; font.pixelSize: Theme.fs(11) }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: wv.wx.icon(modelData.code, modelData.day)
                    color: Theme.textVariant; font.family: wv.iconFont; font.pixelSize: Theme.fs(18)
                }
                Text { anchors.horizontalCenter: parent.horizontalCenter; text: wv.wx.temp(modelData.temp); color: Theme.text; font.pixelSize: Theme.fs(12) }
            }
        }
    }

    // ---- на 5 дней ----
    Rectangle {
        visible: !!wv.d
        Layout.fillWidth: true
        implicitHeight: daysCol.implicitHeight + 12
        radius: Theme.r(16)
        color: Theme.surface
        border.color: Theme.outline
        Column {
            id: daysCol
            x: 14; y: 6
            width: parent.width - 28
            Repeater {
                model: wv.d ? wv.d.days : []
                delegate: Item {
                    required property var modelData
                    required property int index
                    width: daysCol.width; height: 28
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: wv.dayName(modelData.date, index)
                        color: index === 0 ? Theme.text : Theme.textVariant; font.pixelSize: Theme.fs(12)
                        font.bold: index === 0
                    }
                    Text {
                        x: parent.width * 0.42
                        anchors.verticalCenter: parent.verticalCenter
                        text: wv.wx.icon(modelData.code, true)
                        color: Theme.textVariant; font.family: wv.iconFont; font.pixelSize: Theme.fs(16)
                    }
                    Text {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: wv.wx.temp(modelData.min) + "  " + wv.wx.temp(modelData.max)
                        color: Theme.text; font.pixelSize: Theme.fs(12)
                        font.features: ({ "tnum": 1 })
                    }
                }
            }
        }
    }

    // ---- город ----
    RowLayout {
        Layout.fillWidth: true
        spacing: 6
        Text {
            visible: !wv.editing
            text: wv.nf(0xF034E)
            color: Theme.textMuted; font.family: wv.iconFont; font.pixelSize: Theme.fs(13)
        }
        Text {   // клик — сменить город
            visible: !wv.editing
            Layout.fillWidth: true
            text: (wv.d && wv.d.place ? wv.d.place : Tr.t("Город не определён"))
                + (wv.wx && wv.wx.city ? "" : Tr.t(" · определён сам")) + (wv.d && wv.d.stale ? Tr.t(" · нет сети, старые данные") : "")
                + Tr.t("  ·  сменить")
            color: cityMouse.pressed ? Theme.text : cityMouse.containsMouse ? Theme.textVariant : Theme.textMuted; font.pixelSize: Theme.fs(11)
            Behavior on color { ColorAnimation { duration: Prefs.ms(120) } }
            elide: Text.ElideRight
            MouseArea {
                id: cityMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: { wv.editing = true; cityInput.text = wv.wx ? wv.wx.city : ""; cityInput.forceActiveFocus() }
            }
        }
        Rectangle {
            visible: wv.editing
            Layout.fillWidth: true
            implicitHeight: 32; radius: Theme.r(16)
            color: Theme.surface
            border.width: cityInput.activeFocus ? 2 : 1
            border.color: cityInput.activeFocus ? wv.accent : cityHover.hovered ? Theme.outlineHover : Theme.outline
            Behavior on border.color { ColorAnimation { duration: Prefs.ms(150) } }
            HoverHandler { id: cityHover; cursorShape: Qt.IBeamCursor }
            TextInput {
                id: cityInput
                anchors.left: parent.left; anchors.right: parent.right
                anchors.leftMargin: 14; anchors.rightMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                color: Theme.text; font.pixelSize: Theme.fs(12)
                clip: true
                Keys.onReturnPressed: { if (wv.api) wv.api.setPref("weatherCity", text.trim()); wv.editing = false }
                Keys.onEnterPressed: { if (wv.api) wv.api.setPref("weatherCity", text.trim()); wv.editing = false }
                Keys.onEscapePressed: (e) => { wv.editing = false; e.accepted = true }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: !cityInput.text
                    text: Tr.t("Город → Enter (пусто — определять самой)")
                    color: Theme.textMuted; font.pixelSize: Theme.fs(12)
                }
            }
        }
    }

    component Detail: Row {
        id: dt
        property string glyph
        property string text
        property string iconFont
        spacing: 5
        Text { anchors.verticalCenter: parent.verticalCenter; text: dt.glyph; color: Theme.textMuted; font.family: dt.iconFont; font.pixelSize: Theme.fs(13) }
        Text { anchors.verticalCenter: parent.verticalCenter; text: dt.text; color: Theme.textVariant; font.pixelSize: Theme.fs(11) }
    }
}
