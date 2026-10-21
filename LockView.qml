import QtQuick
import Quickshell
import Quickshell.Services.UPower
import Quickshell.Services.Mpris
import Quickshell.Widgets

// Содержимое экрана блокировки (по экземпляру на экран): часы, дата, пользователь, поле пароля,
// внизу — раскладка и батарея. Вся логика — в LockScreen.qml (lock).
// Разблокировка: поле вспыхивает зелёным, всё содержимое уплывает вверх и тает над фоном,
// дальше LockScreen снимает замок и растворяет такой же фон над рабочим столом.
Item {
    id: view
    required property var lock
    property real backdrop: 1            // непрозрачность фона (предпросмотр растворяет его сам)
    readonly property bool preview: lock.mode === "preview"
    readonly property bool done: lock.unlocking   // пароль принят — экран уходит
    readonly property string iconFont: Prefs.iconFont
    function nf(code) { return String.fromCodePoint(code) }

    // музыка: играющий плеер, иначе тот, что последним был в острове
    readonly property var player: {
        var ps = Mpris.players.values
        for (var p of ps) if (p.isPlaying) return p
        var last = lock.panel ? lock.panel.musicPlayer : null
        return last && ps.indexOf(last) >= 0 ? last : null
    }
    // непрочитанные уведомления — только число, без текста
    readonly property int unread: Notifs.active ? Notifs.unread : 0

    // фон; в предпросмотре после пароля он уходит тем же эффектом, что заслонка над рабочим столом
    LockBackdrop { id: bg; anchors.fill: parent }
    Reveal {
        anchors.fill: parent
        cover: bg
        progress: 1 - view.backdrop
        style: view.lock.revealStyle
        islandRect: view.lock.islandRect(width)
    }
    MouseArea {   // клик в любом месте возвращает фокус в поле
        anchors.fill: parent
        onClicked: input.forceActiveFocus()
    }

    // всё, что уходит при разблокировке, — над фоном
    Item {
        id: fg
        anchors.fill: parent
        // уход в паре со стилем (lp 0 → 1): круг — сжаться к аватару, сквозь — навстречу, остров — вверх в точку
        transform: Scale {
            origin.x: fg.width / 2
            origin.y: view.lock.revealStyle === "island" ? 0 : fg.height * 0.53
            xScale: view.leaveScale; yScale: view.leaveScale
        }

        // ---- полоса режима: тест или предпросмотр ----
        Rectangle {
            visible: view.lock.mode === "test" || view.preview
            anchors.top: parent.top
            anchors.topMargin: 16
            anchors.horizontalCenter: parent.horizontalCenter
            height: 32
            width: modeText.implicitWidth + 32
            radius: Theme.r(16)
            color: view.preview ? Theme.surface : Qt.rgba(Theme.warning.r, Theme.warning.g, Theme.warning.b, 0.18)
            border.color: view.preview ? Theme.outline : Theme.warning
            Text {
                id: modeText
                anchors.centerIn: parent
                font.pixelSize: Theme.fs(13)
                color: view.preview ? Theme.textSecondary : Theme.warning
                text: view.preview ? Tr.t("Предпросмотр: экран не заблокирован · Esc — закрыть")
                                   : Tr.t("Тестовая блокировка — снимется сама через ") + view.lock.testLeft + Tr.t(" с")
            }
        }

        // ---- середина ----
        Column {
            id: content
            anchors.centerIn: parent
            anchors.verticalCenterOffset: -24
            spacing: 0

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Qt.formatTime(view.lock.now, "HH:mm")
                font.pixelSize: Theme.fs(Prefs.lockClockSize)          // настройка «Размер часов»
                font.weight: Prefs.lockClockBold ? Font.Bold : Font.Light
                color: Theme.text
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: {
                    var s = Tr.locale.toString(view.lock.now, "dddd, d MMMM")
                    return s.charAt(0).toUpperCase() + s.slice(1)
                }
                font.pixelSize: Theme.fs(18)
                color: Theme.textSecondary
            }
            Text {   // своё приветствие (настройка)
                visible: text !== ""
                anchors.horizontalCenter: parent.horizontalCenter
                topPadding: 6
                text: Prefs.lockGreeting
                font.pixelSize: Theme.fs(15)
                color: Theme.textVariant
            }

            Item { width: 1; height: Prefs.lockShowUser ? 56 : 40 }

            Rectangle {   // аватар: первая буква имени на акценте
                visible: Prefs.lockShowUser
                anchors.horizontalCenter: parent.horizontalCenter
                width: 64; height: 64; radius: Theme.r(32)
                color: Theme.accent
                Text {
                    anchors.centerIn: parent
                    text: view.lock.user.charAt(0).toUpperCase()
                    font.pixelSize: Theme.fs(26)
                    font.bold: true
                    color: Theme.accentText
                }
            }
            Item { visible: Prefs.lockShowUser; width: 1; height: 10 }
            Text {
                visible: Prefs.lockShowUser
                anchors.horizontalCenter: parent.horizontalCenter
                text: view.lock.user
                font.pixelSize: Theme.fs(15)
                font.weight: Font.Medium
                color: Theme.text
            }
            Item { width: 1; height: 18 }

            // поле пароля
            Rectangle {
                id: field
                anchors.horizontalCenter: parent.horizontalCenter
                width: 300; height: 48; radius: Theme.r(24)
                color: Theme.surface
                border.width: input.activeFocus || view.lock.error || view.done ? 2 : 1
                border.color: view.done ? Theme.success : view.lock.error ? Theme.error
                            : input.activeFocus ? Theme.accent : fieldHover.hovered ? Theme.outlineHover : Theme.outline
                HoverHandler { id: fieldHover; cursorShape: Qt.IBeamCursor }
                Behavior on border.color { ColorAnimation { duration: Prefs.ms(150) } }
                transform: Translate { id: shake }

                TextInput {
                    id: input
                    anchors.left: parent.left
                    anchors.right: go.left
                    anchors.leftMargin: 20
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    focus: true
                    echoMode: TextInput.Password
                    passwordCharacter: "●"
                    passwordMaskDelay: 0
                    readOnly: view.lock.busy || view.done
                    font.pixelSize: Theme.fs(16)
                    font.letterSpacing: 2
                    color: Theme.text
                    selectionColor: Theme.accentHover
                    clip: true
                    onTextChanged: if (text && view.lock.error && !view.lock.busy) view.lock.error = ""
                    Keys.onReturnPressed: view.lock.submit(text)
                    Keys.onEnterPressed: view.lock.submit(text)
                    Keys.onEscapePressed: view.preview ? view.lock.closePreview() : (text = "")

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: !input.text
                        text: view.lock.busy ? Tr.t("Проверка…") : Tr.t("Пароль")
                        font.pixelSize: Theme.fs(15)
                        color: Theme.textMuted
                    }
                }

                Rectangle {   // кнопка «войти»; во время проверки — крутится, при успехе — галочка
                    id: go
                    anchors.right: parent.right
                    anchors.rightMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                    width: 36; height: 36; radius: Theme.r(18)
                    color: view.done ? Theme.success : input.text || view.lock.busy
                           ? (goMa.pressed ? Theme.accentPressed : goMa.containsMouse ? Theme.accentLight : Theme.accent)
                           : (goMa.containsMouse ? Theme.surfaceHigher : Theme.surfaceHigh)
                    scale: goMa.pressed ? 0.9 : 1
                    Behavior on color { ColorAnimation { duration: Prefs.ms(150) } }
                    Behavior on scale { NumberAnimation { duration: Prefs.ms(140); easing.type: Easing.OutBack } }
                    Text {
                        Behavior on color { ColorAnimation { duration: Prefs.ms(140) } }
                        anchors.centerIn: parent
                        visible: !view.lock.busy
                        text: view.done ? view.nf(0xF012C) : view.nf(0xF0054)
                        font.family: view.iconFont
                        font.pixelSize: Theme.fs(20)
                        color: view.done ? "#ffffff" : input.text ? Theme.accentText : Theme.textMuted
                        scale: view.done ? 1.15 : 1
                        Behavior on scale { NumberAnimation { duration: Prefs.ms(160); easing.type: Easing.OutBack } }
                    }
                    Text {   // крутится только пока идёт проверка (аниматор — в потоке отрисовки)
                        anchors.centerIn: parent
                        visible: view.lock.busy
                        text: view.nf(0xF0772)
                        font.family: view.iconFont
                        font.pixelSize: Theme.fs(20)
                        color: Theme.accentText
                        RotationAnimator on rotation {
                            running: view.lock.busy
                            from: 0; to: 360; duration: 800
                            loops: Animation.Infinite
                        }
                    }
                    MouseArea {
                        id: goMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { view.lock.submit(input.text); input.forceActiveFocus() }
                    }
                }
            }

            Item { width: 1; height: 12 }
            Text {   // ошибка или Caps Lock; место занято всегда, чтобы ничего не прыгало
                readonly property bool caps: !!view.lock.panel && view.lock.panel.capsLock
                anchors.horizontalCenter: parent.horizontalCenter
                width: 360
                height: 36
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                text: view.lock.error || (caps ? Tr.t("Включён Caps Lock") : "")
                font.pixelSize: Theme.fs(13)
                color: view.lock.error ? Theme.error : Theme.warning
            }
        }

        // ---- низ: раскладка и батарея ----
        Row {
            anchors.left: parent.left
            anchors.bottom: parent.bottom
            anchors.margins: 20
            spacing: 8
            Chip {
                visible: Prefs.lockShowLayout && Niri.layouts.length > 1
                icon: view.nf(0xF030C)
                label: {
                    var n = Niri.layouts[Niri.layoutIdx] || ""
                    var first = n.split(/[\s(]/)[0]
                    var known = { English: "EN", Russian: "RU", Ukrainian: "UA", Belarusian: "BY", German: "DE" }
                    return known[first] || first.slice(0, 2).toUpperCase()
                }
                onClicked: Quickshell.execDetached(["niri", "msg", "action", "switch-layout", "next"])
            }
        }
        Row {
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: 20
            spacing: 8
            Chip {
                visible: Prefs.lockShowUnread && view.unread > 0
                icon: view.nf(0xF116B)
                label: view.unread
            }
            Chip {
                readonly property var batt: UPower.displayDevice
                readonly property bool charging: !!batt && (batt.state === UPowerDeviceState.Charging
                                                           || batt.state === UPowerDeviceState.FullyCharged)
                visible: Prefs.lockShowBattery && !!batt && batt.isLaptopBattery
                icon: {
                    if (!batt) return ""
                    if (charging) return view.nf(0xF0084)
                    var i = Math.round(batt.percentage * 10)
                    return i <= 0 ? view.nf(0xF008E) : i >= 10 ? view.nf(0xF0079) : view.nf(0xF007A + i - 1)
                }
                label: batt ? Math.round(batt.percentage * 100) + "%" : ""
            }
        }
    }

    // ---- музыка внизу по центру: обложка, трек, кнопки ----
    Rectangle {
        id: media
        parent: fg
        visible: Prefs.lockShowMedia && !!view.player
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 20
        width: 360; height: 60
        radius: Theme.r(20)
        color: Theme.surface
        border.color: Theme.outline
        ClippingRectangle {
            x: 8; anchors.verticalCenter: parent.verticalCenter
            width: 44; height: 44; radius: Theme.r(12)
            color: Theme.surfaceHigh
            Text {
                anchors.centerIn: parent
                text: "♫"; color: Prefs.accent; font.pixelSize: Theme.fs(20)
            }
            Image {
                anchors.fill: parent
                source: view.player ? (view.player.trackArtUrl || "") : ""
                sourceSize.width: 88; sourceSize.height: 88
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                visible: status === Image.Ready
            }
        }
        Column {
            x: 64; anchors.verticalCenter: parent.verticalCenter
            width: parent.width - 64 - 112
            Text {
                width: parent.width
                text: view.player ? (view.player.trackTitle || view.player.identity || "") : ""
                color: Theme.text; font.pixelSize: Theme.fs(13); font.bold: true
                elide: Text.ElideRight
            }
            Text {
                width: parent.width
                text: view.player ? (view.player.trackArtist || view.player.identity || "") : ""
                color: Theme.textSecondary; font.pixelSize: Theme.fs(12)
                elide: Text.ElideRight
            }
        }
        Row {
            anchors.right: parent.right; anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            spacing: 0
            MediaBtn { glyph: view.nf(0xF04AE); active: !!view.player && view.player.canGoPrevious; onClicked: view.player.previous() }
            MediaBtn {
                glyph: view.player && view.player.isPlaying ? view.nf(0xF03E4) : view.nf(0xF040A)
                active: !!view.player && view.player.canTogglePlaying
                onClicked: view.player.togglePlaying()
            }
            MediaBtn { glyph: view.nf(0xF04AD); active: !!view.player && view.player.canGoNext; onClicked: view.player.next() }
        }
    }

    SequentialAnimation {
        id: shakeAnim
        NumberAnimation { target: shake; property: "x"; to: -10; duration: Prefs.ms(50); easing.type: Easing.OutQuad }
        NumberAnimation { target: shake; property: "x"; to: 9; duration: Prefs.ms(70); easing.type: Easing.InOutQuad }
        NumberAnimation { target: shake; property: "x"; to: -6; duration: Prefs.ms(70); easing.type: Easing.InOutQuad }
        NumberAnimation { target: shake; property: "x"; to: 3; duration: Prefs.ms(60); easing.type: Easing.InOutQuad }
        NumberAnimation { target: shake; property: "x"; to: 0; duration: Prefs.ms(60); easing.type: Easing.OutQuad }
    }

    // появление: середина всплывает снизу
    ParallelAnimation {
        id: appear
        NumberAnimation { target: fg; property: "opacity"; to: 1; duration: Prefs.ms(200) }
        NumberAnimation { target: content; property: "scale"; to: 1; duration: Prefs.ms(200) }
        NumberAnimation { target: content; property: "opacity"; from: 0; to: 1; duration: Prefs.ms(320); easing.type: Easing.OutCubic }
        NumberAnimation { target: content; property: "anchors.verticalCenterOffset"; from: 0; to: -24; duration: Prefs.ms(420); easing.type: Easing.OutCubic }
    }
    property real lp: 0
    readonly property real leaveScale: {
        var to = ({ iris: 0.6, curtains: 1.04, tiles: 0.92, zoom: 1.5, island: 0.22 })[lock.revealStyle]
        return to === undefined ? 1 : 1 + (to - 1) * lp
    }
    // остальные стили: содержимое сжимается или летит навстречу (leaveScale) и тает
    SequentialAnimation {
        id: leaveStyled
        PauseAnimation { duration: Prefs.ms(70) }
        ParallelAnimation {
            NumberAnimation { target: view; property: "lp"; from: 0; to: 1; duration: Prefs.ms(300); easing.type: Easing.InCubic }
            NumberAnimation { target: fg; property: "opacity"; to: 0; duration: Prefs.ms(290); easing.type: Easing.InQuad }
        }
    }
    // уход после верного пароля: галочка видна мгновение, затем всё уплывает вверх и тает
    // (длительность вместе с паузой — как unlockTimer в LockScreen, 380 мс)
    SequentialAnimation {
        id: leave
        PauseAnimation { duration: Prefs.ms(90) }
        ParallelAnimation {
            NumberAnimation { target: fg; property: "opacity"; to: 0; duration: Prefs.ms(280); easing.type: Easing.InOutQuad }
            NumberAnimation { target: content; property: "anchors.verticalCenterOffset"; to: -76; duration: Prefs.ms(290); easing.type: Easing.OutCubic }
            NumberAnimation { target: content; property: "scale"; to: 0.94; duration: Prefs.ms(290); easing.type: Easing.OutCubic }
        }
    }

    Connections {
        target: view.lock
        function onFailed() { input.text = ""; shakeAnim.restart(); input.forceActiveFocus() }
        function onModeChanged() {
            input.text = ""
            if (view.lock.mode) { view.lp = 0; appear.restart(); input.forceActiveFocus() }
        }
        function onUnlockingChanged() {
            if (view.lock.unlocking) {
                appear.stop()
                if (view.lock.revealStyle === "rise") leave.restart(); else leaveStyled.restart()
                return
            }
            // замок снят после ухода (finishing) — содержимое остаётся ушедшим; раньше release() сбрасывал
            // unlocking раньше mode, и экран «возвращался» поверх рабочего стола (виден в предпросмотре)
            if (!view.lock.mode || view.lock.finishing) return
            leave.stop(); leaveStyled.stop(); view.lp = 0   // разблокировку отменили (сон) — возвращаем экран
            input.text = ""
            appear.restart()
            input.forceActiveFocus()
        }
    }
    Component.onCompleted: { appear.restart(); input.forceActiveFocus() }

    component MediaBtn: Rectangle {
        id: mb
        property string glyph
        property bool active: true
        signal clicked()
        width: 36; height: 36; radius: Theme.r(18)
        color: !active ? "transparent" : mbm.pressed ? Theme.surfacePressed : mbm.containsMouse ? Theme.surfaceHigher : "transparent"
        opacity: active ? 1 : Theme.disabledOpacity
        scale: mbm.pressed && active ? 0.88 : 1
        Behavior on scale { NumberAnimation { duration: Prefs.ms(140); easing.type: Easing.OutBack } }
        Text { anchors.centerIn: parent; text: mb.glyph; color: Theme.text; font.family: Prefs.iconFont; font.pixelSize: Theme.fs(18) }
        MouseArea { id: mbm; anchors.fill: parent; hoverEnabled: true; cursorShape: mb.active ? Qt.PointingHandCursor : Qt.ArrowCursor; onClicked: if (mb.active) mb.clicked() }
    }

    component Chip: Rectangle {
        id: chip
        property string icon
        property string label
        signal clicked()
        height: 32
        width: chipRow.implicitWidth + 24
        radius: Theme.r(16)
        color: chipMouse.pressed ? Theme.surfacePressed : chipMouse.containsMouse ? Theme.surfaceHigher : Theme.surface
        border.color: Theme.outline
        scale: chipMouse.pressed ? 0.95 : 1
        Behavior on color { ColorAnimation { duration: Prefs.ms(120) } }
        Behavior on scale { NumberAnimation { duration: Prefs.ms(140); easing.type: Easing.OutBack } }
        Row {
            id: chipRow
            anchors.centerIn: parent
            spacing: 6
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: chip.icon
                font.family: Prefs.iconFont
                font.pixelSize: Theme.fs(16)
                color: Theme.textVariant
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: chip.label
                font.pixelSize: Theme.fs(13)
                font.weight: Font.Medium
                color: Theme.text
            }
        }
        MouseArea {
            id: chipMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: chip.clicked()
        }
    }
}
