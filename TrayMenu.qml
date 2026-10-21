import QtQuick
import Quickshell
import Quickshell.Widgets

// Меню значка трея в стиле Glide: своё окно-попап вместо системного (it.display() требует
// QApplication — это Qt Widgets и лишние мегабайты). Пункты — из DBusMenu через QsMenuOpener;
// подменю открываются на месте («‹ Назад» вверху), щелчок мимо или Esc закрывают меню.
PopupWindow {
    id: tm
    property var stack: []      // путь по подменю: [корень, подменю, …]
    property var owner: null    // значок трея, чьё меню открыто (бар подсвечивает его)
    readonly property var current: stack.length ? stack[stack.length - 1] : null

    grabFocus: true
    color: "transparent"
    // капля под капсулой: окно шире меню на стыки слева и справа и выше на запас отскока
    implicitWidth: attached ? menuW + 2 * fillet + 4 : 264
    implicitHeight: attached ? fullH + 16 : card.height

    // ---- капля: меню свисает из правой капсулы бара (TrayShape — общий контур с баром) ----
    property var cap: null                  // капсула бара, из которой растёт меню
    property bool attached: false           // поместилось под капсулой; иначе — отдельной карточкой
    readonly property int fillet: 12
    property real menuW: 264
    readonly property real offR: cap ? Math.min(cap.radius, cap.height / 2) + fillet : 0   // от правого края капсулы до меню
    // полная высота содержимого; экран низкий (768) — длинное меню (nm-applet) с прокруткой
    readonly property real fullH: Math.min(col.implicitHeight, (screen ? screen.height : 768) - 120) + 12
    property real shownH: fullH             // подменю другой высоты — капля плавно тянется
    Behavior on shownH { enabled: tm.openT >= 1; NumberAnimation { duration: Prefs.ms(180); easing.type: Easing.OutCubic } }
    property real openT: 0                  // 0 — только капсула, 1 — меню раскрыто
    readonly property real dropH: shownH * openT
    property real popLeft: 0                // левый край окна меню в координатах бара (на момент открытия)

    NumberAnimation {
        id: pour
        target: tm; property: "openT"; to: 1
        duration: Prefs.ms(300); easing.type: Easing.OutBack; easing.overshoot: 0.9
    }
    NumberAnimation {
        id: drain
        target: tm; property: "openT"; to: 0
        duration: Prefs.ms(170); easing.type: Easing.InCubic
        onFinished: if (tm.closing) { tm.closing = false; tm.visible = false }
    }
    property bool closing: false

    // win — окно бара, (x, y) — правый нижний угол значка в его координатах (для отдельной карточки);
    // capItem — капсула, из которой вытекает меню. grab: false — для IPC: захват попапа Wayland даёт
    // только после ввода в родительском окне
    function openFor(trayItem, win, x, y, grab, capItem) {
        if (!trayItem || !trayItem.menu) return
        drain.stop(); closing = false
        grabFocus = grab !== false
        anchor.window = win
        cap = capItem || null
        var room = cap ? cap.width - 2 * offR : 0
        menuW = Math.min(264, room)
        attached = !!cap && menuW >= 200
        if (attached) {
            var capRight = cap.x + cap.width
            popLeft = capRight - offR - menuW - fillet - 2
            anchor.edges = Edges.Top | Edges.Left
            anchor.gravity = Edges.Bottom | Edges.Right
            anchor.rect.x = popLeft; anchor.rect.y = cap.y + cap.height
        } else {
            anchor.edges = Edges.Bottom | Edges.Right
            anchor.gravity = Edges.Bottom | Edges.Left
            anchor.rect.x = x; anchor.rect.y = y
        }
        anchor.rect.width = 1; anchor.rect.height = 1
        owner = trayItem
        stack = [trayItem.menu]
        visible = true
        if (attached) { openT = 0; pour.restart() }
        else { openT = 1; appear.restart() }
    }
    function close() {
        if (attached && visible && Prefs.anim > 0) { closing = true; pour.stop(); drain.restart() }
        else visible = false
    }
    onVisibleChanged: if (!visible) {
        stack = []; owner = null
        if (attached && openT > 0 && !drain.running) drain.restart()   // закрыли щелчком мимо — втянуть стык в баре
    }
    // появление отдельной карточки: проявляется и чуть вырастает от угла значка; подменю — сдвигом содержимого
    ParallelAnimation {
        id: appear
        NumberAnimation { target: card; property: "opacity"; from: 0; to: 1; duration: Prefs.ms(120) }
        NumberAnimation { target: card; property: "scale"; from: 0.94; to: 1; duration: Prefs.ms(180); easing.type: Easing.OutCubic }
    }
    ParallelAnimation {
        id: subAppear
        property real dir: 1
        NumberAnimation { target: col; property: "opacity"; from: 0; to: 1; duration: Prefs.ms(140) }
        NumberAnimation { target: col; property: "x"; from: 16 * subAppear.dir; to: 0; duration: Prefs.ms(180); easing.type: Easing.OutCubic }
    }
    property int depth: 0
    onStackChanged: {
        if (visible && depth > 0 && stack.length > 0) { subAppear.dir = stack.length > depth ? 1 : -1; subAppear.restart() }
        depth = stack.length
    }

    // «_Файл» → «Файл» (мнемоники DBusMenu), «__» — настоящее подчёркивание
    function label(t) { return (t || "").replace(/__/g, "\u0000").replace(/_/g, "").replace(/\u0000/g, "_") }

    QsMenuOpener { id: opener; menu: tm.current }

    // общий с баром контур: капсула (вне окна, выше его верха) + свисающее меню
    TrayShape {
        visible: tm.attached && !!tm.cap
        x: tm.cap ? tm.cap.x - tm.popLeft : 0
        y: tm.cap ? -tm.cap.height : 0
        capW: tm.cap ? tm.cap.width : 0
        capH: tm.cap ? tm.cap.height : 0
        capR: tm.cap ? tm.cap.radius : 0
        menuR: capW - tm.offR
        menuL: menuR - tm.menuW
        menuH: tm.dropH
        fillet: tm.fillet * Math.min(1, tm.openT * 1.5)
        menuRadius: Theme.radiusMd
    }

    Rectangle {
        id: card
        x: tm.attached ? tm.fillet + 2 : 0
        width: tm.attached ? tm.menuW : tm.implicitWidth
        height: tm.attached ? Math.max(0, tm.dropH) : tm.fullH
        clip: tm.attached
        radius: Theme.radiusMd
        // в капле фон и обводку рисует контур; содержимое проявляется, когда капля почти налилась
        color: tm.attached ? "transparent" : Theme.background
        border.color: tm.attached ? "transparent" : Theme.outline
        transformOrigin: Item.TopRight
        focus: true
        Keys.onEscapePressed: tm.stack.length > 1 ? tm.stack = tm.stack.slice(0, -1) : tm.close()

        Flickable {
            x: 6; y: 6
            width: parent.width - 12; height: tm.fullH - 12   // не сжимается вместе с каплей — она его обрезает
            opacity: tm.attached ? Math.max(0, Math.min(1, (tm.openT - 0.35) / 0.5)) : 1
            contentHeight: col.implicitHeight
            interactive: contentHeight > height
            boundsBehavior: Flickable.StopAtBounds
            clip: true
        Column {
            id: col
            width: parent.width
            spacing: 1

            Row_ {
                visible: tm.stack.length > 1
                width: col.width
                glyph: String.fromCodePoint(0xF0141)   // chevron-left
                text: Tr.t("Назад")
                tint: Theme.textVariant
                onClicked: tm.stack = tm.stack.slice(0, -1)
            }
            Rectangle { visible: tm.stack.length > 1; width: col.width; height: 1; color: Theme.outline }

            Repeater {
                model: opener.children
                delegate: Item {
                    id: d
                    required property var modelData
                    width: col.width
                    height: modelData.isSeparator ? 9 : 32
                    Rectangle {
                        visible: d.modelData.isSeparator
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width; height: 1; color: Theme.outline
                    }
                    Row_ {
                        visible: !d.modelData.isSeparator
                        width: parent.width
                        enabled: d.modelData.enabled
                        text: tm.label(d.modelData.text)
                        icon: d.modelData.icon
                        // галочка / переключатель: отмеченный — заполненный значок акцентом
                        glyph: d.modelData.buttonType === QsMenuButtonType.CheckBox
                                   ? String.fromCodePoint(d.modelData.checkState === Qt.Checked ? 0xF0132 : 0xF0131)
                             : d.modelData.buttonType === QsMenuButtonType.RadioButton
                                   ? String.fromCodePoint(d.modelData.checkState === Qt.Checked ? 0xF043E : 0xF043D)
                             : ""
                        checked: d.modelData.buttonType !== QsMenuButtonType.None && d.modelData.checkState === Qt.Checked
                        more: d.modelData.hasChildren
                        onClicked: {
                            if (d.modelData.hasChildren) { tm.stack = tm.stack.concat([d.modelData]); return }
                            d.modelData.triggered()
                            tm.close()
                        }
                    }
                }
            }
        }
        }
    }

    component Row_: Rectangle {
        id: r
        property string text
        property string glyph
        property string icon
        property bool checked: false
        property bool more: false
        property color tint: Theme.text
        signal clicked()
        height: 32
        radius: Theme.radiusSm
        opacity: enabled ? 1 : 0.4
        color: rm.pressed ? Theme.surfaceHigher : rm.containsMouse ? Theme.surfaceHigh : "transparent"
        Behavior on color { ColorAnimation { duration: Prefs.ms(120) } }
        IconImage {
            visible: r.icon !== "" && r.glyph === ""
            x: 10; anchors.verticalCenter: parent.verticalCenter
            implicitSize: 16
            source: r.icon
        }
        Text {
            visible: r.glyph !== ""
            x: 10; anchors.verticalCenter: parent.verticalCenter
            text: r.glyph
            color: r.checked ? Prefs.accent : r.tint
            font.family: Prefs.iconFont; font.pixelSize: Theme.fs(15)
        }
        Text {
            x: 34; width: parent.width - x - (r.more ? 28 : 10)
            anchors.verticalCenter: parent.verticalCenter
            text: r.text; color: r.tint
            font.pixelSize: Theme.fs(12); elide: Text.ElideRight
        }
        Text {
            visible: r.more
            anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
            text: String.fromCodePoint(0xF0142)   // chevron-right
            color: Theme.textVariant
            font.family: Prefs.iconFont; font.pixelSize: Theme.fs(15)
        }
        MouseArea {
            id: rm
            anchors.fill: parent
            hoverEnabled: true
            enabled: r.enabled
            cursorShape: Qt.PointingHandCursor
            onClicked: r.clicked()
        }
    }
}
