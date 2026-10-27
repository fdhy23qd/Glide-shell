import QtQuick
import qs

// Элемент бара «Диски»: виден, пока что-то подключено; щелчок — раздел (категория «Управление»).
Item {
    id: chip
    property var api
    readonly property var on: Drives.mounted
    readonly property bool want: Prefs.drives && on.length > 0
    readonly property var tip: want ? { title: Tr.t("Съёмные диски"), rows: on.map(d => ({ name: Drives.name(d), value: Drives.info(d) })),
                                        hint: Tr.t("Щелчок — открыть, отключить, извлечь") } : ""
    implicitWidth: row.implicitWidth
    implicitHeight: 24
    Row {
        id: row
        anchors.verticalCenter: parent.verticalCenter
        spacing: 3
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: String.fromCodePoint(0xF0553); color: Theme.textVariant
            font.family: Prefs.iconFont; font.pixelSize: Theme.fs(14)
        }
        Text {
            visible: chip.on.length > 1
            anchors.verticalCenter: parent.verticalCenter
            text: chip.on.length; color: Theme.textVariant; font.pixelSize: Theme.fs(11)
        }
    }
    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: if (chip.api) chip.api.openCategory("control") }
}
