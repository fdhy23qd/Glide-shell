import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import qs

// Приложения: часто запускаемые и все по алфавиту. Искать — общим поиском: просто начни печатать.
// Список — из встроенной службы Quickshell. Иконки темы — только синхронно: поиск значков в Qt
// не потокобезопасен, асинхронная загрузка роняла оболочку.
ColumnLayout {
    id: ap
    property var api
    readonly property var counts: api && api.appCounts ? api.appCounts : ({})
    readonly property var all: DesktopEntries.applications.values
        .filter(e => !e.noDisplay).sort((a, b) => a.name.localeCompare(b.name))
    readonly property var frequent: all.filter(e => (counts[e.id] || 0) > 0)
        .sort((a, b) => counts[b.id] - counts[a.id]).slice(0, 8)
    readonly property real cell: width / 4
    spacing: 8

    component AppTile: Rectangle {
        id: tile
        required property var modelData
        property var api
        property real cellW: 80
        width: cellW; height: 80
        radius: Theme.r(14)
        color: tm.containsMouse ? Theme.surfaceHigh : "transparent"
        scale: tm.pressed ? 0.94 : 1
        Behavior on color { ColorAnimation { duration: Prefs.ms(120) } }
        Behavior on scale { NumberAnimation { duration: Prefs.ms(140); easing.type: Easing.OutBack } }
        IconImage {
            anchors.horizontalCenter: parent.horizontalCenter
            y: 8
            implicitSize: 36
            source: Quickshell.iconPath(tile.modelData.icon || "application-x-executable", "application-x-executable")
        }
        Text {
            x: 4; y: 48
            width: parent.width - 8
            text: tile.modelData.name
            color: Theme.textVariant; font.pixelSize: Theme.fs(11)
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            maximumLineCount: 2
            elide: Text.ElideRight
        }
        MouseArea { id: tm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                    onClicked: if (tile.api) tile.api.launchApp(tile.modelData) }
    }

    Text {
        Layout.fillWidth: true
        text: Tr.t("Начни печатать, чтобы найти приложение; Enter — запустить")
        color: Theme.textMuted; font.pixelSize: Theme.fs(11)
        wrapMode: Text.WordWrap
    }
    Text { visible: ap.frequent.length > 0; text: Tr.t("Часто"); color: Theme.textSecondary; font.pixelSize: Theme.fs(12); font.bold: true }
    Grid {
        visible: ap.frequent.length > 0
        columns: 4
        Repeater { model: ap.frequent; delegate: AppTile { api: ap.api; cellW: ap.cell } }
    }
    Text { text: Tr.t("Все приложения · ") + ap.all.length; color: Theme.textSecondary; font.pixelSize: Theme.fs(12); font.bold: true }
    Grid {
        columns: 4
        Repeater { model: ap.all; delegate: AppTile { api: ap.api; cellW: ap.cell } }
    }
}
