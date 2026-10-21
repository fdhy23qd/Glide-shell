import QtQuick
import QtQuick.Layouts
import Quickshell
import qs

// Запись экрана (ядро — api.recorder, Recorder.qml): выбрать звук и что записывать; во время записи —
// таймер и «Остановить». Сама запись идёт и с закрытой панелью — её показывает строка в острове.
ColumnLayout {
    id: rv
    property var api
    readonly property var rec: api ? api.recorder : null
    readonly property color accent: api && api.accent ? api.accent : Theme.accent
    readonly property color accentText: api && api.accentText ? api.accentText : "#ffffff"
    readonly property string iconFont: api && api.iconFont ? api.iconFont : "JetBrainsMono Nerd Font"
    readonly property bool shown: api ? api.shown : false
    property string audio: ""   // "" | system | mic
    spacing: 8

    function nf(code) { return String.fromCodePoint(code) }
    onShownChanged: if (shown && rec) rec.check()

    Text {   // нечем записывать
        visible: !!rv.rec && !rv.rec.hasRecorder
        Layout.fillWidth: true
        text: Tr.t("Нужен wf-recorder (и slurp — для записи области):\nsudo pacman -S wf-recorder slurp")
        color: Theme.textSecondary; font.pixelSize: Theme.fs(12)
        wrapMode: Text.WordWrap
    }

    // ---- идёт запись ----
    RowLayout {
        visible: !!rv.rec && rv.rec.recording
        Layout.fillWidth: true
        spacing: 10
        Rectangle { width: 10; height: 10; radius: Theme.r(5); color: Theme.error }
        Text {
            Layout.fillWidth: true
            text: rv.rec ? Tr.t("Запись · ") + rv.rec.fmt(rv.rec.elapsed) : ""
            color: Theme.text; font.pixelSize: Theme.fs(13); font.bold: true
        }
        Btn { label: Tr.t("Остановить"); danger: true; onClicked: { rv.rec.stop(); rv.api.close() } }
    }

    // ---- выбор ----
    ColumnLayout {
        visible: !!rv.rec && rv.rec.hasRecorder && !rv.rec.recording
        Layout.fillWidth: true
        spacing: 8
        Row {   // звук
            spacing: 6
            Repeater {
                model: [{ v: "", l: Tr.t("Без звука"), g: 0xF075F }, { v: "system", l: Tr.t("Звук системы"), g: 0xF057E }, { v: "mic", l: Tr.t("Микрофон"), g: 0xF036C }]
                delegate: Rectangle {
                    Behavior on border.color { ColorAnimation { duration: Prefs.ms(140) } }
                    required property var modelData
                    readonly property bool on: rv.audio === modelData.v
                    width: chipRow.implicitWidth + 22; height: 30; radius: Theme.r(15)
                    color: on ? Qt.rgba(rv.accent.r, rv.accent.g, rv.accent.b, cm.containsMouse ? 0.32 : 0.22)
                              : (cm.pressed ? Theme.surfaceHigher : cm.containsMouse ? Theme.surfaceHigh : Theme.surface)
                    border.color: on ? rv.accent : "transparent"
                    scale: cm.pressed ? 0.95 : 1
                    Behavior on color { ColorAnimation { duration: Prefs.ms(120) } }
                    Behavior on scale { NumberAnimation { duration: Prefs.ms(140); easing.type: Easing.OutBack } }
                    Row {
                        id: chipRow
                        anchors.centerIn: parent
                        spacing: 6
                        Text { anchors.verticalCenter: parent.verticalCenter; text: rv.nf(modelData.g); color: Theme.textVariant; font.family: rv.iconFont; font.pixelSize: Theme.fs(13) }
                        Text { anchors.verticalCenter: parent.verticalCenter; text: modelData.l; color: Theme.text; font.pixelSize: Theme.fs(12) }
                    }
                    MouseArea { id: cm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: rv.audio = modelData.v }
                }
            }
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            Btn {
                Layout.fillWidth: true
                label: Tr.t("Весь экран"); primary: true; accent: rv.accent; accentText: rv.accentText
                onClicked: { rv.api.close(); rv.rec.start(rv.audio, false) }
            }
            Btn {
                Layout.fillWidth: true
                visible: rv.rec && rv.rec.hasSlurp
                label: Tr.t("Область")
                onClicked: { rv.api.close(); rv.rec.start(rv.audio, true) }
            }
        }
        Text {
            Layout.fillWidth: true
            text: Tr.t("Остановить — клик по строке «Запись» в острове. Видео — в ~/Видео/Записи экрана")
            color: Theme.textMuted; font.pixelSize: Theme.fs(11)
            wrapMode: Text.WordWrap
        }
    }

    component Btn: Rectangle {
        id: b
        property string label
        property bool primary: false
        property bool danger: false
        property color accent: Theme.accent
        property color accentText: "#ffffff"
        signal clicked()
        implicitWidth: bt.implicitWidth + 28; implicitHeight: 34; radius: Theme.r(17)
        color: danger ? (bm.pressed ? Theme.errorContainer : bm.containsMouse ? Theme.errorHover : Theme.errorContainer)
             : primary ? (bm.pressed ? Qt.darker(accent, 1.15) : bm.containsMouse ? Qt.lighter(accent, 1.12) : accent)
             : (bm.pressed ? Theme.surfacePressed : bm.containsMouse ? Theme.surfaceHigher : Theme.surfaceHigh)
        opacity: enabled ? 1 : Theme.disabledOpacity
        scale: bm.pressed ? 0.95 : 1
        Behavior on scale { NumberAnimation { duration: Prefs.ms(140); easing.type: Easing.OutBack } }
        Text { id: bt; anchors.centerIn: parent; text: b.label; color: b.danger ? Theme.errorText : b.primary ? b.accentText : Theme.text; font.pixelSize: Theme.fs(13) }
        MouseArea { id: bm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: b.clicked() }
    }
}
