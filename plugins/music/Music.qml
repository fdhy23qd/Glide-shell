import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Mpris
import qs

// Плеер на встроенном в Quickshell MPRIS. Клик по названию плеера переключает между несколькими.
ColumnLayout {
    id: m
    property var api
    readonly property color accent: api && api.accent ? api.accent : Theme.accent   // акцент из настроек панели
    readonly property color accentText: api && api.accentText ? api.accentText : "#ffffff"   // текст на акценте
    property var chosen: null
    readonly property var player: pick()
    spacing: 10

    function pick() {
        var vs = Mpris.players.values
        if (chosen) for (var j = 0; j < vs.length; j++) if (vs[j] === chosen) return chosen
        for (var i = 0; i < vs.length; i++) if (vs[i].isPlaying) return vs[i]
        return vs.length ? vs[0] : null
    }
    function cycle() {
        var vs = Mpris.players.values
        if (vs.length < 2) return
        var cur = 0
        for (var i = 0; i < vs.length; i++) if (vs[i] === player) cur = i
        chosen = vs[(cur + 1) % vs.length]
    }
    function fmt(s) {
        s = Math.max(0, Math.floor(s))
        return Math.floor(s / 60) + ":" + ("0" + (s % 60)).slice(-2)
    }

    Timer {   // position в Mpris сам не обновляется
        running: !!m.player && m.player.isPlaying && !!m.api && m.api.shown   // только пока панель открыта
        interval: 500
        repeat: true
        onTriggered: m.player.positionChanged()
    }

    EmptyState {
        visible: !m.player
        Layout.fillWidth: true
        glyph: 0xF075A
        text: Tr.t("Сейчас ничего не играет")
        hint: Tr.t("Запусти музыку в плеере или браузере — она появится здесь")
    }

    RowLayout {
        visible: !!m.player
        Layout.fillWidth: true
        spacing: 12
        Rectangle {
            Layout.preferredWidth: 64
            Layout.preferredHeight: 64
            radius: Theme.r(8)
            color: Theme.surface
            clip: true
            Image {   // обложка проявляется после загрузки
                anchors.fill: parent
                source: m.player ? m.player.trackArtUrl : ""
                sourceSize.width: 128; sourceSize.height: 128   // не декодировать обложку в полном размере
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                opacity: status === Image.Ready ? 1 : 0
                scale: status === Image.Ready ? 1 : 1.08
                Behavior on opacity { NumberAnimation { duration: Prefs.ms(300) } }
                Behavior on scale { NumberAnimation { duration: Prefs.ms(400); easing.type: Easing.OutCubic } }
            }
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2
            Text {
                Layout.fillWidth: true
                text: m.player ? (m.player.trackTitle || "—") : ""
                color: Theme.text; font.pixelSize: Theme.fs(14); font.bold: true
                elide: Text.ElideRight
            }
            Text {
                Layout.fillWidth: true
                text: m.player ? m.player.trackArtist : ""
                color: Theme.textSecondary
                elide: Text.ElideRight
            }
            Text {
                text: m.player ? m.player.identity : ""
                color: idMa.pressed ? Theme.text : idMa.containsMouse ? Theme.textVariant : Theme.textMuted; font.pixelSize: Theme.fs(11)
                Behavior on color { ColorAnimation { duration: Prefs.ms(120) } }
                MouseArea { id: idMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: m.cycle() }
            }
        }
    }

    Rectangle {
        visible: !!m.player && m.player.lengthSupported
        Layout.fillWidth: true
        implicitHeight: 8
        radius: Theme.r(4)
        color: seekMa.containsMouse ? Theme.surfaceHigher : Theme.surfaceHigh   // перемотка: под курсором ярче
        Behavior on color { ColorAnimation { duration: Prefs.ms(120) } }
        Rectangle {
            height: parent.height
            radius: Theme.r(4)
            color: m.accent
            width: m.player && m.player.length > 0
                   ? parent.width * Math.min(1, m.player.position / m.player.length) : 0
            Behavior on width { NumberAnimation { duration: Prefs.ms(500); easing.type: Easing.Linear } }
        }
        MouseArea {
            id: seekMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            enabled: !!m.player && m.player.canSeek
            onClicked: (e) => { m.player.position = (e.x / width) * m.player.length }
        }
    }
    Text {
        visible: !!m.player && m.player.lengthSupported
        text: m.player ? fmt(m.player.position) + " / " + fmt(m.player.length) : ""
        color: Theme.textMuted; font.pixelSize: Theme.fs(11)
    }

    component Btn: Rectangle {
        id: b
        property string glyph
        property bool active: true
        signal clicked()
        Layout.fillWidth: true
        implicitHeight: 38
        radius: Theme.r(8)
        opacity: active ? 1 : Theme.disabledOpacity
        color: !active ? Theme.surfaceHigh : bma.pressed ? Theme.surfacePressed : bma.containsMouse ? Theme.surfaceHigher : Theme.surfaceHigh
        scale: bma.pressed && active ? 0.92 : 1
        Behavior on color { ColorAnimation { duration: Prefs.ms(120) } }
        Behavior on scale { NumberAnimation { duration: Prefs.ms(140); easing.type: Easing.OutBack } }
        Behavior on opacity { NumberAnimation { duration: Prefs.ms(150) } }
        Text { anchors.centerIn: parent; text: b.glyph; color: Theme.text; font.pixelSize: Theme.fs(16) }
        MouseArea { id: bma; anchors.fill: parent; hoverEnabled: true; cursorShape: b.active ? Qt.PointingHandCursor : Qt.ArrowCursor; onClicked: if (b.active) b.clicked() }
    }

    RowLayout {
        visible: !!m.player
        Layout.fillWidth: true
        spacing: 8
        Btn { glyph: "⏮"; active: !!m.player && m.player.canGoPrevious; onClicked: m.player.previous() }
        Btn { glyph: m.player && m.player.isPlaying ? "⏸" : "▶"; active: !!m.player && m.player.canTogglePlaying; onClicked: m.player.togglePlaying() }
        Btn { glyph: "⏭"; active: !!m.player && m.player.canGoNext; onClicked: m.player.next() }
    }
}
