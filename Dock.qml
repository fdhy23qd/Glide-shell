import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets

// Док внизу экрана: закреплённые и запущенные приложения.
// Левый клик — запустить / перейти к окну (повторный перебирает окна), средний — новое окно,
// правый — меню (окна приложения, закрепить, сдвинуть, закрыть). Колесо над значком листает окна.
PanelWindow {
    id: dock
    required property var panel
    readonly property var p: panel
    readonly property int s: Prefs.dockIcon                  // размер значка
    readonly property int bodyH: s + 22

    visible: Prefs.dock
    anchors { bottom: true; left: true; right: true }
    implicitHeight: 380                                      // запас сверху под меню; мышь ловит только mask
    exclusionMode: Prefs.dockMode === "always" ? ExclusionMode.Normal : ExclusionMode.Ignore
    exclusiveZone: Prefs.dockMode === "always" ? bodyH + 12 : 0
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    WlrLayershell.namespace: "glide-dock"
    color: "transparent"
    mask: Region {
        item: dock.revealed ? body : trigger
        Region { item: menu.visible ? menu : null }
    }

    component MenuItem: Rectangle {
        id: mi
        property string text
        property string glyph
        property color tint: Theme.text
        signal clicked()
        width: 248; height: 32; radius: Theme.radiusSm
        color: mim.pressed ? Theme.surfaceHigher : mim.containsMouse ? Theme.surfaceHigh : "transparent"
        Behavior on color { ColorAnimation { duration: Prefs.ms(120) } }
        Text { x: 10; anchors.verticalCenter: parent.verticalCenter; text: mi.glyph; color: mi.tint
               font.family: Prefs.iconFont; font.pixelSize: Theme.fs(15) }
        Text { x: 34; width: parent.width - 42; anchors.verticalCenter: parent.verticalCenter
               text: mi.text; color: mi.tint; font.pixelSize: Theme.fs(12); elide: Text.ElideRight }
        MouseArea { id: mim; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                    onClicked: mi.clicked() }
    }

    // ---------- показ ----------
    // «пустой воркспейс» — свой у каждого монитора: док смотрит на активный стол своего экрана
    readonly property bool multi: Quickshell.screens.length > 1
    readonly property var activeWs: multi && screen ? Niri.workspaces.find(w => w.is_active && w.output === screen.name) || null
                                                    : Niri.workspaces.find(w => w.is_focused) || null
    readonly property bool emptyWs: {
        if (!activeWs) return false
        for (var id in Niri.windows) if (Niri.windows[id].workspace_id === activeWs.id) return false
        return true
    }
    property bool hot: false                                 // мышь над доком (уход — с задержкой)
    readonly property bool revealed: Prefs.dockMode === "always" || hot || menu.open || launching !== ""
                                     || (Prefs.dockMode === "smart" && emptyWs)
    Timer { id: hideDelay; interval: 600; onTriggered: dock.hot = false }

    // ---------- приложения ----------
    function keyFor(appId) { var e = Niri.entryFor(appId); return e ? e.id : appId }
    function entryFor(key) { return DesktopEntries.byId(key) || Niri.entryFor(key) }
    function nameFor(key) { var e = entryFor(key); return e ? e.name : key }
    function iconFor(key) {
        var e = entryFor(key)
        return Quickshell.iconPath(e && e.icon ? e.icon : key, "application-x-executable")
    }
    function windowsOf(key) {   // окна приложения по порядку открытия
        var out = []
        for (var id in Niri.windows) if (keyFor(Niri.windows[id].app_id) === key) out.push(Niri.windows[id])
        return out.sort((a, b) => a.id - b.id)
    }

    // закреплённые — первыми, затем запущенные. ListModel правится на месте и только когда меняется
    // состав: смена заголовков окон (частое событие) ничего не пересобирает
    readonly property string itemsSig: {
        var pinned = Prefs.dockPinned || [], seen = {}, out = []
        var focusedKey = Niri.focusedWindow ? keyFor(Niri.focusedWindow.app_id) : ""
        var groups = {}
        for (var id in Niri.windows) {
            var k = keyFor(Niri.windows[id].app_id)
            if (!k) continue
            groups[k] = (groups[k] || 0) + 1
        }
        for (var i = 0; i < pinned.length; i++) {
            seen[pinned[i]] = true
            out.push({ key: pinned[i], pinned: true, count: groups[pinned[i]] || 0, focused: pinned[i] === focusedKey })
        }
        var running = Object.keys(groups).filter(k => !seen[k]).sort()
        for (i = 0; i < running.length; i++)
            out.push({ key: running[i], pinned: false, count: groups[running[i]], focused: running[i] === focusedKey })
        return JSON.stringify(out)
    }
    onItemsSigChanged: {
        var arr = JSON.parse(itemsSig)
        for (var i = 0; i < arr.length; i++) {
            if (i < items.count) items.set(i, arr[i]); else items.append(arr[i])
        }
        if (items.count > arr.length) items.remove(arr.length, items.count - arr.length)
        if (launching && arr.some(x => x.key === launching && x.count > 0)) launching = ""
    }
    ListModel { id: items }

    // ---------- действия ----------
    property string launching: ""                           // значок прыгает, пока не появится окно
    Timer { id: launchTimeout; interval: 8000; onTriggered: dock.launching = "" }
    function launch(key) {
        var e = entryFor(key)
        if (!e) return
        launching = key
        launchTimeout.restart()
        p.launchApp(e)
    }
    function activate(key) {
        var ws = windowsOf(key)
        if (!ws.length) { launch(key); return }
        var f = Niri.focusedWindow
        if (f && keyFor(f.app_id) === key) {   // уже в фокусе — следующее окно приложения
            var i = ws.findIndex(w => w.id === f.id)
            Niri.focusWindow(ws[(i + 1) % ws.length].id)
            return
        }
        // последнее окно, бывшее в фокусе
        function t(w) { var ts = w.focus_timestamp; return ts ? ts.secs * 1e9 + ts.nanos : 0 }
        ws.sort((a, b) => t(b) - t(a))
        Niri.focusWindow(ws[0].id)
    }
    function cycle(key, dir) {
        var ws = windowsOf(key)
        if (!ws.length) return
        var f = Niri.focusedWindow
        var i = f ? ws.findIndex(w => w.id === f.id) : -1
        Niri.focusWindow(ws[(i + dir + ws.length) % ws.length].id)
    }
    function setPinned(list) { Prefs.set("dockPinned", list) }
    function togglePin(key) {
        var l = (Prefs.dockPinned || []).slice(), i = l.indexOf(key)
        if (i >= 0) l.splice(i, 1); else l.push(key)
        setPinned(l)
    }
    function movePin(key, d) {
        var l = (Prefs.dockPinned || []).slice(), i = l.indexOf(key), j = i + d
        if (i < 0 || j < 0 || j >= l.length) return
        l[i] = l[j]; l[j] = key
        setPinned(l)
    }

    // первый запуск: закреплённые берём из дока DMS
    FileView {
        path: Prefs.dockPinned === null && Object.keys(Prefs.data).length
              ? (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/DankMaterialShell/session.json" : ""
        printErrors: false
        onLoaded: {
            try { var l = JSON.parse(text()).pinnedApps } catch (e) {}
            dock.setPinned(Array.isArray(l) ? l : [])
        }
        onLoadFailed: dock.setPinned([])
    }

    // ---------- зона вызова (док спрятан) ----------
    Item {
        id: trigger
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        width: body.width
        height: 4
        HoverHandler {   // наведение на нижний край экрана, пока док спрятан
            onHoveredChanged: if (hovered) { hideDelay.stop(); dock.hot = true }
        }
    }

    // ---------- тело дока ----------
    Rectangle {
        id: body
        anchors.horizontalCenter: parent.horizontalCenter
        y: dock.height - (dock.revealed ? height + 8 : -4)
        width: row.implicitWidth + 16
        height: dock.bodyH
        radius: Theme.radiusLg
        // фон и обводку рисует контур: из него вверх вытекает меню приложения (одно окно — без стыков)
        color: "transparent"
        opacity: dock.revealed ? 1 : 0
        TrayShape {
            capW: body.width; capH: body.height; capR: body.radius
            menuL: menu.menuL; menuR: menu.menuL + menu.width
            menuH: menu.attached ? menu.dropH : 0
            fillet: menu.attached ? menu.fillet * Math.min(1, menu.openT * 1.5) : 0
            menuRadius: Theme.radiusMd
            // отражение по вертикали: «свисающее» меню TrayShape оказывается над доком
            transform: Scale { yScale: -1; origin.y: body.height / 2 }
        }
        Behavior on y { enabled: Prefs.anim > 0; Spring { bounce: 0.22; speed: 1.1 } }
        Behavior on width { enabled: Prefs.anim > 0; Spring { bounce: 0.2; speed: 1.3 } }
        Behavior on opacity { NumberAnimation { duration: Prefs.ms(180) } }

        Row {
            id: row
            anchors.centerIn: parent
            spacing: 2

            // «Приложения»
            Rectangle {
                visible: Prefs.dockButtons
                width: dock.s + 8; height: dock.s + 8; radius: Theme.radiusMd
                anchors.verticalCenter: parent.verticalCenter
                color: appsMa.pressed ? Theme.surfaceHigher : appsMa.containsMouse ? Theme.surfaceHigh : "transparent"
                scale: appsMa.pressed ? 0.9 : 1
                Behavior on color { ColorAnimation { duration: Prefs.ms(120) } }
                Behavior on scale { NumberAnimation { duration: Prefs.ms(140); easing.type: Easing.OutBack } }
                Text {
                    anchors.centerIn: parent
                    text: String.fromCodePoint(0xF003B)
                    color: Theme.textVariant
                    font.family: Prefs.iconFont; font.pixelSize: dock.s * 0.55
                }
                MouseArea { id: appsMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: dock.p.openCategory("apps") }
            }
            Rectangle {
                visible: Prefs.dockButtons && items.count > 0
                width: 1; height: dock.s * 0.7; color: Theme.outline
                anchors.verticalCenter: parent.verticalCenter
            }

            Repeater {
                id: cells
                model: items
                delegate: Item {
                    id: cell
                    Behavior on width { NumberAnimation { duration: Prefs.ms(200); easing.type: Easing.OutCubic } }
                    required property int index
                    required property string key
                    required property bool pinned
                    required property int count
                    required property bool focused
                    // перед первым незакреплённым — разделитель
                    readonly property bool firstRunning: !pinned && index > 0 && items.get(index - 1).pinned
                    width: dock.s + 12 + (firstRunning ? 9 : 0)
                    height: dock.bodyH

                    Rectangle {
                        visible: cell.firstRunning
                        x: 2; anchors.verticalCenter: parent.verticalCenter
                        width: 1; height: dock.s * 0.7; color: Theme.outline
                    }

                    Item {
                        id: slot
                        Behavior on x { NumberAnimation { duration: Prefs.ms(200); easing.type: Easing.OutCubic } }
                        x: cell.firstRunning ? 9 : 0
                        width: dock.s + 12; height: parent.height
                        readonly property bool hovered: cellMa.containsMouse

                        IconImage {
                            id: icon
                            anchors.horizontalCenter: parent.horizontalCenter
                            y: 6
                            implicitSize: dock.s
                            source: dock.iconFor(cell.key)
                            scale: cellMa.pressed ? 0.88 : (slot.hovered ? 1.12 : 1)
                            transformOrigin: Item.Bottom
                            Behavior on scale { enabled: Prefs.anim > 0; Spring { bounce: 0.4; speed: 1.6 } }
                            SequentialAnimation on y {   // запуск: значок подпрыгивает, пока не откроется окно
                                running: dock.launching === cell.key
                                loops: Animation.Infinite
                                alwaysRunToEnd: true
                                NumberAnimation { to: -4; duration: 260; easing.type: Easing.OutQuad }
                                NumberAnimation { to: 6; duration: 300; easing.type: Easing.OutBounce }
                            }
                        }
                        Rectangle {   // окон больше одного — число
                            visible: cell.count > 1
                            x: icon.x + icon.width - width / 2 - 2; y: 3
                            width: Math.max(16, cnt.implicitWidth + 8); height: 16; radius: Theme.r(8)
                            color: Prefs.accent
                            Text { id: cnt; anchors.centerIn: parent; text: cell.count; color: Theme.accentText
                                   font.pixelSize: Theme.fs(10); font.bold: true }
                        }
                        Rectangle {   // индикатор: открыто — точка, в фокусе — вытянутая
                            Behavior on color { ColorAnimation { duration: Prefs.ms(140) } }
                            anchors.horizontalCenter: parent.horizontalCenter
                            y: parent.height - 8
                            height: 4; radius: Theme.r(2)
                            width: cell.focused ? 16 : (cell.count > 0 ? 5 : 0)
                            color: cell.focused ? Prefs.accent : Theme.textSecondary
                            opacity: cell.count > 0 ? 1 : 0
                            Behavior on width { enabled: Prefs.anim > 0; Spring { bounce: 0.3; speed: 1.5 } }
                            Behavior on opacity { NumberAnimation { duration: Prefs.ms(150) } }
                        }

                        MouseArea {
                            id: cellMa
                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                            cursorShape: Qt.PointingHandCursor
                            onClicked: (m) => {
                                if (m.button === Qt.RightButton) menu.openFor(cell.key, slot)
                                else if (m.button === Qt.MiddleButton) dock.launch(cell.key)
                                else { menu.close(); dock.activate(cell.key) }
                            }
                            onWheel: (w) => dock.cycle(cell.key, w.angleDelta.y < 0 ? 1 : -1)
                        }

                        Rectangle {   // подсказка с названием: проявляется и чуть всплывает
                            readonly property bool on: slot.hovered && !menu.open
                            opacity: on ? 1 : 0
                            visible: opacity > 0
                            Behavior on opacity { NumberAnimation { duration: Prefs.ms(120) } }
                            anchors.horizontalCenter: parent.horizontalCenter
                            y: -height - (on ? 8 : 4)
                            Behavior on y { NumberAnimation { duration: Prefs.ms(160); easing.type: Easing.OutCubic } }
                            width: tip.implicitWidth + 16; height: 26; radius: Theme.r(13)
                            color: Theme.surfaceHigh
                            border.color: Theme.outline
                            Text {
                                id: tip; anchors.centerIn: parent
                                text: dock.nameFor(cell.key) + (cell.count > 1 ? "  ·  " + cell.count + Tr.t(" окна") : "")
                                color: Theme.text; font.pixelSize: Theme.fs(12)
                            }
                        }
                    }
                }
            }

            // «Обзор» niri
            Rectangle {
                visible: Prefs.dockButtons
                width: dock.s + 8; height: dock.s + 8; radius: Theme.radiusMd
                anchors.verticalCenter: parent.verticalCenter
                color: ovMa.pressed ? Theme.surfaceHigher : ovMa.containsMouse ? Theme.surfaceHigh : "transparent"
                scale: ovMa.pressed ? 0.9 : 1
                Behavior on color { ColorAnimation { duration: Prefs.ms(120) } }
                Behavior on scale { NumberAnimation { duration: Prefs.ms(140); easing.type: Easing.OutBack } }
                Text {
                    anchors.centerIn: parent
                    text: String.fromCodePoint(0xF056E)
                    color: Theme.textVariant
                    font.family: Prefs.iconFont; font.pixelSize: dock.s * 0.55
                }
                MouseArea { id: ovMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: Niri.action(["toggle-overview"]) }
            }
        }

        HoverHandler {
            onHoveredChanged: {
                if (hovered) { hideDelay.stop(); dock.hot = true }
                else hideDelay.restart()
            }
        }
    }

    // IPC panel dockMenu КЛЮЧ: открыть меню значка без щелчка (проверка); "" — закрыть
    function menuFor(key) {
        if (key === "") { menu.close(); return "closed" }
        for (var i = 0; i < cells.count; i++) {
            var it = cells.itemAt(i)
            if (it && it.key === key) { hot = true; menu.openFor(key, it); return "ok" }
        }
        var keys = []
        for (i = 0; i < items.count; i++) keys.push(items.get(i).key)
        return keys.join(" ")
    }

    // ---------- меню приложения ----------
    Rectangle {
        id: menu
        property string key: ""
        property var wins: []
        property bool open: false
        // капля: меню поднимается из дока; не помещается над ним (мало значков) — отдельная карточка
        property bool attached: false
        readonly property int fillet: 12
        property real menuL: 0                       // левый край меню от левого края дока
        readonly property real fullH: menuCol.implicitHeight + 12
        property real openT: 0
        readonly property real dropH: fullH * openT
        visible: attached ? openT > 0.001 : open
        width: 260
        height: attached ? dropH : fullH
        clip: attached
        radius: Theme.radiusMd
        color: attached ? "transparent" : Theme.background
        border.color: attached ? "transparent" : Theme.outline
        x: attached ? body.x + menuL : cardX
        y: attached ? body.y - dropH : body.y - height - 8
        property real cardX: 0

        NumberAnimation { id: pour; target: menu; property: "openT"; to: 1; duration: Prefs.ms(300); easing.type: Easing.OutBack; easing.overshoot: 0.9 }
        NumberAnimation { id: drain; target: menu; property: "openT"; to: 0; duration: Prefs.ms(170); easing.type: Easing.InCubic }

        function openFor(k, anchorItem) {
            key = k
            wins = dock.windowsOf(k)
            var r = Math.min(body.radius, body.height / 2)
            var c = anchorItem.mapToItem(body, anchorItem.width / 2, 0).x
            attached = body.width - 2 * (r + fillet) >= width
            menuL = Math.max(r + fillet, Math.min(body.width - r - fillet - width, c - width / 2))
            var pt = anchorItem.mapToItem(dock.contentItem, anchorItem.width / 2, 0)
            cardX = Math.max(8, Math.min(dock.width - width - 8, pt.x - width / 2))
            open = true
            menuHold.stop()
            drain.stop()
            if (attached) pour.restart(); else openT = 1
        }
        function close() {
            open = false
            pour.stop()
            if (attached) drain.restart(); else openT = 0
        }
        readonly property bool isPinned: (Prefs.dockPinned || []).indexOf(key) >= 0

        HoverHandler {   // ушли с меню — закрыть через секунду
            onHoveredChanged: hovered ? menuHold.stop() : menuHold.restart()
        }
        Timer { id: menuHold; interval: 1000; onTriggered: menu.close() }

        Column {
            id: menuCol
            x: 6
            // в капле содержимое стоит на своём конечном месте, а капля, поднимаясь, открывает его снизу
            y: menu.attached ? menu.dropH - menu.fullH + 6 : 6
            opacity: menu.attached ? Math.max(0, Math.min(1, (menu.openT - 0.35) / 0.5)) : 1
            spacing: 1
            Text {
                x: 10; height: 26
                verticalAlignment: Text.AlignVCenter
                text: dock.nameFor(menu.key)
                color: Theme.textSecondary; font.pixelSize: Theme.fs(11); font.bold: true
            }
            Repeater {   // окна приложения: клик — перейти
                model: menu.wins.slice(0, 8)
                delegate: MenuItem {
                    required property var modelData
                    glyph: String.fromCodePoint(0xF05AF)
                    text: (Niri.windows[modelData.id] || modelData).title || Tr.t("окно")
                    onClicked: { Niri.focusWindow(modelData.id); menu.close() }
                }
            }
            Rectangle { visible: menu.wins.length > 0; width: 248; height: 1; color: Theme.outline }
            MenuItem {
                visible: !!dock.entryFor(menu.key)
                glyph: String.fromCodePoint(0xF0415); text: Tr.t("Новое окно")
                onClicked: { dock.launch(menu.key); menu.close() }
            }
            MenuItem {
                glyph: String.fromCodePoint(menu.isPinned ? 0xF0931 : 0xF0403)
                text: menu.isPinned ? Tr.t("Открепить") : Tr.t("Закрепить")
                onClicked: { dock.togglePin(menu.key); menu.close() }
            }
            MenuItem {
                visible: menu.isPinned && (Prefs.dockPinned || []).indexOf(menu.key) > 0
                glyph: String.fromCodePoint(0xF004D); text: Tr.t("Сдвинуть влево")
                onClicked: dock.movePin(menu.key, -1)
            }
            MenuItem {
                visible: menu.isPinned && (Prefs.dockPinned || []).indexOf(menu.key) < (Prefs.dockPinned || []).length - 1
                glyph: String.fromCodePoint(0xF0054); text: Tr.t("Сдвинуть вправо")
                onClicked: dock.movePin(menu.key, 1)
            }
            MenuItem {
                visible: menu.wins.length > 0
                glyph: String.fromCodePoint(0xF0156); tint: Theme.error
                text: menu.wins.length > 1 ? Tr.t("Закрыть все окна (") + menu.wins.length + ")" : Tr.t("Закрыть окно")
                onClicked: { for (var w of menu.wins) Niri.closeWindow(w.id); menu.close() }
            }
        }
    }
}
