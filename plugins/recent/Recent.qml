import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs
import "kinds.js" as K

// Недавние файлы (recent.py ← recently-used.xbel): шесть последних, щелчок — открыть, «папка» — открыть, где лежит.
ColumnLayout {
    id: rv
    property var api
    property string pluginDir: ""
    property var list: []
    readonly property bool shown: api ? api.shown : false
    spacing: 4
    // команда — явно при запуске: привязка к pluginDir пересчитывается позже обработчика
    function reload() { if (!pluginDir || rd.running) return; rd.command = ["python3", "-I", pluginDir + "/recent.py"]; rd.running = true }
    onShownChanged: if (shown) reload()
    onPluginDirChanged: reload()
    Process {
        id: rd
        stdout: StdioCollector { onStreamFinished: { try { rv.list = JSON.parse(text).slice(0, 6) } catch (e) { rv.list = [] } } }
    }
    function open(p) {
        Quickshell.execDetached(["systemd-run", "--user", "--scope", "--collect", "--quiet", "xdg-open", p])
        if (api) api.close()
    }
    Text {
        visible: rv.list.length === 0
        text: Tr.t("Недавних файлов нет")
        color: Theme.textMuted; font.pixelSize: Theme.fs(12)
    }
    Repeater {
        model: rv.list
        delegate: Rectangle {
            id: row
            required property var modelData
            Layout.fillWidth: true
            implicitHeight: 34; radius: Theme.radiusSm
            color: ma.pressed ? Theme.surfacePressed : ma.containsMouse ? Theme.surfaceHigher : Theme.surfaceHigh
            scale: ma.pressed ? 0.98 : 1
            Behavior on color { ColorAnimation { duration: Prefs.ms(120) } }
            Behavior on scale { NumberAnimation { duration: Prefs.ms(100) } }
            MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: rv.open(row.modelData.path) }
            Text { x: 10; width: 20; height: parent.height; verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignHCenter
                   text: String.fromCodePoint(K.glyph(row.modelData.mime, row.modelData.name)); color: Theme.textVariant
                   font.family: Prefs.iconFont; font.pixelSize: Theme.fs(15) }
            Text { x: 38; width: parent.width - x - info.width - 46; height: parent.height; verticalAlignment: Text.AlignVCenter
                   text: row.modelData.name; color: Theme.text; font.pixelSize: Theme.fs(12); elide: Text.ElideMiddle; textFormat: Text.PlainText }
            Text { id: info; anchors.right: dirBtn.left; anchors.rightMargin: 6; height: parent.height; verticalAlignment: Text.AlignVCenter
                   text: K.ago(row.modelData.time, Tr.t); color: Theme.textMuted; font.pixelSize: Theme.fs(11) }
            Rectangle {   // открыть папку, где лежит
                id: dirBtn
                anchors.right: parent.right; anchors.rightMargin: 4; anchors.verticalCenter: parent.verticalCenter
                width: 26; height: 26; radius: 13
                color: dm.pressed ? Theme.surfacePressed : dm.containsMouse ? Theme.surfaceHigher : "transparent"
                Text { anchors.centerIn: parent; text: String.fromCodePoint(0xF0770); color: Theme.textSecondary
                       font.family: Prefs.iconFont; font.pixelSize: Theme.fs(13) }
                MouseArea { id: dm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: rv.open(row.modelData.path.replace(/\/[^\/]*$/, "")) }
            }
        }
    }
}
