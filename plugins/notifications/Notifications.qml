import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import qs

// История уведомлений (данные — api.notifs, сервер в ядре): «не беспокоить», «очистить всё»,
// карточки — клик открывает приложение или выполняет действие по умолчанию, ✕ убирает.
ColumnLayout {
    id: nv
    property var api
    readonly property var ns: api ? api.notifs : null
    readonly property color accent: api && api.accent ? api.accent : Theme.accent
    readonly property color accentText: api && api.accentText ? api.accentText : "#ffffff"
    readonly property string iconFont: api && api.iconFont ? api.iconFont : "JetBrainsMono Nerd Font"
    readonly property bool shown: api ? api.shown : false
    readonly property var items: ns ? ns.list.slice(0, 30) : []
    spacing: 8

    function nf(code) { return String.fromCodePoint(code) }
    onShownChanged: if (shown && ns) ns.markRead()
    Component.onCompleted: if (ns) ns.markRead()

    Text {
        visible: !!nv.ns && !nv.ns.active
        Layout.fillWidth: true
        text: Tr.t("Уведомления пока показывает DMS. Свои включаются в настройках → «Уведомления»; ")
            + Tr.t("у имени на шине один владелец, поэтому DMS при этом должен быть остановлен.")
        color: Theme.textSecondary; font.pixelSize: Theme.fs(12)
        wrapMode: Text.WordWrap
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 6
        Chip {
            accent: nv.accent; accentText: nv.accentText; iconFont: nv.iconFont
            on: !!nv.ns && nv.ns.dnd
            glyph: on ? nv.nf(0xF009B) : nv.nf(0xF009A)
            text: Tr.t("Не беспокоить")
            onClicked: nv.ns.setDnd(!nv.ns.dnd)
        }
        Item { Layout.fillWidth: true }
        Chip {
            accent: nv.accent; accentText: nv.accentText; iconFont: nv.iconFont
            visible: nv.items.length > 0
            glyph: nv.nf(0xF00E2)   // метла
            text: Tr.t("Очистить")
            onClicked: nv.ns.clear()
        }
    }

    EmptyState {
        visible: nv.items.length === 0
        Layout.fillWidth: true
        Layout.bottomMargin: 8
        glyph: nv.ns && nv.ns.dnd ? 0xF009B : 0xF009A
        text: Tr.t("Уведомлений нет")
        hint: nv.ns && nv.ns.dnd ? Tr.t("Включено «Не беспокоить» — новые не всплывают, но попадут сюда") : ""
    }

    Repeater {
        model: nv.items
        delegate: Rectangle {
            id: card
            required property var modelData
            readonly property var e: modelData
            Layout.fillWidth: true
            implicitHeight: body.implicitHeight + 24
            radius: Theme.r(16)
            color: cardMouse.pressed ? Theme.surfaceHigher : cardMouse.containsMouse ? Theme.surfaceHigh : Theme.surface
            border.color: e.urgency === 2 ? Theme.error : Theme.outline   // 2 — срочное
            scale: cardMouse.pressed ? 0.985 : 1
            Behavior on color { ColorAnimation { duration: Prefs.ms(120) } }
            Behavior on scale { NumberAnimation { duration: Prefs.ms(140); easing.type: Easing.OutBack } }

            MouseArea {
                id: cardMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: if (nv.ns.activate(card.e)) nv.api.close()
            }

            ClippingRectangle {
                id: icon
                x: 12; y: 12
                width: 36; height: 36; radius: Theme.r(10)
                color: Theme.surfaceHigh
                Text {
                    anchors.centerIn: parent
                    visible: img.status !== Image.Ready
                    text: nv.nf(0xF009A)
                    color: nv.accent
                    font.family: nv.iconFont; font.pixelSize: Theme.fs(18)
                }
                Image {
                    id: img
                    anchors.fill: parent
                    source: nv.ns.iconFor(card.e)
                    sourceSize.width: 72; sourceSize.height: 72
                    fillMode: Image.PreserveAspectCrop
                }
            }

            ColumnLayout {
                id: body
                x: 58; y: 12
                width: card.width - 58 - 40
                spacing: 2
                Text {
                    Layout.fillWidth: true
                    text: (card.e.appName || Tr.t("Уведомление")) + "  ·  " + nv.ns.ago(card.e.time)
                    color: Theme.textSecondary; font.pixelSize: Theme.fs(11)
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                }
                Text {
                    Layout.fillWidth: true
                    visible: text !== ""
                    text: card.e.summary
                    color: Theme.text; font.pixelSize: Theme.fs(13); font.bold: true
                    textFormat: Text.PlainText
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                }
                Text {
                    Layout.fillWidth: true
                    visible: text !== ""
                    text: card.e.body
                    color: Theme.textVariant; font.pixelSize: Theme.fs(12)
                    textFormat: Text.StyledText
                    wrapMode: Text.Wrap
                    maximumLineCount: 4
                    elide: Text.ElideRight
                    linkColor: nv.accent
                    onLinkActivated: (link) => { if (nv.ns) nv.ns.openLink(link) }
                }
                Flow {   // действия, пока приложение их ждёт
                    Layout.fillWidth: true
                    Layout.topMargin: 4
                    visible: card.e.actions.length > 0
                    spacing: 6
                    Repeater {
                        model: card.e.actions
                        delegate: Chip {
                            required property var modelData
                            accent: nv.accent; accentText: nv.accentText; iconFont: nv.iconFont
                            text: modelData.text
                            onClicked: nv.ns.invoke(card.e, modelData.id)
                        }
                    }
                }
            }

            Rectangle {   // убрать
                Behavior on color { ColorAnimation { duration: Prefs.ms(140) } }
                anchors.right: parent.right; anchors.rightMargin: 8
                y: 8
                width: 26; height: 26; radius: Theme.r(13)
                color: xMouse.pressed ? Theme.surfacePressed : xMouse.containsMouse ? Theme.surfaceHigher : "transparent"
                scale: xMouse.pressed ? 0.85 : 1
                Behavior on scale { NumberAnimation { duration: Prefs.ms(140); easing.type: Easing.OutBack } }
                Text {
                    anchors.centerIn: parent
                    text: nv.nf(0xF0156)
                    color: Theme.textSecondary
                    font.family: nv.iconFont; font.pixelSize: Theme.fs(13)
                }
                MouseArea {
                    id: xMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: nv.ns.remove(card.e)
                }
            }
        }
    }

    // inline-компонент не видит id файла — цвета и шрифт передаются свойствами
    component Chip: Rectangle {
        id: ch
        property string glyph
        property string text
        property bool on: false
        property color accent: Theme.accent
        property color accentText: "#ffffff"
        property string iconFont: "JetBrainsMono Nerd Font"
        signal clicked()
        implicitHeight: 30
        implicitWidth: chRow.implicitWidth + 24
        radius: Theme.r(15)
        color: on ? (chMouse.containsMouse ? Qt.lighter(ch.accent, 1.12) : ch.accent)
                  : chMouse.pressed ? Theme.surfacePressed : chMouse.containsMouse ? Theme.surfaceHigher : Theme.surfaceHigh
        scale: chMouse.pressed ? 0.94 : 1
        Behavior on color { ColorAnimation { duration: Prefs.ms(120) } }
        Behavior on scale { NumberAnimation { duration: Prefs.ms(140); easing.type: Easing.OutBack } }
        Row {
            id: chRow
            anchors.centerIn: parent
            spacing: 6
            Text {
                Behavior on color { ColorAnimation { duration: Prefs.ms(140) } }
                visible: ch.glyph !== ""
                anchors.verticalCenter: parent.verticalCenter
                text: ch.glyph
                color: ch.on ? ch.accentText : Theme.textVariant
                font.family: ch.iconFont; font.pixelSize: Theme.fs(14)
            }
            Text {
                Behavior on color { ColorAnimation { duration: Prefs.ms(140) } }
                anchors.verticalCenter: parent.verticalCenter
                text: ch.text
                color: ch.on ? ch.accentText : Theme.text
                font.pixelSize: Theme.fs(12)
            }
        }
        MouseArea { id: chMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: ch.clicked() }
    }
}
