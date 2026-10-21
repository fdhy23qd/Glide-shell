import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Polkit

// polkit-агент: окно пароля, когда программе нужны права (pkexec, «Диски», NetworkManager и т. п.).
// За флагом Prefs.polkit: агент в сессии может быть только один, и пока работает DMS, он у него.
// Пароль уходит прямо в polkit (flow.submit) и нигде не хранится.
Scope {
    id: pk
    readonly property var agent: loader.item
    readonly property var flow: agent ? agent.flow : null
    readonly property bool open: !!agent && agent.isActive && !!flow
    property bool busy: false
    property string error: ""
    signal failed()

    LazyLoader {
        id: loader
        active: Prefs.polkit
        PolkitAgent {}
    }

    // если polkit предлагает несколько учёток (root и пользователь из wheel) — берём свою
    function pickSelf() {
        var ids = flow ? flow.identities : null
        if (!ids || ids.length < 2) return
        var me = Quickshell.env("USER")
        for (var i = 0; i < ids.length; i++) {
            if (!ids[i].isGroup && ids[i].string === me) {
                if (ids[i] !== flow.selectedIdentity) { switching = true; flow.selectedIdentity = ids[i]; switching = false }
                return
            }
        }
    }
    property bool switching: false   // смена учётки обрывает сессию — это не ошибка пароля

    Connections {
        target: pk.agent
        function onAuthenticationRequestStarted() { pk.error = ""; pk.busy = false; pk.pickSelf() }
    }
    Connections {
        target: pk.flow
        function onAuthenticationFailed() {
            if (pk.switching) return
            pk.busy = false
            pk.error = pk.flow && pk.flow.supplementaryIsError && pk.flow.supplementaryMessage
                       ? pk.flow.supplementaryMessage : Tr.t("Неверный пароль")
            pk.failed()
        }
        function onIsResponseRequiredChanged() { if (pk.flow.isResponseRequired) pk.busy = false }
        function onAuthenticationSucceeded() { pk.busy = false }
    }

    function submit(text) {
        if (!flow || busy || !text) return
        if (!flow.isResponseRequired) return
        busy = true
        error = ""
        flow.submit(text)
    }
    function cancel() { if (flow) flow.cancelAuthenticationRequest() }

    // известные действия — по-русски, остальное как прислал polkit
    function describe(f) {
        if (!f) return ""
        var a = f.actionId || ""
        if (a === "org.freedesktop.policykit.exec") return Tr.t("Программа просит права администратора (pkexec)")
        if (a.indexOf("org.freedesktop.NetworkManager") === 0) return Tr.t("Изменение настроек сети")
        if (a.indexOf("org.freedesktop.udisks2") === 0) return Tr.t("Действие с дисками")
        if (a.indexOf("org.freedesktop.packagekit") === 0) return Tr.t("Установка или обновление программ")
        if (a.indexOf("org.freedesktop.systemd1") === 0) return Tr.t("Управление системными службами")
        if (a.indexOf("org.freedesktop.login1") === 0) return Tr.t("Управление питанием и сеансами")
        return f.message
    }

    LazyLoader {
        active: pk.open
        PanelWindow {
            id: win
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
            WlrLayershell.namespace: "glide-polkit"
            color: "transparent"

            Rectangle {   // затемнение
                id: dim
                anchors.fill: parent
                color: Qt.rgba(0, 0, 0, 0.55)
                opacity: 0
                Component.onCompleted: opacity = 1
                Behavior on opacity { NumberAnimation { duration: Prefs.ms(180) } }
                MouseArea { anchors.fill: parent }   // клики мимо окна никуда не уходят
            }

            Rectangle {
                id: card
                anchors.centerIn: parent
                width: 380
                height: col.implicitHeight + 48
                radius: Theme.radiusLg
                color: Theme.background
                border.color: Theme.outline
                scale: 0.94
                opacity: 0
                Component.onCompleted: { scale = 1; opacity = 1; input.forceActiveFocus() }
                Behavior on scale { enabled: Prefs.anim > 0; Spring { bounce: 0.2 } }
                Behavior on opacity { NumberAnimation { duration: Prefs.ms(160) } }
                transform: Translate { id: shake }

                Column {
                    id: col
                    x: 24; y: 24
                    width: parent.width - 48
                    spacing: 0

                    Rectangle {   // значок: щит с замком
                        width: 48; height: 48; radius: Theme.r(16)
                        color: Theme.accentSoft
                        Text {
                            anchors.centerIn: parent
                            text: String.fromCodePoint(0xF099D)
                            color: Prefs.accent
                            font.family: Prefs.iconFont; font.pixelSize: Theme.fs(26)
                        }
                    }
                    Item { width: 1; height: 14 }
                    Text {
                        width: parent.width
                        text: Tr.t("Нужен пароль")
                        color: Theme.text; font.pixelSize: Theme.fs(18); font.bold: true
                    }
                    Item { width: 1; height: 6 }
                    Text {
                        width: parent.width
                        text: pk.describe(pk.flow)
                        color: Theme.textVariant; font.pixelSize: Theme.fs(13)
                        wrapMode: Text.Wrap
                        textFormat: Text.PlainText
                    }
                    Text {   // исходный текст polkit и id действия — мелко, для понимания, что просит права
                        width: parent.width
                        visible: !!pk.flow && pk.describe(pk.flow) !== pk.flow.message
                        topPadding: 4
                        text: pk.flow ? pk.flow.message + "\n" + pk.flow.actionId : ""
                        color: Theme.textMuted; font.pixelSize: Theme.fs(11)
                        wrapMode: Text.Wrap   // по словам; длинный id действия — где придётся
                        textFormat: Text.PlainText
                    }
                    Item { width: 1; height: 16 }

                    Rectangle {   // поле пароля
                        width: parent.width; height: 44; radius: Theme.radiusMd
                        color: Theme.surface
                        border.width: input.activeFocus || pk.error ? 2 : 1
                        border.color: pk.error ? Theme.error : input.activeFocus ? Prefs.accent
                                    : inputHover.hovered ? Theme.outlineHover : Theme.outline
                        HoverHandler { id: inputHover; cursorShape: Qt.IBeamCursor }
                        Behavior on border.color { ColorAnimation { duration: Prefs.ms(150) } }
                        TextInput {
                            id: input
                            anchors.left: parent.left; anchors.right: parent.right
                            anchors.leftMargin: 16; anchors.rightMargin: 16
                            anchors.verticalCenter: parent.verticalCenter
                            echoMode: pk.flow && pk.flow.responseVisible ? TextInput.Normal : TextInput.Password
                            passwordCharacter: "●"
                            passwordMaskDelay: 0
                            readOnly: pk.busy
                            color: Theme.text; font.pixelSize: Theme.fs(15)
                            selectionColor: Theme.accentHover
                            clip: true
                            onTextChanged: if (text && pk.error) pk.error = ""
                            Keys.onReturnPressed: { pk.submit(text); text = "" }
                            Keys.onEnterPressed: { pk.submit(text); text = "" }
                            Keys.onEscapePressed: pk.cancel()
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: !input.text
                                text: pk.busy ? Tr.t("Проверка…")
                                    : pk.flow && pk.flow.inputPrompt && !/^password:?\s*$/i.test(pk.flow.inputPrompt)
                                      ? pk.flow.inputPrompt : Tr.t("Пароль")
                                color: Theme.textMuted; font.pixelSize: Theme.fs(14)
                            }
                        }
                    }
                    Text {
                        width: parent.width
                        height: 30
                        verticalAlignment: Text.AlignVCenter
                        text: pk.error
                        color: Theme.error; font.pixelSize: Theme.fs(12)
                        elide: Text.ElideRight
                    }

                    Row {
                        anchors.right: parent.right
                        spacing: 8
                        Btn { label: Tr.t("Отмена"); onClicked: pk.cancel() }
                        Btn {
                            label: pk.busy ? Tr.t("Проверка…") : Tr.t("Подтвердить")
                            primary: true
                            onClicked: { pk.submit(input.text); input.text = "" }
                        }
                    }
                }
            }

            SequentialAnimation {
                id: shakeAnim
                NumberAnimation { target: shake; property: "x"; to: -10; duration: Prefs.ms(50) }
                NumberAnimation { target: shake; property: "x"; to: 9; duration: Prefs.ms(70) }
                NumberAnimation { target: shake; property: "x"; to: -5; duration: Prefs.ms(70) }
                NumberAnimation { target: shake; property: "x"; to: 0; duration: Prefs.ms(60) }
            }
            Connections {
                target: pk
                function onFailed() { input.text = ""; shakeAnim.restart(); input.forceActiveFocus() }
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
        Behavior on color { ColorAnimation { duration: Prefs.ms(120) } }
        Text {
            id: t
            anchors.centerIn: parent
            text: b.label
            color: b.primary ? Theme.accentText : Theme.text
            font.pixelSize: Theme.fs(13); font.weight: Font.Medium
        }
        MouseArea { id: m; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: b.clicked() }
    }
}
