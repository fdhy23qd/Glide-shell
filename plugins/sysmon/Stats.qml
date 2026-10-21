import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import qs

// Метрики системы; опрашиваются раз в 2 секунды, пока панель открыта.
ColumnLayout {
    id: s
    property var api
    readonly property color accent: api && api.accent ? api.accent : Theme.accent   // акцент из настроек панели
    readonly property color accentText: api && api.accentText ? api.accentText : "#ffffff"   // текст на акценте
    property var d: ({})
    spacing: 8

    function speed(b) { return b > 1048576 ? (b / 1048576).toFixed(1) + Tr.t(" МБ/с") : Math.round(b / 1024) + Tr.t(" КБ/с") }

    Process {
        id: p
        command: ["python3", decodeURIComponent(Qt.resolvedUrl("stats.py").toString().replace("file://", ""))]
        stdout: StdioCollector {
            onStreamFinished: { try { s.d = JSON.parse(text) } catch (e) {} }
        }
    }
    Timer {
        interval: 2000
        repeat: true
        running: !!s.api && s.api.shown
        triggeredOnStart: true
        onTriggered: p.running = true
    }

    component Metric: ColumnLayout {
        property color accent: Theme.accent
        property string name
        property string value
        property real fraction: -1
        Layout.fillWidth: true
        spacing: 3
        RowLayout {
            Layout.fillWidth: true
            Text { text: name; color: Theme.textSecondary; font.pixelSize: Theme.fs(12); Layout.fillWidth: true }
            Text { text: value; color: Theme.text; font.pixelSize: Theme.fs(12) }
        }
        Rectangle {
            visible: fraction >= 0
            Layout.fillWidth: true
            implicitHeight: 6
            radius: Theme.r(3)
            color: Theme.surfaceHigh
            Rectangle {
                height: parent.height
                radius: Theme.r(3)
                width: parent.width * Math.max(0, Math.min(1, fraction))
                color: fraction > 0.85 ? Theme.error : accent
                Behavior on width { NumberAnimation { duration: Prefs.ms(600); easing.type: Easing.OutCubic } }
                Behavior on color { ColorAnimation { duration: Prefs.ms(300) } }
            }
        }
    }

    Metric { accent: s.accent; name: "CPU"; value: Math.round(d.cpu || 0) + "%"; fraction: (d.cpu || 0) / 100 }
    Metric { accent: s.accent; name: "RAM"; value: (d.mem_used || 0).toFixed(1) + " / " + (d.mem_total || 0).toFixed(1) + Tr.t(" ГиБ")
             fraction: d.mem_total ? d.mem_used / d.mem_total : 0 }
    Metric { accent: s.accent; name: Tr.t("Диск /"); value: Math.round(d.disk_used || 0) + " / " + Math.round(d.disk_total || 0) + Tr.t(" ГиБ")
             fraction: d.disk_total ? d.disk_used / d.disk_total : 0 }
    Metric { accent: s.accent; visible: !!d.gpu; name: "GPU"; value: d.gpu ? Math.round(d.gpu.percent) + "%  " + Math.round(d.gpu.temp) + "°C" : ""
             fraction: d.gpu ? d.gpu.percent / 100 : -1 }
    Metric { accent: s.accent; visible: d.temp !== null && d.temp !== undefined; name: Tr.t("Температура (макс.)"); value: Math.round(d.temp || 0) + "°C" }
    Metric { accent: s.accent; visible: !!d.battery; name: Tr.t("Батарея"); value: d.battery ? d.battery.percent + "%  " + d.battery.status : ""
             fraction: d.battery ? d.battery.percent / 100 : -1 }
    Metric { accent: s.accent; name: Tr.t("Сеть"); value: "↓ " + speed(d.net_rx || 0) + "   ↑ " + speed(d.net_tx || 0) }
}
