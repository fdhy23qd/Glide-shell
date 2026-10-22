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

    // ---- стопки по приложениям: 2+ уведомления одного приложения — стопка «Telegram · 5», щелчок раскрывает ----
    property var expanded: ({})
    function toggleGroup(k) { var e = Object.assign({}, expanded); e[k] = !e[k]; expanded = e }
    readonly property var groups: {
        var out = [], idx = {}
        for (var e of items) {
            var k = e.appName || e.desktopEntry || "?"
            if (idx[k] === undefined) { idx[k] = out.length; out.push({ key: k, app: e.appName || Tr.t("Уведомление"), entries: [] }) }
            out[idx[k]].entries.push(e)
        }
        return out
    }

    Repeater {
        model: nv.groups
        delegate: ColumnLayout {
            id: grp
            required property var modelData
            readonly property var g: modelData
            readonly property bool many: g.entries.length > 1
            readonly property bool open: !many || !!nv.expanded[g.key]
            Layout.fillWidth: true
            spacing: 6

            // заголовок стопки
            Rectangle {
                visible: true
                Layout.fillWidth: true
                implicitHeight: 30; radius: Theme.r(15)
                color: hdrMa.pressed ? Theme.surfacePressed : hdrMa.containsMouse ? Theme.surfaceHigh : "transparent"
                Behavior on color { ColorAnimation { duration: Prefs.ms(120) } }
                MouseArea { id: hdrMa; anchors.fill: parent; hoverEnabled: grp.many; enabled: grp.many
                            cursorShape: Qt.PointingHandCursor; onClicked: nv.toggleGroup(grp.g.key) }
                Text {
                    x: 10; anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 90
                    text: grp.g.app + (grp.many ? "  ·  " + grp.g.entries.length : "")
                    color: Theme.textSecondary; font.pixelSize: Theme.fs(12); font.bold: true
                    textFormat: Text.PlainText; elide: Text.ElideRight
                }
                Text {   // свернуть / раскрыть
                    id: chev
                    visible: grp.many
                    width: grp.many ? implicitWidth : 0
                    anchors.right: clr.left; anchors.rightMargin: 6; anchors.verticalCenter: parent.verticalCenter
                    text: nv.nf(0xF0140)
                    rotation: grp.open ? 180 : 0
                    Behavior on rotation { NumberAnimation { duration: Prefs.ms(200); easing.type: Easing.OutCubic } }
                    color: Theme.textSecondary
                    font.family: nv.iconFont; font.pixelSize: Theme.fs(16)
                }
                Rectangle {   // без всплывашек от этого приложения (история — остаётся)
                    id: muteBtn
                    readonly property bool muted: Prefs.notifMuted.indexOf(grp.g.app) >= 0
                    anchors.right: chev.left; anchors.rightMargin: 4; anchors.verticalCenter: parent.verticalCenter
                    width: 24; height: 24; radius: Theme.r(12)
                    color: muteMa.pressed ? Theme.surfacePressed : muteMa.containsMouse ? Theme.surfaceHigher : "transparent"
                    scale: muteMa.pressed ? 0.85 : 1
                    Behavior on color { ColorAnimation { duration: Prefs.ms(120) } }
                    Behavior on scale { NumberAnimation { duration: Prefs.ms(140); easing.type: Easing.OutBack } }
                    Text { anchors.centerIn: parent; text: nv.nf(muteBtn.muted ? 0xF009B : 0xF009A)
                           color: muteBtn.muted ? Theme.warning : Theme.textSecondary; font.family: nv.iconFont; font.pixelSize: Theme.fs(13) }
                    MouseArea { id: muteMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: { Prefs.notifMute(grp.g.app, !muteBtn.muted)
                                             if (nv.api) nv.api.flash(nv.nf(muteBtn.muted ? 0xF009A : 0xF009B), muteBtn.muted ? Tr.t("Всплывашки снова: ") + grp.g.app
                                                                       : Tr.t("Без всплывашек: ") + grp.g.app, Theme.textVariant) } }
                }
                Rectangle {   // убрать всю стопку
                    id: clr
                    anchors.right: parent.right; anchors.rightMargin: 4; anchors.verticalCenter: parent.verticalCenter
                    width: 24; height: 24; radius: Theme.r(12)
                    color: clrMa.pressed ? Theme.surfacePressed : clrMa.containsMouse ? Theme.surfaceHigher : "transparent"
                    scale: clrMa.pressed ? 0.85 : 1
                    Behavior on color { ColorAnimation { duration: Prefs.ms(120) } }
                    Behavior on scale { NumberAnimation { duration: Prefs.ms(140); easing.type: Easing.OutBack } }
                    Text { anchors.centerIn: parent; text: nv.nf(0xF0156); color: Theme.textSecondary
                           font.family: nv.iconFont; font.pixelSize: Theme.fs(12) }
                    MouseArea { id: clrMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: { for (var e of grp.g.entries.slice()) nv.ns.remove(e) } }
                }
            }

            // свёрнутая стопка: свежая карточка, под ней — края ещё двух
            Item {
                visible: !grp.open
                Layout.fillWidth: true
                implicitHeight: topCard.implicitHeight + Math.min(2, grp.g.entries.length - 1) * 7
                Repeater {
                    id: under
                    model: Math.min(2, grp.g.entries.length - 1)
                    delegate: Rectangle {
                        required property int index
                        readonly property int depth: Math.min(2, grp.g.entries.length - 1) - index   // 1 — ближняя, 2 — дальняя (ниже и уже)
                        x: depth * 10; width: parent.width - depth * 20
                        y: topCard.implicitHeight - 24 + depth * 7; height: 24
                        radius: Theme.r(16)
                        color: depth === 1 ? Theme.surfaceHigh : Theme.surface
                        border.color: Theme.outline
                        z: -depth
                    }
                }
                NotifCard {
                    id: topCard
                    width: parent.width
                    e: grp.g.entries[0]
                    hub: nv
                    stacked: true
                    onStackClicked: nv.toggleGroup(grp.g.key)
                }
            }

            // раскрытая стопка (или одно уведомление) — все карточки
            Repeater {
                model: grp.open ? grp.g.entries : []
                delegate: NotifCard {
                    required property var modelData
                    Layout.fillWidth: true
                    e: modelData
                    hub: nv
                }
            }
        }
    }

    // карточка уведомления; inline-компонент не видит id файла — всё через hub (корень раздела)
    component NotifCard: Rectangle {
        id: card
        property var e
        property var hub
        property bool stacked: false          // верх свёрнутой стопки: щелчок раскрывает, а не открывает
        signal stackClicked()
        implicitHeight: body.implicitHeight + 24
        radius: Theme.r(16)
        color: cardMouse.pressed ? Theme.surfaceHigher : cardMouse.containsMouse ? Theme.surfaceHigh : Theme.surface
        border.color: e && e.urgency === 2 ? Theme.error : Theme.outline   // 2 — срочное
        scale: cardMouse.pressed ? 0.985 : 1
        Behavior on color { ColorAnimation { duration: Prefs.ms(120) } }
        Behavior on scale { NumberAnimation { duration: Prefs.ms(140); easing.type: Easing.OutBack } }

        MouseArea {
            id: cardMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                if (card.stacked) { card.stackClicked(); return }
                if (card.hub.ns.activate(card.e)) card.hub.api.close()
            }
        }

        ClippingRectangle {
            x: 12; y: 12
            width: 36; height: 36; radius: Theme.r(10)
            color: Theme.surfaceHigh
            Text {
                anchors.centerIn: parent
                visible: img.status !== Image.Ready
                text: String.fromCodePoint(0xF009A)
                color: card.hub.accent
                font.family: card.hub.iconFont; font.pixelSize: Theme.fs(18)
            }
            Image {
                id: img
                anchors.fill: parent
                source: card.e ? card.hub.ns.iconFor(card.e) : ""
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
                text: card.e ? (card.e.appName || Tr.t("Уведомление")) + "  ·  " + card.hub.ns.ago(card.e.time) : ""
                color: Theme.textSecondary; font.pixelSize: Theme.fs(11)
                textFormat: Text.PlainText
                elide: Text.ElideRight
            }
            Text {
                Layout.fillWidth: true
                visible: text !== ""
                text: card.e ? card.e.summary : ""
                color: Theme.text; font.pixelSize: Theme.fs(13); font.bold: true
                textFormat: Text.PlainText
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
            }
            Text {
                Layout.fillWidth: true
                visible: text !== ""
                text: card.e ? card.e.body : ""
                color: Theme.textVariant; font.pixelSize: Theme.fs(12)
                textFormat: Text.StyledText
                wrapMode: Text.Wrap
                maximumLineCount: card.stacked ? 2 : 4
                elide: Text.ElideRight
                linkColor: card.hub.accent
                onLinkActivated: (link) => { if (card.hub.ns) card.hub.ns.openLink(link) }
            }
            Flow {   // действия, пока приложение их ждёт (в свёрнутой стопке — нет)
                Layout.fillWidth: true
                Layout.topMargin: 4
                visible: !card.stacked && !!card.e && card.e.actions.length > 0
                spacing: 6
                Repeater {
                    model: card.e && !card.stacked ? card.e.actions : []
                    delegate: Chip {
                        required property var modelData
                        accent: card.hub.accent; accentText: card.hub.accentText; iconFont: card.hub.iconFont
                        text: modelData.text
                        onClicked: card.hub.ns.invoke(card.e, modelData.id)
                    }
                }
            }
        }

        Rectangle {   // убрать
            visible: !card.stacked
            Behavior on color { ColorAnimation { duration: Prefs.ms(140) } }
            anchors.right: parent.right; anchors.rightMargin: 8
            y: 8
            width: 26; height: 26; radius: Theme.r(13)
            color: xMouse.pressed ? Theme.surfacePressed : xMouse.containsMouse ? Theme.surfaceHigher : "transparent"
            scale: xMouse.pressed ? 0.85 : 1
            Behavior on scale { NumberAnimation { duration: Prefs.ms(140); easing.type: Easing.OutBack } }
            Text {
                anchors.centerIn: parent
                text: String.fromCodePoint(0xF0156)
                color: Theme.textSecondary
                font.family: card.hub.iconFont; font.pixelSize: Theme.fs(13)
            }
            MouseArea {
                id: xMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: card.hub.ns.remove(card.e)
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
