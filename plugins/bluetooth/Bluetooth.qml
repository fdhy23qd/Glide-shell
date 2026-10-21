import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth
import qs

// Bluetooth (BlueZ через Quickshell.Bluetooth): переключатель, «Мои устройства» и «Рядом» —
// поиск идёт, только пока панель открыта. Клик по своему устройству — действия (подключить,
// отключить, забыть), по новому — сопряжение; коды подтверждает окно агента (BtAgent.qml в ядре).
ColumnLayout {
    id: bt
    property var api
    readonly property color accent: api && api.accent ? api.accent : Theme.accent
    readonly property color accentText: api && api.accentText ? api.accentText : "#ffffff"
    readonly property string iconFont: api && api.iconFont ? api.iconFont : "JetBrainsMono Nerd Font"
    readonly property bool shown: api ? api.shown : false
    spacing: 6

    function nf(code) { return String.fromCodePoint(code) }
    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property bool on: !!adapter && adapter.enabled
    Binding { target: bt.adapter; property: "discovering"; value: bt.shown && bt.on; when: !!bt.adapter }

    // заблокированный через rfkill адаптер BlueZ не включит — сначала снимаем блокировку (ACL пользователя)
    function toggle() {
        if (on) { adapter.enabled = false; return }
        if (adapter.state === BluetoothAdapterState.Blocked) { api.run(["rfkill", "unblock", "bluetooth"]); powerOn.restart() }
        else adapter.enabled = true
    }
    Timer { id: powerOn; interval: 600; onTriggered: if (bt.adapter) bt.adapter.enabled = true }

    property string selected: ""   // адрес устройства с открытыми действиями
    property string error: ""
    onShownChanged: if (!shown) { selected = ""; error = "" }

    // как и у Wi-Fi: пересобираем списки, только когда меняется состав или состояние
    property var mine: []
    property var near: []
    property string sig: ""
    function rebuild() {
        var all = Bluetooth.devices.values
        var m = all.filter(d => d.paired).sort((a, b) => (b.connected - a.connected) || a.name.localeCompare(b.name))
        // безымянные «устройства» рядом — обычно чужие метки и браслеты, прячем
        var n = all.filter(d => !d.paired && d.deviceName).slice(0, 8)
        var s = m.concat(n).map(d => d.address + (d.connected ? 1 : 0) + (d.pairing ? 1 : 0) + d.state).join("|")
        if (s !== sig) { sig = s; mine = m; near = n }
    }
    Connections { target: Bluetooth.devices; function onValuesChanged() { bt.rebuild() } }
    Timer { running: bt.shown; interval: 1500; repeat: true; triggeredOnStart: true; onTriggered: bt.rebuild() }

    function glyph(d) {
        var i = d.icon || ""
        return nf(i.indexOf("headset") >= 0 || i.indexOf("headphone") >= 0 ? 0xF02CB
                : i.indexOf("phone") >= 0 ? 0xF011C : i.indexOf("mouse") >= 0 ? 0xF037D
                : i.indexOf("keyboard") >= 0 ? 0xF030C : i.indexOf("computer") >= 0 ? 0xF0322
                : i.indexOf("audio") >= 0 || i.indexOf("speaker") >= 0 ? 0xF04C3
                : i.indexOf("gaming") >= 0 || i.indexOf("joystick") >= 0 ? 0xF0297 : 0xF00AF)
    }
    function stateText(d) {
        if (d.pairing) return Tr.t("сопряжение…")
        if (d.state === BluetoothDeviceState.Connecting) return Tr.t("подключение…")
        if (d.state === BluetoothDeviceState.Disconnecting) return Tr.t("отключение…")
        if (d.connected) return Tr.t("подключено") + (d.batteryAvailable ? " · " + Math.round(d.battery * 100) + "%" : "")
        return d.paired ? "" : ""
    }
    function pairAndConnect(d) {
        error = ""
        d.pair()
        pairWatch.target = d
    }
    Connections {   // сопряглось — доверяем и подключаем (наушники сами этого не делают)
        id: pairWatch
        target: null
        function onPairedChanged() {
            var d = pairWatch.target
            if (d && d.paired) { d.trusted = true; d.connect(); pairWatch.target = null; bt.selected = "" }
        }
        function onPairingChanged() {
            var d = pairWatch.target
            if (d && !d.pairing && !d.paired) { bt.error = Tr.t("Не удалось сопрячь «") + d.name + "»"; pairWatch.target = null }
        }
    }

    // ---- заголовок с переключателем ----
    RowLayout {
        Layout.fillWidth: true
        Text {
            Layout.fillWidth: true
            text: "Bluetooth"
            color: Theme.textSecondary; font.pixelSize: Theme.fs(11); font.bold: true
        }
        Text {
            visible: bt.on && bt.adapter.discovering
            text: Tr.t("поиск…")
            color: Theme.textMuted; font.pixelSize: Theme.fs(11)
        }
        Rectangle {
            implicitWidth: 40; implicitHeight: 22; radius: Theme.r(11)
            // наведение — ярче, нажатие — бегунок крупнее, недоступен — полупрозрачный
            opacity: !!bt.adapter ? 1 : Theme.disabledOpacity
            color: bt.on ? (togMa.containsMouse ? Qt.lighter(bt.accent, 1.12) : bt.accent) : togMa.containsMouse ? Theme.surfacePressed : Theme.surfaceHigher
            Behavior on color { ColorAnimation { duration: Prefs.ms(160) } }
            Rectangle {
                Behavior on color { ColorAnimation { duration: Prefs.ms(140) } }
                width: 16; height: 16; radius: Theme.r(8)
                y: 3; x: bt.on ? parent.width - width - 3 : 3
                scale: togMa.pressed ? 1.2 : 1
                color: bt.on ? bt.accentText : togMa.containsMouse ? Theme.textVariant : Theme.textSecondary
                Behavior on scale { NumberAnimation { duration: Prefs.ms(140); easing.type: Easing.OutBack } }
                Behavior on x { NumberAnimation { duration: Prefs.ms(160); easing.type: Easing.OutCubic } }
            }
            MouseArea {
                id: togMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                enabled: !!bt.adapter
                onClicked: bt.toggle()
            }
        }
    }
    EmptyState {
        visible: !bt.adapter || !bt.on
        Layout.fillWidth: true
        compact: true
        glyph: 0xF00B2
        text: !bt.adapter ? Tr.t("Нет адаптера Bluetooth") : Tr.t("Bluetooth выключен")
    }
    Text {
        visible: bt.error !== ""
        Layout.fillWidth: true
        text: bt.error
        color: Theme.error; font.pixelSize: Theme.fs(11)
        wrapMode: Text.WordWrap
    }

    Section { visible: bt.on && bt.mine.length > 0; text: Tr.t("Мои устройства") }
    Repeater {
        model: bt.on ? bt.mine : []
        delegate: deviceRow
    }
    Section { visible: bt.on; text: bt.near.length ? Tr.t("Рядом") : Tr.t("Рядом — ищу…") }
    Repeater {
        model: bt.on ? bt.near : []
        delegate: deviceRow
    }

    component Section: Text {
        Layout.topMargin: 4
        color: Theme.textMuted; font.pixelSize: Theme.fs(11)
    }

    // строка устройства — обычный Component, а не inline: ему нужен id `bt` этого файла
    Component {
        id: deviceRow
        ColumnLayout {
        id: row
        required property var modelData
        readonly property var d: modelData
        readonly property bool open: bt.selected === d.address
        Layout.fillWidth: true
        spacing: 0
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 40
            radius: Theme.r(12)
            color: rm.pressed ? Theme.surfaceHigher : row.open ? Theme.surfaceHigh : rm.containsMouse ? Theme.surfaceLow : "transparent"
            Behavior on color { ColorAnimation { duration: Prefs.ms(120) } }
            Text {
                Behavior on color { ColorAnimation { duration: Prefs.ms(140) } }
                x: 10; anchors.verticalCenter: parent.verticalCenter
                text: bt.glyph(row.d)
                color: row.d.connected ? bt.accent : Theme.textVariant
                font.family: bt.iconFont; font.pixelSize: Theme.fs(17)
            }
            Column {
                x: 38; anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 38 - 12
                Text {
                    width: parent.width
                    text: row.d.name
                    color: Theme.text; font.pixelSize: Theme.fs(13); font.bold: row.d.connected
                    elide: Text.ElideRight
                }
                Text {
                    Behavior on color { ColorAnimation { duration: Prefs.ms(140) } }
                    width: parent.width
                    visible: text !== ""
                    text: bt.stateText(row.d)
                    color: row.d.connected ? bt.accent : Theme.textMuted; font.pixelSize: Theme.fs(11)
                }
            }
            MouseArea {
                id: rm
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    bt.error = ""
                    if (!row.d.paired) bt.pairAndConnect(row.d)              // новое — сразу сопрягаем
                    else bt.selected = row.open ? "" : row.d.address
                }
            }
        }
        RowLayout {   // действия раскрываются под строкой, а не появляются рывком
            property real expand: row.open ? 1 : 0
            Behavior on expand { NumberAnimation { duration: Prefs.ms(180); easing.type: Easing.OutCubic } }
            visible: expand > 0.01
            opacity: expand
            clip: true
            Layout.preferredHeight: implicitHeight * expand
            Layout.fillWidth: true
            Layout.leftMargin: 38
            Layout.topMargin: 4 * expand
            Layout.bottomMargin: 6 * expand
            spacing: 6
            Item { Layout.fillWidth: true }
            Btn { visible: !row.d.connected; label: Tr.t("Подключить"); primary: true; accent: bt.accent; accentText: bt.accentText; onClicked: row.d.connect() }
            Btn { visible: row.d.connected; label: Tr.t("Отключить"); onClicked: row.d.disconnect() }
            Btn { label: Tr.t("Забыть"); onClicked: { row.d.forget(); bt.selected = "" } }
        }
        }
    }

    component Btn: Rectangle {
        id: b
        property string label
        property bool primary: false
        property color accent: Theme.accent
        property color accentText: "#ffffff"
        signal clicked()
        implicitWidth: btt.implicitWidth + 24; implicitHeight: 30; radius: Theme.r(15)
        color: primary ? (bm.pressed ? Qt.darker(accent, 1.15) : bm.containsMouse ? Qt.lighter(accent, 1.12) : accent)
                       : (bm.pressed ? Theme.surfacePressed : bm.containsMouse ? Theme.surfaceHigher : Theme.surfaceHigh)
        opacity: enabled ? 1 : Theme.disabledOpacity
        scale: bm.pressed ? 0.95 : 1
        Behavior on color { ColorAnimation { duration: Prefs.ms(120) } }
        Behavior on scale { NumberAnimation { duration: Prefs.ms(140); easing.type: Easing.OutBack } }
        Text { id: btt; anchors.centerIn: parent; text: b.label; color: b.primary ? b.accentText : Theme.text; font.pixelSize: Theme.fs(12) }
        MouseArea { id: bm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: b.clicked() }
    }
}
