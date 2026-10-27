import QtQuick
import Quickshell
import Quickshell.Wayland

// Окно вопроса плагина (Confirms.qml): поверх всего, как окно polkit, но без пароля. Заголовок — имя плагина
// из реестра, ниже — его вопрос; Enter — да, Esc — нет. Пока экран заперт — ждёт.
Scope {
    id: cd
    required property var confirms
    property bool locked: false
    readonly property var q: confirms.current
    LazyLoader {
        active: !!cd.confirms.current && !cd.locked
        PanelWindow {
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
            WlrLayershell.namespace: "glide-confirm"
            color: "transparent"
            Rectangle {
                anchors.fill: parent
                color: Qt.rgba(0, 0, 0, 0.45)
                opacity: 0
                Component.onCompleted: opacity = 1
                Behavior on opacity { NumberAnimation { duration: Prefs.ms(160) } }
                MouseArea { anchors.fill: parent }
            }
            Rectangle {
                id: card
                anchors.centerIn: parent
                width: 380
                height: col.implicitHeight + 44
                radius: Theme.radiusLg
                color: Theme.background
                border.color: Theme.outline
                scale: 0.94; opacity: 0
                Component.onCompleted: { scale = 1; opacity = 1; keys.forceActiveFocus() }
                Behavior on scale { enabled: Prefs.anim > 0; Spring { bounce: 0.2 } }
                Behavior on opacity { NumberAnimation { duration: Prefs.ms(150) } }
                Item {
                    id: keys
                    focus: true
                    Keys.onReturnPressed: cd.confirms.answer(true)
                    Keys.onEnterPressed: cd.confirms.answer(true)
                    Keys.onEscapePressed: cd.confirms.answer(false)
                }
                Column {
                    id: col
                    x: 22; y: 22; width: parent.width - 44
                    spacing: 10
                    Row {
                        spacing: 10
                        Rectangle {
                            width: 36; height: 36; radius: Theme.r(12); color: Theme.accentSoft
                            Text { anchors.centerIn: parent; text: String.fromCodePoint(0xF02D7); color: Prefs.accent
                                   font.family: Prefs.iconFont; font.pixelSize: Theme.fs(20) }
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            width: col.width - 46
                            text: cd.q ? Tr.t("Плагин «") + cd.q.name + Tr.t("» спрашивает") : ""
                            color: Theme.textSecondary; font.pixelSize: Theme.fs(12); elide: Text.ElideRight
                        }
                    }
                    Text {
                        width: parent.width
                        text: cd.q ? cd.q.text : ""
                        color: Theme.text; font.pixelSize: Theme.fs(14); wrapMode: Text.Wrap
                        textFormat: Text.PlainText
                    }
                    Row {
                        anchors.right: parent.right
                        spacing: 8
                        Btn { label: cd.q && cd.q.no ? cd.q.no : Tr.t("Нет"); onClicked: cd.confirms.answer(false) }
                        Btn { label: cd.q && cd.q.yes ? cd.q.yes : Tr.t("Да"); primary: true; onClicked: cd.confirms.answer(true) }
                    }
                }
            }
        }
    }
    component Btn: Rectangle {
        id: b
        property string label
        property bool primary: false
        signal clicked()
        width: bt.implicitWidth + 32; height: 34; radius: Theme.r(17)
        color: primary ? (bm.pressed ? Theme.accentPressed : bm.containsMouse ? Theme.accentLight : Prefs.accent)
                       : (bm.pressed ? Theme.surfacePressed : bm.containsMouse ? Theme.surfaceHigher : Theme.surfaceHigh)
        scale: bm.pressed ? 0.94 : 1
        Behavior on color { ColorAnimation { duration: Prefs.ms(120) } }
        Behavior on scale { NumberAnimation { duration: Prefs.ms(120); easing.type: Easing.OutBack } }
        Text { id: bt; anchors.centerIn: parent; text: b.label; color: b.primary ? Theme.accentText : Theme.text; font.pixelSize: Theme.fs(13) }
        MouseArea { id: bm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: b.clicked() }
    }
}
