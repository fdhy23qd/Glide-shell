import QtQuick
import QtQuick.Layouts
import qs

// Съёмные диски (ядро — Drives.qml): каждое устройство карточкой — имя, размер, где подключено; кнопки
// «Открыть», «Подключить», «Отключить», «Извлечь». Вставленное подключается само (настройка в «Поведении»).
ColumnLayout {
    id: dv
    property var api
    spacing: 8
    function nf(code) { return String.fromCodePoint(code) }

    EmptyState {
        visible: !Prefs.drives || Drives.list.length === 0
        Layout.fillWidth: true
        compact: true
        glyph: 0xF0553
        text: !Prefs.drives ? Tr.t("Слежение за дисками выключено") : Tr.t("Съёмных дисков нет")
        hint: !Prefs.drives ? Tr.t("Включить: настройки → «Поведение» → «Съёмные диски»") : Tr.t("Вставь флешку или карту памяти — она появится здесь")
    }
    Repeater {
        model: Prefs.drives ? Drives.list : []
        delegate: Rectangle {
            id: card
            required property var modelData
            readonly property var d: modelData
            readonly property string busy: Drives.busy[d.id] || ""
            Layout.fillWidth: true
            implicitHeight: col.implicitHeight + 20
            radius: Theme.r(16)
            color: Theme.surface
            border.color: d.mounted ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.5) : Theme.outline
            Behavior on border.color { ColorAnimation { duration: Prefs.ms(160) } }
            ColumnLayout {
                id: col
                x: 12; y: 10; width: parent.width - 24
                spacing: 8
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10
                    Text {
                        text: dv.nf(card.d.image ? 0xF02CA : card.d.encrypted ? 0xF033E : 0xF0553)
                        color: card.d.mounted ? Theme.accent : Theme.textVariant
                        font.family: Prefs.iconFont; font.pixelSize: Theme.fs(22)
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1
                        Text {
                            Layout.fillWidth: true
                            text: Drives.name(card.d)
                            color: Theme.text; font.pixelSize: Theme.fs(13); font.bold: true
                            elide: Text.ElideRight; textFormat: Text.PlainText
                        }
                        Text {
                            Layout.fillWidth: true
                            text: [Drives.info(card.d), card.d.image ? Tr.t("образ") : card.d.driveName,
                                   card.d.mounted ? card.d.mountPoint : card.d.encrypted ? Tr.t("зашифрован") : Tr.t("не подключён")]
                                  .filter(x => x).join("  ·  ")
                            color: Theme.textSecondary; font.pixelSize: Theme.fs(11)
                            elide: Text.ElideMiddle; textFormat: Text.PlainText
                        }
                    }
                }
                Flow {
                    Layout.fillWidth: true
                    spacing: 6
                    visible: !card.d.encrypted
                    Btn { visible: card.d.mounted; glyph: 0xF0770; label: Tr.t("Открыть"); primary: true; onClicked: { Drives.open(card.d); if (dv.api) dv.api.close() } }
                    Btn { visible: !card.d.mounted; glyph: 0xF0553; label: Tr.t("Подключить"); primary: true; onClicked: Drives.mount(card.d, false) }
                    Btn { visible: card.d.mounted; glyph: 0xF0156; label: Tr.t("Отключить"); onClicked: Drives.unmount(card.d) }
                    Btn { glyph: 0xF01EA; label: Tr.t("Извлечь"); onClicked: Drives.eject(card.d) }
                    Text {
                        visible: card.busy !== ""
                        height: 30; verticalAlignment: Text.AlignVCenter
                        text: card.busy === "mount" ? Tr.t("подключаю…") : card.busy === "eject" ? Tr.t("извлекаю…") : Tr.t("отключаю…")
                        color: Theme.textMuted; font.pixelSize: Theme.fs(11)
                    }
                }
            }
            enabled: busy === ""
            opacity: enabled ? 1 : Theme.disabledOpacity
        }
    }

    component Btn: Rectangle {
        id: b
        property int glyph
        property string label
        property bool primary: false
        signal clicked()
        implicitWidth: br.implicitWidth + 24; implicitHeight: 30; radius: Theme.r(15)
        color: b.primary ? (bm.pressed ? Theme.accentPressed : bm.containsMouse ? Theme.accentLight : Theme.accent)
                         : (bm.pressed ? Theme.surfacePressed : bm.containsMouse ? Theme.surfaceHigher : Theme.surfaceHigh)
        scale: bm.pressed ? 0.94 : 1
        Behavior on color { ColorAnimation { duration: Prefs.ms(120) } }
        Behavior on scale { NumberAnimation { duration: Prefs.ms(140); easing.type: Easing.OutBack } }
        Row {
            id: br; anchors.centerIn: parent; spacing: 6
            Text { anchors.verticalCenter: parent.verticalCenter; text: String.fromCodePoint(b.glyph)
                   color: b.primary ? Theme.accentText : Theme.textVariant; font.family: Prefs.iconFont; font.pixelSize: Theme.fs(13) }
            Text { anchors.verticalCenter: parent.verticalCenter; text: b.label
                   color: b.primary ? Theme.accentText : Theme.text; font.pixelSize: Theme.fs(12) }
        }
        MouseArea { id: bm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: b.clicked() }
    }
}
