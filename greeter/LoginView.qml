import QtQuick
import Quickshell
import Quickshell.Services.UPower

// Вид экрана входа (по экземпляру на экран; поле и кнопки — только на основном): как замок Glide Shell —
// часы, дата, аватар, поле пароля; плюс выбор пользователя и сеанса, раскладка, батарея, питание.
// Пароль принят — содержимое уплывает вверх и тает над фоном, дальше greetd запускает сеанс.
Item {
    id: view
    required property var login
    property bool primary: true
    readonly property bool done: login.done
    function nf(code) { return String.fromCodePoint(code) }

    // ---- фон: как у замка (сияние акцента, сплошной или картинка с затемнением) ----
    Rectangle { anchors.fill: parent; color: Look.background }
    Rectangle {
        anchors.fill: parent
        visible: Look.background_ === "glow" || (Look.background_ === "image" && img.status !== Image.Ready)
        gradient: Gradient {
            GradientStop { position: 0; color: Qt.rgba(Look.accent.r, Look.accent.g, Look.accent.b, 0.16) }
            GradientStop { position: 0.55; color: "transparent" }
        }
    }
    Image {
        id: img
        anchors.fill: parent
        visible: Look.background_ === "image" && status === Image.Ready
        source: Look.background_ === "image" && Look.image ? (Look.image.indexOf("://") > 0 ? Look.image : "file://" + Look.image) : ""
        fillMode: Image.PreserveAspectCrop
        sourceSize.width: width; sourceSize.height: height
        asynchronous: true
    }
    Rectangle { anchors.fill: parent; visible: img.visible; color: Qt.rgba(0, 0, 0, 0.45) }

    MouseArea { anchors.fill: parent; onClicked: input.forceActiveFocus() }

    Item {
        id: fg
        anchors.fill: parent

        Rectangle {   // проверка без настоящего входа
            visible: view.login.test && view.primary
            anchors.top: parent.top; anchors.topMargin: 16
            anchors.horizontalCenter: parent.horizontalCenter
            height: 32; width: testText.implicitWidth + 32
            radius: Look.r(16)
            color: Look.surface
            border.color: Look.outline
            Text {
                id: testText
                anchors.centerIn: parent
                text: "Проверка экрана входа: сеанс не запускается · Esc — закрыть"
                color: Look.textSecondary; font.pixelSize: Look.fs(13)
            }
        }

        Column {
            id: content
            anchors.centerIn: parent
            anchors.verticalCenterOffset: -24
            spacing: 0

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Qt.formatTime(view.login.now, "HH:mm")
                font.pixelSize: Look.fs(Look.clockSize)
                font.weight: Look.clockBold ? Font.Bold : Font.Light
                color: Look.text
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: { var s = Qt.locale("ru_RU").toString(view.login.now, "dddd, d MMMM"); return s.charAt(0).toUpperCase() + s.slice(1) }
                font.pixelSize: Look.fs(18)
                color: Look.textSecondary
            }

            Item { width: 1; height: 56; visible: view.primary }

            // ---- пользователь: аватар, имя, стрелки (если их несколько) ----
            Row {
                visible: view.primary
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 18
                RoundBtn {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: view.login.users.length > 1
                    glyph: view.nf(0xF0141)
                    onClicked: view.login.nextUser(-1)
                }
                Rectangle {
                    width: 64; height: 64; radius: Look.r(32)
                    color: Look.accent
                    Text {
                        anchors.centerIn: parent
                        text: view.login.user ? (view.login.user.full || view.login.user.name).charAt(0).toUpperCase() : ""
                        font.pixelSize: Look.fs(26); font.bold: true
                        color: Look.accentText
                    }
                }
                RoundBtn {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: view.login.users.length > 1
                    glyph: view.nf(0xF0142)
                    onClicked: view.login.nextUser(1)
                }
            }
            Item { visible: view.primary; width: 1; height: 10 }
            Text {
                visible: view.primary
                anchors.horizontalCenter: parent.horizontalCenter
                text: view.login.user ? (view.login.user.full || view.login.user.name) : "Нет пользователей"
                font.pixelSize: Look.fs(15); font.weight: Font.Medium
                color: Look.text
            }
            Item { visible: view.primary; width: 1; height: 18 }

            // ---- поле пароля ----
            Rectangle {
                id: field
                visible: view.primary
                anchors.horizontalCenter: parent.horizontalCenter
                width: 300; height: 48; radius: Look.r(24)
                color: Look.surface
                border.width: input.activeFocus || view.login.error || view.done ? 2 : 1
                border.color: view.done ? Look.success : view.login.error && !view.login.busy ? Look.error
                            : input.activeFocus ? Look.accent : fieldHover.hovered ? Look.outlineHover : Look.outline
                HoverHandler { id: fieldHover; cursorShape: Qt.IBeamCursor }
                Behavior on border.color { ColorAnimation { duration: Look.ms(150) } }
                transform: Translate { id: shake }

                TextInput {
                    id: input
                    anchors.left: parent.left; anchors.right: go.left
                    anchors.leftMargin: 20; anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    focus: view.primary
                    echoMode: view.login.prompt !== "" && view.login.promptEcho ? TextInput.Normal : TextInput.Password
                    passwordCharacter: "●"
                    passwordMaskDelay: 0
                    readOnly: view.login.busy || view.done
                    font.pixelSize: Look.fs(16); font.letterSpacing: 2
                    color: Look.text
                    selectionColor: Look.accentHover
                    clip: true
                    onTextChanged: if (text && view.login.error && !view.login.busy) view.login.error = ""
                    Keys.onReturnPressed: view.submit()
                    Keys.onEnterPressed: view.submit()
                    Keys.onEscapePressed: view.login.test ? Qt.quit() : (text = "")
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: !input.text
                        text: view.login.busy ? "Проверка…" : view.login.prompt !== "" ? view.login.prompt : "Пароль"
                        font.pixelSize: Look.fs(15); font.letterSpacing: 0
                        color: Look.textMuted
                    }
                }
                Rectangle {   // «войти»: проверка — крутится, успех — галочка
                    id: go
                    anchors.right: parent.right; anchors.rightMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                    width: 36; height: 36; radius: Look.r(18)
                    color: view.done ? Look.success : input.text || view.login.busy
                           ? (goMa.pressed ? Look.accentPressed : goMa.containsMouse ? Look.accentLight : Look.accent)
                           : (goMa.containsMouse ? Look.surfaceHigher : Look.surfaceHigh)
                    scale: goMa.pressed ? 0.9 : 1
                    Behavior on color { ColorAnimation { duration: Look.ms(150) } }
                    Behavior on scale { NumberAnimation { duration: Look.ms(140); easing.type: Easing.OutBack } }
                    Text {
                        anchors.centerIn: parent
                        visible: !view.login.busy
                        text: view.done ? view.nf(0xF012C) : view.nf(0xF0054)
                        font.family: Look.iconFont; font.pixelSize: Look.fs(20)
                        color: view.done ? "#ffffff" : input.text ? Look.accentText : Look.textMuted
                        Behavior on color { ColorAnimation { duration: Look.ms(140) } }
                    }
                    Text {
                        anchors.centerIn: parent
                        visible: view.login.busy
                        text: view.nf(0xF0772)
                        font.family: Look.iconFont; font.pixelSize: Look.fs(20)
                        color: Look.accentText
                        RotationAnimator on rotation { running: view.login.busy; from: 0; to: 360; duration: 800; loops: Animation.Infinite }
                    }
                    MouseArea {
                        id: goMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { view.submit(); input.forceActiveFocus() }
                    }
                }
            }

            Item { visible: view.primary; width: 1; height: 12 }
            Text {   // ошибка или Caps Lock; место занято всегда — ничего не прыгает
                visible: view.primary
                anchors.horizontalCenter: parent.horizontalCenter
                width: 360; height: 36
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                text: view.login.error || (view.login.capsLock ? "Включён Caps Lock" : "")
                font.pixelSize: Look.fs(13)
                color: view.login.error ? Look.error : Look.warning
            }
        }

        // ---- низ слева: сеанс и раскладка ----
        Row {
            visible: view.primary
            anchors.left: parent.left; anchors.bottom: parent.bottom; anchors.margins: 20
            spacing: 8
            Chip {
                visible: view.login.sessions.length > 0
                icon: view.nf(0xF0379)
                label: view.login.session ? view.login.session.name : ""
                more: view.login.sessions.length > 1
                onClicked: view.login.nextSession()
            }
            Chip {
                visible: view.login.layouts.length > 1
                icon: view.nf(0xF030C)
                label: view.login.layoutShort
                onClicked: view.login.switchLayout()
            }
        }
        // ---- низ справа: батарея и питание ----
        Row {
            visible: view.primary
            anchors.right: parent.right; anchors.bottom: parent.bottom; anchors.margins: 20
            spacing: 8
            Chip {
                readonly property var batt: UPower.displayDevice
                readonly property bool charging: !!batt && (batt.state === UPowerDeviceState.Charging || batt.state === UPowerDeviceState.FullyCharged)
                visible: !!batt && batt.isLaptopBattery
                icon: {
                    if (!batt) return ""
                    if (charging) return view.nf(0xF0084)
                    var i = Math.round(batt.percentage * 10)
                    return i <= 0 ? view.nf(0xF008E) : i >= 10 ? view.nf(0xF0079) : view.nf(0xF007A + i - 1)
                }
                label: batt ? Math.round(batt.percentage * 100) + "%" : ""
                interactive: false
            }
            RoundBtn { glyph: view.nf(0xF04B2); tip: "Сон"; onClicked: view.login.power("suspend") }
            RoundBtn { glyph: view.nf(0xF0709); tip: "Перезагрузка"; onClicked: view.login.power("reboot") }
            RoundBtn { glyph: view.nf(0xF0425); tip: "Выключение"; danger: true; onClicked: view.login.power("poweroff") }
        }
    }

    function submit() {
        var t = input.text
        input.text = ""
        login.submit(t)
    }

    SequentialAnimation {
        id: shakeAnim
        NumberAnimation { target: shake; property: "x"; to: -10; duration: Look.ms(50); easing.type: Easing.OutQuad }
        NumberAnimation { target: shake; property: "x"; to: 9; duration: Look.ms(70); easing.type: Easing.InOutQuad }
        NumberAnimation { target: shake; property: "x"; to: -6; duration: Look.ms(70); easing.type: Easing.InOutQuad }
        NumberAnimation { target: shake; property: "x"; to: 3; duration: Look.ms(60); easing.type: Easing.InOutQuad }
        NumberAnimation { target: shake; property: "x"; to: 0; duration: Look.ms(60); easing.type: Easing.OutQuad }
    }
    ParallelAnimation {   // появление: середина всплывает снизу
        id: appear
        NumberAnimation { target: content; property: "opacity"; from: 0; to: 1; duration: Look.ms(360); easing.type: Easing.OutCubic }
        NumberAnimation { target: content; property: "anchors.verticalCenterOffset"; from: 0; to: -24; duration: Look.ms(460); easing.type: Easing.OutCubic }
    }
    ParallelAnimation {   // вход: содержимое уплывает вверх и тает, фон остаётся — как при разблокировке
        id: leave
        NumberAnimation { target: fg; property: "opacity"; to: 0; duration: Look.ms(300); easing.type: Easing.InOutQuad }
        NumberAnimation { target: content; property: "anchors.verticalCenterOffset"; to: -76; duration: Look.ms(320); easing.type: Easing.OutCubic }
        NumberAnimation { target: content; property: "scale"; to: 0.94; duration: Look.ms(320); easing.type: Easing.OutCubic }
    }
    Connections {
        target: view.login
        function onFailed() { shakeAnim.restart(); input.forceActiveFocus() }
        function onDoneChanged() { if (view.login.done) leave.restart() }
    }
    Component.onCompleted: { appear.restart(); if (primary) input.forceActiveFocus() }

    component RoundBtn: Rectangle {
        id: rb
        property string glyph
        property string tip
        property bool danger: false
        signal clicked()
        width: 40; height: 40; radius: Look.r(20)
        color: rbm.pressed ? Look.surfacePressed : rbm.containsMouse ? Look.surfaceHigher : Look.surface
        border.color: Look.outline
        scale: rbm.pressed ? 0.9 : 1
        Behavior on color { ColorAnimation { duration: Look.ms(120) } }
        Behavior on scale { NumberAnimation { duration: Look.ms(140); easing.type: Easing.OutBack } }
        Text {
            anchors.centerIn: parent
            text: rb.glyph
            color: rb.danger && rbm.containsMouse ? Look.error : Look.textVariant
            font.family: Look.iconFont; font.pixelSize: Look.fs(18)
            Behavior on color { ColorAnimation { duration: Look.ms(120) } }
        }
        MouseArea { id: rbm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: rb.clicked() }
        Rectangle {   // подсказка сверху
            visible: rb.tip !== "" && rbm.containsMouse
            anchors.horizontalCenter: parent.horizontalCenter
            y: -height - 8
            width: tipText.implicitWidth + 16; height: 26; radius: Look.r(13)
            color: Look.surfaceHigh
            border.color: Look.outline
            Text { id: tipText; anchors.centerIn: parent; text: rb.tip; color: Look.textVariant; font.pixelSize: Look.fs(12) }
        }
    }

    component Chip: Rectangle {
        id: chip
        property string icon
        property string label
        property bool more: false
        property bool interactive: true
        signal clicked()
        height: 32
        width: chipRow.implicitWidth + 24
        radius: Look.r(16)
        color: interactive && chipMouse.pressed ? Look.surfacePressed : interactive && chipMouse.containsMouse ? Look.surfaceHigher : Look.surface
        border.color: Look.outline
        scale: interactive && chipMouse.pressed ? 0.95 : 1
        Behavior on color { ColorAnimation { duration: Look.ms(120) } }
        Behavior on scale { NumberAnimation { duration: Look.ms(140); easing.type: Easing.OutBack } }
        Row {
            id: chipRow
            anchors.centerIn: parent
            spacing: 6
            Text { anchors.verticalCenter: parent.verticalCenter; text: chip.icon; font.family: Look.iconFont; font.pixelSize: Look.fs(16); color: Look.textVariant }
            Text { anchors.verticalCenter: parent.verticalCenter; text: chip.label; font.pixelSize: Look.fs(13); font.weight: Font.Medium; color: Look.text }
            Text { visible: chip.more; anchors.verticalCenter: parent.verticalCenter; text: String.fromCodePoint(0xF0140); font.family: Look.iconFont; font.pixelSize: Look.fs(14); color: Look.textMuted }
        }
        MouseArea {
            id: chipMouse
            anchors.fill: parent
            enabled: chip.interactive
            hoverEnabled: true
            cursorShape: chip.interactive ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: chip.clicked()
        }
    }
}
