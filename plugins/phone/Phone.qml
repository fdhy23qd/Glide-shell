import QtQuick
import QtQuick.Layouts
import Quickshell
import qs

// Телефон через KDE Connect (ядро — KdeConnect.qml): карточка устройства и действия. Кнопки — только те,
// что поддерживает телефон и пока он на связи; уведомления телефона приходят в общий центр уведомлений сами.
ColumnLayout {
    id: ph
    property var api
    readonly property var kc: KdeConnect
    readonly property var d: kc.phone
    readonly property bool on: !!d && d.reachable
    spacing: 10

    function nf(code) { return String.fromCodePoint(code) }
    function act(action, text) { kc.act(ph.d, action, text); if (ph.api && action !== "text") ph.api.close() }

    EmptyState {
        visible: !Prefs.kdeconnect || ph.kc.devices.length === 0
        Layout.fillWidth: true
        glyph: 0xF011C
        text: !Prefs.kdeconnect ? Tr.t("Интеграция с KDE Connect выключена") : Tr.t("Нет сопряжённых телефонов")
        hint: !Prefs.kdeconnect ? Tr.t("Включить: настройки → «Поведение»")
            : Tr.t("Установи KDE Connect на телефон и сопряги его (kdeconnect-app)")
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
                text: !ph.d ? "" : !ph.on ? Tr.t("не на связи") : Tr.t("на связи") + (ph.d.network ? " · " + ph.d.network : "")
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
        Act { visible: ph.kc.has(ph.d, "sftp"); glyph: ph.nf(0xF024B); label: Tr.t("Файлы телефона"); onClicked: ph.act("browse") }
        Act { visible: ph.kc.has(ph.d, "sms"); glyph: ph.nf(0xF0361); label: Tr.t("Сообщения"); onClicked: ph.act("sms") }
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

    component Act: Rectangle {
        id: a
        property string glyph
        property string label
        signal clicked()
        Layout.fillWidth: true
        Layout.preferredWidth: 1
        implicitHeight: 44
        radius: Theme.radiusMd
        color: am.pressed ? Theme.surfacePressed : am.containsMouse ? Theme.surfaceHigher : Theme.surfaceHigh
        opacity: enabled ? 1 : Theme.disabledOpacity
        scale: am.pressed ? 0.96 : 1
        Behavior on color { ColorAnimation { duration: Prefs.ms(120) } }
        Behavior on scale { NumberAnimation { duration: Prefs.ms(140); easing.type: Easing.OutBack } }
        Row {
            x: 12; anchors.verticalCenter: parent.verticalCenter
            spacing: 10
            Text { anchors.verticalCenter: parent.verticalCenter; text: a.glyph; color: Theme.accent; font.family: Prefs.iconFont; font.pixelSize: Theme.fs(17) }
            Text { anchors.verticalCenter: parent.verticalCenter; text: a.label; color: Theme.text; font.pixelSize: Theme.fs(12) }
        }
        MouseArea { id: am; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: a.clicked() }
    }
}
