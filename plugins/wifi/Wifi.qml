import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Networking
import qs

// Wi-Fi через NetworkManager (Quickshell.Networking): переключатель, сети рядом (сканирует, пока
// панель открыта), клик по сети — действия: подключить / ввести пароль / отключить / забыть.
// Пароль уходит прямо в NetworkManager (connectWithPsk) и здесь не хранится.
ColumnLayout {
    id: wf
    property var api
    readonly property color accent: api && api.accent ? api.accent : Theme.accent
    readonly property color accentText: api && api.accentText ? api.accentText : "#ffffff"
    readonly property string iconFont: api && api.iconFont ? api.iconFont : "JetBrainsMono Nerd Font"
    readonly property bool shown: api ? api.shown : false
    spacing: 6

    function nf(code) { return String.fromCodePoint(code) }

    readonly property var dev: {
        for (var d of Networking.devices.values) if (d.type === DeviceType.Wifi) return d
        return null
    }
    readonly property bool on: Networking.wifiEnabled
    // сканируем, только пока панель открыта: это и батарея, и радиоэфир
    Binding { target: wf.dev; property: "scannerEnabled"; value: wf.shown && wf.on; when: !!wf.dev }

    property string selected: ""      // имя сети, под которой открыты действия
    property string psk: ""           // вводимый пароль — до отправки
    property string error: ""
    property string errorNet: ""

    // список пересобираем, только когда меняется состав или состояние (не сила сигнала) —
    // иначе делегаты пересоздаются каждую секунду сканирования
    property var nets: []
    property string netsSig: ""
    function strength(n) { var s = n.signalStrength || 0; return s > 1 ? s / 100 : s }
    function rebuild() {
        if (!dev) { nets = []; netsSig = ""; return }
        var l = dev.networks.values.filter(n => n.name)
        l.sort((a, b) => (b.connected - a.connected) || (b.known - a.known) || (strength(b) - strength(a)))
        l = l.slice(0, 10)
        var sig = l.map(n => n.name + ":" + (n.connected ? 1 : 0) + (n.known ? 1 : 0) + (n.stateChanging ? 1 : 0)).join("|")
        if (sig !== netsSig) { netsSig = sig; nets = l }
    }
    Connections { target: wf.dev ? wf.dev.networks : null; function onValuesChanged() { wf.rebuild() } }
    Timer {   // сила сигнала и подключение меняются без смены состава — пересортировка раз в 3 с
        running: wf.shown && wf.on
        interval: 3000; repeat: true; triggeredOnStart: true
        onTriggered: wf.rebuild()
    }
    onDevChanged: rebuild()

    readonly property var selNet: {
        for (var n of nets) if (n.name === selected) return n
        return null
    }
    function isOpen(n) { return n.security === WifiSecurityType.Open || n.security === WifiSecurityType.Owe }
    function isEnterprise(n) {
        return n.security === WifiSecurityType.Wpa2Eap || n.security === WifiSecurityType.WpaEap
            || n.security === WifiSecurityType.Wpa3SuiteB192 || n.security === WifiSecurityType.Leap
    }
    function needsPassword(n) { return !!n && !n.known && !n.connected && !isOpen(n) && !isEnterprise(n) }
    function connect(n) {
        error = ""
        if (needsPassword(n)) {
            if (psk.length < 8) { error = Tr.t("Пароль Wi-Fi — не короче 8 символов"); errorNet = n.name; return }
            n.connectWithPsk(psk)
            psk = ""
        } else {
            n.connect()
        }
    }
    function fail(name, reason) {
        errorNet = name
        error = reason === ConnectionFailReason.NoSecrets ? Tr.t("Неверный пароль или он не сохранён")
              : reason === ConnectionFailReason.WifiAuthTimeout ? Tr.t("Сеть не ответила вовремя — неверный пароль?")
              : reason === ConnectionFailReason.WifiNetworkLost ? Tr.t("Сеть пропала")
              : Tr.t("Не удалось подключиться")
        if (reason === ConnectionFailReason.NoSecrets || reason === ConnectionFailReason.WifiAuthTimeout) selected = name
    }
    function signalGlyph(n) {
        var s = strength(n), lock = !isOpen(n)
        var lv = s > 0.75 ? 3 : s > 0.5 ? 2 : s > 0.25 ? 1 : 0
        return nf([lock ? 0xF0921 : 0xF091F, lock ? 0xF0924 : 0xF0922, lock ? 0xF0927 : 0xF0925, lock ? 0xF092A : 0xF0928][lv])
    }

    // ---- заголовок с переключателем ----
    RowLayout {
        Layout.fillWidth: true
        Text {
            Layout.fillWidth: true
            text: Tr.t("Сети Wi-Fi")
            color: Theme.textSecondary; font.pixelSize: Theme.fs(11); font.bold: true
        }
        Rectangle {   // переключатель
            implicitWidth: 40; implicitHeight: 22; radius: Theme.r(11)
            // наведение — ярче, нажатие — бегунок крупнее, недоступен — полупрозрачный
            opacity: Networking.wifiHardwareEnabled ? 1 : Theme.disabledOpacity
            color: wf.on ? (togMa.containsMouse ? Qt.lighter(wf.accent, 1.12) : wf.accent) : togMa.containsMouse ? Theme.surfacePressed : Theme.surfaceHigher
            Behavior on color { ColorAnimation { duration: Prefs.ms(160) } }
            Rectangle {
                Behavior on color { ColorAnimation { duration: Prefs.ms(140) } }
                width: 16; height: 16; radius: Theme.r(8)
                y: 3; x: wf.on ? parent.width - width - 3 : 3
                scale: togMa.pressed ? 1.2 : 1
                color: wf.on ? wf.accentText : togMa.containsMouse ? Theme.textVariant : Theme.textSecondary
                Behavior on scale { NumberAnimation { duration: Prefs.ms(140); easing.type: Easing.OutBack } }
                Behavior on x { NumberAnimation { duration: Prefs.ms(160); easing.type: Easing.OutCubic } }
            }
            MouseArea {
                id: togMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                enabled: Networking.wifiHardwareEnabled
                onClicked: Networking.wifiEnabled = !Networking.wifiEnabled
            }
        }
    }

    EmptyState {
        visible: !wf.on || !wf.dev || wf.nets.length === 0
        Layout.fillWidth: true
        compact: true
        glyph: wf.on && wf.dev ? 0xF0928 : 0xF092D
        text: !wf.dev ? Tr.t("Нет адаптера Wi-Fi") : !Networking.wifiHardwareEnabled ? Tr.t("Wi-Fi выключен кнопкой на ноутбуке")
            : !wf.on ? Tr.t("Wi-Fi выключен") : Tr.t("Ищу сети…")
    }

    // ---- сети: первые 5 (подключённая и сохранённые — сверху), остальные по «Ещё» ----
    property bool all: false
    onShownChanged: if (!shown) { all = false; selected = ""; psk = "" }
    Repeater {
        model: !wf.on ? [] : wf.all ? wf.nets : wf.nets.slice(0, 5)
        delegate: ColumnLayout {
            id: row
            required property var modelData
            readonly property var n: modelData
            readonly property bool open: wf.selected === n.name
            Layout.fillWidth: true
            spacing: 0

            Connections { target: row.n; function onConnectionFailed(reason) { wf.fail(row.n.name, reason) } }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 40
                radius: Theme.r(12)
                color: rm.pressed ? Theme.surfaceHigher : row.open ? Theme.surfaceHigh : rm.containsMouse ? Theme.surfaceLow : "transparent"
                Behavior on color { ColorAnimation { duration: Prefs.ms(120) } }
                Text {
                    Behavior on color { ColorAnimation { duration: Prefs.ms(140) } }
                    x: 10; anchors.verticalCenter: parent.verticalCenter
                    text: wf.signalGlyph(row.n)
                    color: row.n.connected ? wf.accent : Theme.textVariant
                    font.family: wf.iconFont; font.pixelSize: Theme.fs(17)
                }
                Column {
                    x: 38; anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 38 - 12
                    Text {
                        width: parent.width
                        text: row.n.name
                        color: Theme.text; font.pixelSize: Theme.fs(13); font.bold: row.n.connected
                        elide: Text.ElideRight
                    }
                    Text {
                        Behavior on color { ColorAnimation { duration: Prefs.ms(140) } }
                        width: parent.width
                        visible: text !== ""
                        text: row.n.stateChanging ? Tr.t("подключение…") : row.n.connected ? Tr.t("подключено")
                            : row.n.known ? Tr.t("сохранена") : wf.isOpen(row.n) ? Tr.t("открытая") : ""
                        color: row.n.connected ? wf.accent : Theme.textMuted; font.pixelSize: Theme.fs(11)
                    }
                }
                MouseArea {
                    id: rm
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: { wf.error = ""; wf.psk = ""; wf.selected = row.open ? "" : row.n.name }
                }
            }

            // действия под выбранной сетью
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
                Rectangle {   // пароль — только для новой защищённой сети
                    visible: wf.needsPassword(row.n)
                    Layout.fillWidth: true
                    implicitHeight: 30; radius: Theme.r(15)
                    color: Theme.surface
                    border.width: pass.activeFocus ? 2 : 1
                    border.color: pass.activeFocus ? wf.accent : passHover.hovered ? Theme.outlineHover : Theme.outline
                    Behavior on border.color { ColorAnimation { duration: Prefs.ms(150) } }
                    HoverHandler { id: passHover; cursorShape: Qt.IBeamCursor }
                    TextInput {
                        id: pass
                        anchors.left: parent.left; anchors.right: parent.right
                        anchors.leftMargin: 12; anchors.rightMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        echoMode: TextInput.Password
                        passwordCharacter: "●"
                        color: Theme.text; font.pixelSize: Theme.fs(12)
                        clip: true
                        text: wf.psk
                        onTextChanged: wf.psk = text
                        onVisibleChanged: if (visible) forceActiveFocus()
                        Keys.onReturnPressed: wf.connect(row.n)
                        Keys.onEnterPressed: wf.connect(row.n)
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: !pass.text
                            text: Tr.t("Пароль")
                            color: Theme.textMuted; font.pixelSize: Theme.fs(12)
                        }
                    }
                }
                Text {
                    visible: wf.isEnterprise(row.n) && !row.n.known
                    Layout.fillWidth: true
                    text: Tr.t("Корпоративная сеть — настрой в nm-connection-editor")
                    color: Theme.textSecondary; font.pixelSize: Theme.fs(11)
                    wrapMode: Text.WordWrap
                }
                Item { visible: !wf.needsPassword(row.n) && !(wf.isEnterprise(row.n) && !row.n.known); Layout.fillWidth: true }
                Btn {
                    visible: !row.n.connected && !(wf.isEnterprise(row.n) && !row.n.known)
                    label: Tr.t("Подключить"); primary: true; accent: wf.accent; accentText: wf.accentText
                    onClicked: wf.connect(row.n)
                }
                Btn { visible: row.n.connected; label: Tr.t("Отключить"); onClicked: row.n.disconnect() }
                Btn { visible: row.n.known; label: Tr.t("Забыть"); onClicked: { row.n.forget(); wf.selected = "" } }
            }
            Text {
                visible: row.open && wf.error !== "" && wf.errorNet === row.n.name
                Layout.leftMargin: 38
                Layout.bottomMargin: 6
                text: wf.error
                color: Theme.error; font.pixelSize: Theme.fs(11)
            }
        }
    }

    Text {
        Behavior on color { ColorAnimation { duration: Prefs.ms(140) } }
        visible: wf.on && wf.nets.length > 5
        Layout.leftMargin: 10
        text: wf.all ? Tr.t("Свернуть") : Tr.t("Ещё ") + (wf.nets.length - 5)
        color: moreMouse.pressed ? Theme.text : moreMouse.containsMouse ? Theme.textVariant : Theme.textMuted; font.pixelSize: Theme.fs(12)
        MouseArea { id: moreMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: wf.all = !wf.all }
    }

    component Btn: Rectangle {
        id: b
        property string label
        property bool primary: false
        property color accent: Theme.accent
        property color accentText: "#ffffff"
        signal clicked()
        implicitWidth: bt.implicitWidth + 24; implicitHeight: 30; radius: Theme.r(15)
        color: primary ? (bm.pressed ? Qt.darker(accent, 1.15) : bm.containsMouse ? Qt.lighter(accent, 1.12) : accent)
                       : (bm.pressed ? Theme.surfacePressed : bm.containsMouse ? Theme.surfaceHigher : Theme.surfaceHigh)
        opacity: enabled ? 1 : Theme.disabledOpacity
        scale: bm.pressed ? 0.95 : 1
        Behavior on color { ColorAnimation { duration: Prefs.ms(120) } }
        Behavior on scale { NumberAnimation { duration: Prefs.ms(140); easing.type: Easing.OutBack } }
        Text { id: bt; anchors.centerIn: parent; text: b.label; color: b.primary ? b.accentText : Theme.text; font.pixelSize: Theme.fs(12) }
        MouseArea { id: bm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: b.clicked() }
    }
}
