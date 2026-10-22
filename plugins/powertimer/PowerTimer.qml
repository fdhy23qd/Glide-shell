import QtQuick
import QtQuick.Layouts
import Quickshell
import qs

// Выключение или сон по таймеру (tools/glide-powertimer.sh — таймер systemd). Идёт таймер — остаток и «Отменить»,
// иначе — что сделать и через сколько.
ColumnLayout {
    id: pt
    property var api
    property string pluginDir
    readonly property var st: api ? api.powerTimer : null           // {action, end} или null
    readonly property real now: api ? api.now : Date.now()
    readonly property int leftMin: st ? Math.max(0, Math.ceil((st.end * 1000 - now) / 60000)) : 0
    property string action: "poweroff"
    spacing: 10
    function tool(args) { api.run(["sh", Quickshell.shellDir + "/tools/glide-powertimer.sh"].concat(args), "") }
    function fmt(m) { return m >= 60 ? Math.floor(m / 60) + Tr.t(" ч ") + (m % 60 ? m % 60 + Tr.t(" мин") : "") : m + Tr.t(" мин") }

    // идёт таймер
    Rectangle {
        visible: !!pt.st
        Layout.fillWidth: true
        implicitHeight: 64; radius: Theme.r(18)
        color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.14)
        border.color: Theme.accent
        RowLayout {
            anchors.fill: parent; anchors.leftMargin: 16; anchors.rightMargin: 10
            Text { text: String.fromCodePoint(pt.st && pt.st.action === "suspend" ? 0xF04B2 : 0xF0425); color: Theme.accent
                   font.family: Prefs.iconFont; font.pixelSize: Theme.fs(22) }
            Column {
                Layout.fillWidth: true
                Text { text: (pt.st && pt.st.action === "suspend" ? Tr.t("Сон через ") : Tr.t("Выключение через ")) + pt.fmt(pt.leftMin)
                       color: Theme.text; font.pixelSize: Theme.fs(14); font.bold: true }
                Text { text: pt.st ? Tr.t("в ") + Qt.formatTime(new Date(pt.st.end * 1000), "HH:mm") : ""
                       color: Theme.textSecondary; font.pixelSize: Theme.fs(12) }
            }
            Btn { text: Tr.t("Отменить"); onClicked: pt.tool(["cancel"]) }
        }
    }

    // поставить
    Row {
        visible: !pt.st
        spacing: 6
        Repeater {
            model: [{ v: "poweroff", l: Tr.t("Выключить"), g: 0xF0425 }, { v: "suspend", l: Tr.t("Сон"), g: 0xF04B2 }]
            delegate: Btn {
                required property var modelData
                glyph: modelData.g; text: modelData.l
                on: pt.action === modelData.v
                onClicked: pt.action = modelData.v
            }
        }
    }
    Flow {
        visible: !pt.st
        Layout.fillWidth: true
        spacing: 6
        Repeater {
            model: [15, 30, 45, 60, 90, 120]
            delegate: Btn {
                required property int modelData
                text: Tr.t("через ") + pt.fmt(modelData)
                onClicked: pt.tool(["set", String(modelData), pt.action])
            }
        }
    }

    component Btn: Rectangle {
        id: b
        property string text
        property int glyph: 0
        property bool on: false
        signal clicked()
        implicitHeight: 32; implicitWidth: br.implicitWidth + 24; radius: Theme.r(16)
        color: on ? (bm.containsMouse ? Theme.accentLight : Theme.accent)
                  : bm.pressed ? Theme.surfacePressed : bm.containsMouse ? Theme.surfaceHigher : Theme.surfaceHigh
        scale: bm.pressed ? 0.94 : 1
        Behavior on color { ColorAnimation { duration: Prefs.ms(120) } }
        Behavior on scale { NumberAnimation { duration: Prefs.ms(140); easing.type: Easing.OutBack } }
        Row {
            id: br; anchors.centerIn: parent; spacing: 6
            Text { visible: b.glyph > 0; text: b.glyph > 0 ? String.fromCodePoint(b.glyph) : ""; anchors.verticalCenter: parent.verticalCenter
                   color: b.on ? Theme.accentText : Theme.textVariant; font.family: Prefs.iconFont; font.pixelSize: Theme.fs(14) }
            Text { text: b.text; anchors.verticalCenter: parent.verticalCenter
                   color: b.on ? Theme.accentText : Theme.text; font.pixelSize: Theme.fs(12) }
        }
        MouseArea { id: bm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: b.clicked() }
    }
}
