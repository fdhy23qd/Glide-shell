import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Bluetooth

// Агент Bluetooth: пока адаптер включён, держит tools/glide-bt-agent.py (агент BlueZ по умолчанию)
// и показывает его вопросы окном: «код совпадает?», ввести PIN или код, разрешить подключение,
// показать код, который нужно набрать на устройстве. Без агента сопрягаются только устройства
// без кода (наушники, колонки, мыши); DMS держал свой — после его отключения агента не было.
Scope {
    id: ba
    readonly property bool on: !!Bluetooth.defaultAdapter && Bluetooth.defaultAdapter.enabled
    property var req: null      // {id, kind: confirm|pin|passkey|authorize|display, device, code}

    Process {
        id: agent
        running: ba.on && Prefs.warm   // через несколько секунд после старта
        stdinEnabled: true
        command: ["setpriv", "--pdeathsig", "TERM", "python3", "-I", Quickshell.shellDir + "/tools/glide-bt-agent.py"]
        stdout: SplitParser {
            onRead: line => {
                var m
                try { m = JSON.parse(line) } catch (e) { return }
                if (m.kind === "ready") return
                if (m.kind === "cancel") { ba.req = null; return }
                ba.req = m
            }
        }
        stderr: StdioCollector { onStreamFinished: if (text.trim()) console.warn("glide-shell bt-agent:", text.trim()) }
        onRunningChanged: if (!running) ba.req = null
    }

    function answer(ok, value) {
        if (!req) return
        if (req.id !== undefined) agent.write(req.id + (ok ? " yes" : " no") + (value ? " " + value : "") + "\n")
        req = null
    }

    LazyLoader {
        active: !!ba.req
        PanelWindow {
            id: dlg
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
            WlrLayershell.namespace: "glide-bt-agent"
            color: Qt.rgba(0, 0, 0, 0.45)
            readonly property var r: ba.req || ({})
            readonly property bool input: dlg.r.kind === "pin" || dlg.r.kind === "passkey"

            Rectangle {
                anchors.centerIn: parent
                width: 360
                height: col.implicitHeight + 48
                radius: Theme.radiusLg
                color: Theme.background
                border.color: Theme.outline

                Column {
                    id: col
                    x: 24; y: 24
                    width: parent.width - 48
                    spacing: 10
                    Text {
                        text: String.fromCodePoint(0xF00AF)
                        color: Prefs.accent; font.family: Prefs.iconFont; font.pixelSize: Theme.fs(30)
                    }
                    Text {
                        width: parent.width
                        text: dlg.r.kind === "authorize" ? Tr.t("Разрешить подключение?") : Tr.t("Сопряжение Bluetooth")
                        color: Theme.text; font.pixelSize: Theme.fs(17); font.bold: true
                    }
                    Text {
                        width: parent.width
                        wrapMode: Text.Wrap
                        textFormat: Text.PlainText
                        color: Theme.textVariant; font.pixelSize: Theme.fs(13)
                        text: (dlg.r.device || Tr.t("Устройство")) + (
                              dlg.r.kind === "confirm" ? Tr.t(" показывает код ниже? Подтверди, только если он совпадает.")
                            : dlg.r.kind === "display" ? Tr.t(": набери этот код на устройстве и нажми Enter.")
                            : dlg.r.kind === "pin" ? Tr.t(" просит PIN-код (часто 0000 или 1234).")
                            : dlg.r.kind === "passkey" ? Tr.t(" просит код из 6 цифр, показанный на нём.")
                            : Tr.t(" хочет подключиться к этому компьютеру."))
                    }
                    Text {   // код
                        visible: !!dlg.r.code
                        text: dlg.r.code ? dlg.r.code.replace(/(\d{3})(\d{3})/, "$1 $2") : ""
                        color: Theme.text; font.pixelSize: Theme.fs(34); font.bold: true
                        font.letterSpacing: 3
                        font.features: ({ "tnum": 1 })
                    }
                    Rectangle {
                        visible: dlg.input
                        width: parent.width; height: 42; radius: Theme.radiusMd
                        color: Theme.surface
                        border.width: field.activeFocus ? 2 : 1
                        border.color: field.activeFocus ? Prefs.accent : fieldHover.hovered ? Theme.outlineHover : Theme.outline
                        Behavior on border.color { ColorAnimation { duration: Prefs.ms(150) } }
                        HoverHandler { id: fieldHover; cursorShape: Qt.IBeamCursor }
                        TextInput {
                            id: field
                            anchors.left: parent.left; anchors.right: parent.right
                            anchors.leftMargin: 14; anchors.rightMargin: 14
                            anchors.verticalCenter: parent.verticalCenter
                            color: Theme.text; font.pixelSize: Theme.fs(16)
                            inputMethodHints: Qt.ImhDigitsOnly
                            validator: RegularExpressionValidator { regularExpression: dlg.r.kind === "passkey" ? /\d{0,6}/ : /\S{0,16}/ }
                            focus: dlg.input
                            Keys.onReturnPressed: ba.answer(true, text)
                            Keys.onEnterPressed: ba.answer(true, text)
                        }
                    }
                    Row {
                        anchors.right: parent.right
                        spacing: 8
                        topPadding: 6
                        Btn { visible: dlg.r.kind !== "display"; label: Tr.t("Отклонить"); onClicked: ba.answer(false) }
                        Btn {
                            primary: true
                            label: dlg.r.kind === "display" ? Tr.t("Готово") : dlg.r.kind === "confirm" ? Tr.t("Коды совпадают") : Tr.t("Разрешить")
                            onClicked: ba.answer(true, dlg.input ? field.text : "")
                        }
                    }
                }
                Keys.onEscapePressed: ba.answer(false)
                focus: !dlg.input
            }
        }
    }

    component Btn: Rectangle {
        id: b
        property string label
        property bool primary: false
        signal clicked()
        width: Math.max(96, t.implicitWidth + 32); height: 38; radius: Theme.r(19)
        color: primary ? (m.pressed ? Theme.accentPressed : m.containsMouse ? Theme.accentLight : Prefs.accent)
                       : (m.pressed ? Theme.surfacePressed : m.containsMouse ? Theme.surfaceHigher : Theme.surfaceHigh)
        opacity: enabled ? 1 : Theme.disabledOpacity
        scale: m.pressed ? 0.96 : 1
        Behavior on scale { NumberAnimation { duration: Prefs.ms(140); easing.type: Easing.OutBack } }
        Text { id: t; anchors.centerIn: parent; text: b.label; color: b.primary ? Theme.accentText : Theme.text; font.pixelSize: Theme.fs(13) }
        MouseArea { id: m; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: b.clicked() }
    }
}
