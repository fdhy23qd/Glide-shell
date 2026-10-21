import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland

// Мастер первого запуска: язык → вид (акцент, тон, анимации; меняется сразу) → остров и док → клавиши → готово.
// Появляется один раз на новой установке (Prefs.welcome ставит setup.sh), снова — кнопкой в «Виде» или
// IPC panel welcome. Esc / «Пропустить» — закрыть; Enter / → — дальше, ← — назад.
PanelWindow {
    id: wz
    required property var root
    property int step: 0
    readonly property int steps: 5
    property int dir: 1
    signal done()

    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "glide-welcome"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    color: "transparent"

    function go(d) {
        var n = step + d
        if (n < 0) return
        if (n >= steps) { finish(); return }
        dir = d; step = n
        slide.restart()
    }
    function finish() { Prefs.set("welcomeDone", true); wz.done() }
    function nf(c) { return String.fromCodePoint(c) }

    Rectangle {   // затемнение
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.55)
        opacity: shown ? 1 : 0
        property bool shown: false
        Component.onCompleted: shown = true
        Behavior on opacity { NumberAnimation { duration: Prefs.ms(260) } }
        MouseArea { anchors.fill: parent }   // клики мимо карточки — никуда
    }

    Rectangle {
        id: card
        anchors.centerIn: parent
        width: Math.min(580, parent.width - 40)
        height: 470
        radius: Theme.r(28)
        color: Theme.surface
        border.color: Theme.outline
        scale: appear ? 1 : 0.94
        opacity: appear ? 1 : 0
        property bool appear: false
        Component.onCompleted: appear = true
        Behavior on scale { NumberAnimation { duration: Prefs.ms(320); easing.type: Easing.OutBack } }
        Behavior on opacity { NumberAnimation { duration: Prefs.ms(220) } }
        focus: true
        Keys.onEscapePressed: wz.finish()
        Keys.onReturnPressed: wz.go(1)
        Keys.onRightPressed: wz.go(1)
        Keys.onLeftPressed: wz.go(-1)

        // содержимое шага: въезжает со стороны перехода
        Item {
            id: page
            x: 32; y: 30
            width: parent.width - 64
            height: parent.height - 30 - 84
            transform: Translate { id: shift }
            ParallelAnimation {
                id: slide
                NumberAnimation { target: shift; property: "x"; from: 28 * wz.dir; to: 0; duration: Prefs.ms(300); easing.type: Easing.OutCubic }
                NumberAnimation { target: page; property: "opacity"; from: 0; to: 1; duration: Prefs.ms(260) }
            }

            // ---- 0: привет и язык ----
            ColumnLayout {
                anchors.fill: parent
                visible: wz.step === 0
                spacing: 14
                Text { text: wz.nf(0xF1821); color: Prefs.accent; font.family: Prefs.iconFont; font.pixelSize: Theme.fs(44) }
                Text { text: Tr.t("Добро пожаловать в Glide Shell"); color: Theme.text; font.pixelSize: Theme.fs(24); font.bold: true }
                Text {
                    Layout.fillWidth: true
                    text: Tr.t("Остров сверху — это часы и всё, что происходит: музыка, уведомления, громкость. Щелчок по нему открывает панель. Настроим главное за минуту — всё можно поменять потом в настройках.")
                    color: Theme.textSecondary; font.pixelSize: Theme.fs(14); wrapMode: Text.WordWrap
                }
                Item { Layout.fillHeight: true }
                Label { text: "Язык / Language" }   // без перевода: видно на любом языке
                Pills {
                    options: [{ label: Tr.t("как в системе"), value: "auto" }, { label: "Русский", value: "ru" }, { label: "English", value: "en" }]   // без перевода
                    current: Prefs.lang
                    onPicked: (v) => Prefs.set("lang", v)
                }
            }

            // ---- 1: вид ----
            ColumnLayout {
                anchors.fill: parent
                visible: wz.step === 1
                spacing: 12
                Title { text: Tr.t("Как будет выглядеть") }
                Hint { text: Tr.t("Меняется сразу — посмотри на остров и эту карточку") }
                Label { text: Tr.t("Акцентный цвет") }
                Row {
                    spacing: 10
                    Repeater {
                        model: ["#7b61ff", "#4f7cff", "#2bb3e6", "#1fbf9f", "#34c77b", "#f5a623", "#ff7a45", "#ef5b8d"]
                        delegate: Rectangle {
                            id: sw
                            required property string modelData
                            readonly property bool sel: Qt.colorEqual(Prefs.accent, modelData)
                            width: 34; height: 34; radius: 17
                            color: "transparent"
                            border.color: sel ? Theme.text : swMa.containsMouse ? Theme.outlineHover : "transparent"
                            border.width: 2
                            scale: swMa.pressed ? 0.88 : 1
                            Behavior on scale { NumberAnimation { duration: Prefs.ms(140); easing.type: Easing.OutBack } }
                            Behavior on border.color { ColorAnimation { duration: Prefs.ms(140) } }
                            Rectangle { anchors.centerIn: parent; width: 24; height: 24; radius: 12; color: sw.modelData }
                            MouseArea { id: swMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                        onClicked: Prefs.set("accent", sw.modelData) }
                        }
                    }
                }
                Label { text: Tr.t("Тон фона") }
                Pills {
                    options: [{ label: Tr.t("графит Glide"), value: "glide" }, { label: Tr.t("AMOLED-чёрный"), value: "amoled" },
                              { label: Tr.t("мягкий"), value: "soft" }]
                    current: Prefs.themeTone
                    onPicked: (v) => Prefs.set("themeTone", v)
                }
                Label { text: Tr.t("Анимации") }
                Pills {
                    options: [{ label: Tr.t("выкл"), value: 0 }, { label: Tr.t("быстрые"), value: 0.6 },
                              { label: Tr.t("обычные"), value: 1 }, { label: Tr.t("плавные"), value: 1.5 }]
                    current: Prefs.anim
                    onPicked: (v) => Prefs.set("anim", v)
                }
            }

            // ---- 2: остров и док ----
            ColumnLayout {
                anchors.fill: parent
                visible: wz.step === 2
                spacing: 12
                Title { text: Tr.t("Остров и док") }
                Label { text: Tr.t("Музыка, уведомления и прочее в острове") }
                Pills {
                    options: [{ label: Tr.t("компактно"), value: "inline" }, { label: Tr.t("прижать к верху"), value: "raise" },
                              { label: Tr.t("строками"), value: "stack" }]
                    current: Prefs.islandMode
                    onPicked: (v) => Prefs.set("islandMode", v)
                }
                Hint {
                    text: Prefs.islandMode === "inline" ? Tr.t("В строке часов: остров не ниже бара, подробности — при наведении")
                        : Prefs.islandMode === "raise" ? Tr.t("Строками под часами; на время активности остров поднимается к краю экрана")
                        : Tr.t("Каждая активность — отдельной строкой под часами")
                }
                Label { text: Tr.t("Док внизу") }
                Pills {
                    options: [{ label: Tr.t("умно"), value: "smart" }, { label: Tr.t("по наведению"), value: "autohide" },
                              { label: Tr.t("всегда"), value: "always" }]
                    current: Prefs.dockMode
                    onPicked: (v) => Prefs.set("dockMode", v)
                }
                Hint { text: Tr.t("«Умно» — прячется, когда его закрывает окно") }
                Item { Layout.fillHeight: true }
                Hint { text: Tr.t("Что показывать в острове и в каком порядке — «Настройки» → «Остров»") }
            }

            // ---- 3: клавиши ----
            ColumnLayout {
                anchors.fill: parent
                visible: wz.step === 3
                spacing: 10
                Title { text: Tr.t("Главные клавиши") }
                Repeater {
                    model: [{ k: "Mod+D", t: Tr.t("приложения и поиск: файлы, действия, интернет") },
                            { k: "Super", t: Tr.t("коротко — центр управления (если включён keyd)") },
                            { k: "Super+Alt+L", t: Tr.t("заблокировать экран") },
                            { k: "Ctrl+K", t: Tr.t("поиск в открытой панели") },
                            { k: "Alt+1…9", t: Tr.t("разделы панели") },
                            { k: "Esc", t: Tr.t("закрыть панель") }]
                    delegate: RowLayout {
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: 12
                        Rectangle {
                            Layout.preferredWidth: 120
                            implicitHeight: 30; radius: Theme.r(10)
                            color: Theme.surfaceHigh; border.color: Theme.outline
                            Text { anchors.centerIn: parent; text: parent.parent.modelData.k; color: Theme.text
                                   font.pixelSize: Theme.fs(13); font.family: "JetBrainsMono Nerd Font" }
                        }
                        Text { Layout.fillWidth: true; text: parent.modelData.t; color: Theme.textSecondary
                               font.pixelSize: Theme.fs(13); wrapMode: Text.WordWrap }
                    }
                }
            }

            // ---- 4: готово ----
            ColumnLayout {
                anchors.fill: parent
                visible: wz.step === 4
                spacing: 14
                Text { text: wz.nf(0xF012C); color: Theme.success; font.family: Prefs.iconFont; font.pixelSize: Theme.fs(44) }
                Title { text: Tr.t("Всё готово") }
                Hint {
                    text: Tr.t("Обои, виджеты рабочего стола, экран блокировки, ночной свет и остальное — в настройках (⚙ в панели). Мастер можно открыть снова: «Настройки» → «Вид».")
                }
                Item { Layout.fillHeight: true }
                RowLayout {
                    spacing: 10
                    Btn { text: Tr.t("Открыть панель"); primary: true; onClicked: { wz.finish(); wz.root.open() } }
                    Btn { text: Tr.t("Настройки"); onClicked: { wz.finish(); wz.root.settingsPage = "look"; wz.root.settingsOpen = true; wz.root.open() } }
                }
            }
        }

        // ---- низ: точки шагов и кнопки ----
        Row {
            anchors.left: parent.left; anchors.leftMargin: 32
            anchors.bottom: parent.bottom; anchors.bottomMargin: 34
            spacing: 6
            Repeater {
                model: wz.steps
                delegate: Rectangle {
                    required property int index
                    width: index === wz.step ? 22 : 8; height: 8; radius: 4
                    color: index === wz.step ? Prefs.accent : Theme.surfaceHigher
                    Behavior on width { NumberAnimation { duration: Prefs.ms(240); easing.type: Easing.OutCubic } }
                    Behavior on color { ColorAnimation { duration: Prefs.ms(200) } }
                }
            }
        }
        Row {
            anchors.right: parent.right; anchors.rightMargin: 24
            anchors.bottom: parent.bottom; anchors.bottomMargin: 22
            spacing: 8
            Btn { visible: wz.step < wz.steps - 1; text: Tr.t("Пропустить"); flat: true; onClicked: wz.finish() }
            Btn { visible: wz.step > 0; text: Tr.t("Назад"); onClicked: wz.go(-1) }
            Btn { visible: wz.step < wz.steps - 1; text: Tr.t("Далее"); primary: true; onClicked: wz.go(1) }
        }
    }

    // ---- элементы (inline-компоненты не видят id файла — только Theme/Prefs/свойства) ----
    component Title: Text { color: Theme.text; font.pixelSize: Theme.fs(20); font.bold: true }
    component Label: Text { color: Theme.text; font.pixelSize: Theme.fs(13); Layout.topMargin: 4 }
    component Hint: Text { Layout.fillWidth: true; color: Theme.textMuted; font.pixelSize: Theme.fs(12); wrapMode: Text.WordWrap }
    component Pills: Rectangle {
        id: pl
        property var options: []
        property var current
        signal picked(var value)
        Layout.fillWidth: true
        implicitHeight: 36; radius: height / 2
        color: Theme.surfaceHigh; border.color: Theme.outline
        readonly property real cell: (width - 4) / Math.max(1, options.length)
        readonly property int idx: { for (var i = 0; i < options.length; i++) if (options[i].value === current) return i; return -1 }
        Rectangle {
            visible: pl.idx >= 0
            x: 2 + pl.idx * pl.cell; y: 2
            width: pl.cell; height: parent.height - 4; radius: height / 2
            color: Prefs.accent
            Behavior on x { NumberAnimation { duration: Prefs.ms(220); easing.type: Easing.OutCubic } }
        }
        Row {
            x: 2; y: 2
            Repeater {
                model: pl.options
                delegate: Item {
                    id: po
                    required property var modelData
                    required property int index
                    width: pl.cell; height: pl.height - 4
                    Rectangle {
                        anchors.fill: parent; radius: height / 2
                        visible: po.index !== pl.idx
                        color: poMa.pressed ? Theme.surfacePressed : poMa.containsMouse ? Theme.surfaceHigher : "transparent"
                        Behavior on color { ColorAnimation { duration: Prefs.ms(120) } }
                    }
                    Text {
                        anchors.centerIn: parent
                        text: po.modelData.label
                        color: po.index === pl.idx ? Theme.accentText : Theme.textSecondary
                        font.pixelSize: Theme.fs(13)
                        Behavior on color { ColorAnimation { duration: Prefs.ms(140) } }
                    }
                    MouseArea { id: poMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: pl.picked(po.modelData.value) }
                }
            }
        }
    }
    component Btn: Rectangle {
        id: b
        property string text
        property bool primary: false
        property bool flat: false
        signal clicked()
        implicitWidth: bt.implicitWidth + 32; implicitHeight: 38; radius: Theme.r(19)
        width: implicitWidth; height: implicitHeight
        color: b.primary ? (bMa.pressed ? Theme.accentPressed : bMa.containsMouse ? Theme.accentLight : Prefs.accent)
             : b.flat ? (bMa.pressed ? Theme.surfacePressed : bMa.containsMouse ? Theme.surfaceHigh : "transparent")
             : (bMa.pressed ? Theme.surfacePressed : bMa.containsMouse ? Theme.surfaceHigher : Theme.surfaceHigh)
        scale: bMa.pressed ? 0.95 : 1
        Behavior on color { ColorAnimation { duration: Prefs.ms(120) } }
        Behavior on scale { NumberAnimation { duration: Prefs.ms(140); easing.type: Easing.OutBack } }
        Text { id: bt; anchors.centerIn: parent; text: b.text; font.pixelSize: Theme.fs(13); font.bold: b.primary
               color: b.primary ? Theme.accentText : b.flat ? Theme.textSecondary : Theme.text }
        MouseArea { id: bMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: b.clicked() }
    }
}
