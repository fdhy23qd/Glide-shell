import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.Pipewire
import qs

// Микшер (PipeWire): ползунок на каждое приложение, которое сейчас выводит звук (колесо — шаг 5%,
// клик по значку — без звука), и выбор микрофона, если их несколько.
ColumnLayout {
    id: mx
    property var api
    readonly property color accent: api && api.accent ? api.accent : Theme.accent
    readonly property color accentText: api && api.accentText ? api.accentText : "#ffffff"
    readonly property string iconFont: api && api.iconFont ? api.iconFont : "JetBrainsMono Nerd Font"
    spacing: 8

    // потоки воспроизведения приложений («Stream/Output/Audio») и микрофоны («Audio/Source»)
    readonly property var streams: Pipewire.nodes.values.filter(n => n.type === PwNodeType.AudioOutStream && n.audio)
    readonly property var sources: Pipewire.nodes.values.filter(n => n.type === PwNodeType.AudioSource && n.audio)
    readonly property var source: Pipewire.defaultAudioSource
    PwObjectTracker { objects: mx.streams.concat(mx.sources) }

    function appName(n) {
        var p = n.properties || {}
        return p["application.name"] || n.description || n.nickname || n.name || Tr.t("Приложение")
    }
    function appIcon(n) {
        var p = n.properties || {}
        var name = p["application.icon-name"] || p["application.process.binary"] || ""
        return name ? Quickshell.iconPath(name, true) : ""
    }

    Text {
        text: Tr.t("Приложения")
        color: Theme.textSecondary; font.pixelSize: Theme.fs(11); font.bold: true
    }
    Text {
        visible: mx.streams.length === 0
        text: Tr.t("Сейчас никто не играет звук")
        color: Theme.textMuted; font.pixelSize: Theme.fs(12)
    }
    Repeater {
        model: mx.streams
        delegate: RowLayout {
            id: st
            required property var modelData
            readonly property var a: modelData.audio
            Layout.fillWidth: true
            spacing: 10
            Item {   // значок приложения; клик — без звука
                implicitWidth: 28; implicitHeight: 28
                scale: muteMa.pressed ? 0.85 : muteMa.containsMouse ? 1.1 : 1
                Behavior on scale { NumberAnimation { duration: Prefs.ms(140); easing.type: Easing.OutBack } }
                Rectangle {   // подложка под курсором
                    anchors.fill: parent; anchors.margins: -3
                    radius: Theme.r(8)
                    color: muteMa.containsMouse ? Theme.surfaceHigh : "transparent"
                    Behavior on color { ColorAnimation { duration: Prefs.ms(120) } }
                }
                IconImage {
                    id: icon
                    Behavior on opacity { NumberAnimation { duration: Prefs.ms(140) } }
                    anchors.fill: parent
                    source: mx.appIcon(st.modelData)
                    visible: source != "" && status === Image.Ready
                    opacity: st.a && st.a.muted ? 0.35 : 1
                }
                Text {
                    anchors.centerIn: parent
                    visible: !icon.visible
                    text: String.fromCodePoint(st.a && st.a.muted ? 0xF0581 : 0xF057E)
                    color: Theme.textVariant; font.family: mx.iconFont; font.pixelSize: Theme.fs(18)
                }
                MouseArea { id: muteMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: if (st.a) st.a.muted = !st.a.muted }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 3
                RowLayout {
                    Layout.fillWidth: true
                    Text {
                        Layout.fillWidth: true
                        text: mx.appName(st.modelData)
                        color: Theme.text; font.pixelSize: Theme.fs(12)
                        elide: Text.ElideRight
                    }
                    Text {
                        text: st.a ? (st.a.muted ? Tr.t("без звука") : Math.round(st.a.volume * 100) + "%") : ""
                        color: Theme.textSecondary; font.pixelSize: Theme.fs(11)
                        font.features: ({ "tnum": 1 })
                    }
                }
                Rectangle {   // полоса громкости
                    id: track
                    Behavior on color { ColorAnimation { duration: Prefs.ms(140) } }
                    Layout.fillWidth: true
                    // наведение — полоса толще, перетаскивание — заливка светлее
                    implicitHeight: drag.containsMouse || drag.pressed ? 8 : 6; radius: Theme.r(implicitHeight / 2)
                    color: drag.containsMouse || drag.pressed ? Theme.surfaceHigher : Theme.surfaceHigh
                    Behavior on implicitHeight { NumberAnimation { duration: Prefs.ms(120) } }
                    Rectangle {
                        Behavior on color { ColorAnimation { duration: Prefs.ms(140) } }
                        height: parent.height; radius: parent.radius
                        width: st.a ? parent.width * Math.min(1, st.a.volume) : 0
                        color: st.a && st.a.muted ? Theme.divider : drag.pressed ? Qt.lighter(mx.accent, 1.15) : mx.accent
                        Behavior on width { enabled: !drag.sliding; NumberAnimation { duration: Prefs.ms(220); easing.type: Easing.OutCubic } }
                    }
                    MouseArea {
                        id: drag
                        anchors.fill: parent
                        anchors.margins: -8   // попадать легче, чем в 6 пикселей
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        function at(x) {
                            if (!st.a) return
                            st.a.volume = Math.max(0, Math.min(1, (x - 8) / track.width))
                            if (st.a.muted) st.a.muted = false
                        }
                        // щелчок — заливка плавно доезжает до места; перетаскивание — идёт за курсором без задержки
                        property bool sliding: false
                        property real pressX: 0
                        onPressed: (m) => { sliding = false; pressX = m.x; at(m.x) }
                        onPositionChanged: (m) => { if (!pressed) return; if (Math.abs(m.x - pressX) > 3) sliding = true; if (sliding) at(m.x) }
                        onReleased: sliding = false
                        onCanceled: sliding = false
                        onWheel: (w) => { if (st.a) st.a.volume = Math.max(0, Math.min(1, st.a.volume + (w.angleDelta.y > 0 ? 0.05 : -0.05))) }
                    }
                }
            }
        }
    }

    // ---- микрофон ----
    Text {
        visible: mx.sources.length > 1
        Layout.topMargin: 2
        text: Tr.t("Микрофон")
        color: Theme.textSecondary; font.pixelSize: Theme.fs(11); font.bold: true
    }
    Flow {
        visible: mx.sources.length > 1
        Layout.fillWidth: true
        spacing: 6
        Repeater {
            model: mx.sources
            delegate: Rectangle {
                id: ch
                Behavior on border.color { ColorAnimation { duration: Prefs.ms(140) } }
                required property var modelData
                readonly property bool on: modelData === mx.source
                width: Math.min(chT.implicitWidth + 22, 240); height: 28; radius: Theme.r(14)
                color: on ? Qt.rgba(mx.accent.r, mx.accent.g, mx.accent.b, chm.containsMouse ? 0.32 : 0.22)
                          : (chm.pressed ? Theme.surfaceHigher : chm.containsMouse ? Theme.surfaceHigh : Theme.surface)
                border.color: on ? mx.accent : "transparent"
                scale: chm.pressed ? 0.95 : 1
                Behavior on color { ColorAnimation { duration: Prefs.ms(120) } }
                Behavior on scale { NumberAnimation { duration: Prefs.ms(140); easing.type: Easing.OutBack } }
                Text {
                    id: chT
                    Behavior on color { ColorAnimation { duration: Prefs.ms(140) } }
                    anchors.centerIn: parent
                    width: Math.min(implicitWidth, 218)
                    text: ch.modelData.description || ch.modelData.nickname || ch.modelData.name
                    color: ch.on ? Theme.text : Theme.textVariant; font.pixelSize: Theme.fs(12)
                    elide: Text.ElideRight
                }
                MouseArea { id: chm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Pipewire.preferredDefaultAudioSource = ch.modelData }
            }
        }
    }
}
