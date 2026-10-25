import QtQuick
import Quickshell

// Капля из капсулы бара: подсказки по наведению и списки по щелчку (окна). Как меню трея: общий с
// капсулой контур TrayShape — бар рисует верх, это окно — всё ниже капсулы, шов встык.
// Содержимое — дочерние элементы; ширина капли задаётся при открытии (окно попапа потом не двигается),
// высота следует за содержимым.
PopupWindow {
    id: cd
    default property alias content: holder.data
    property var cap: null                  // капсула, из которой растёт капля
    property string key: ""                 // что показывается (бар выбирает содержимое по ключу)
    property bool attached: false
    readonly property int fillet: 12
    property real menuW: 240
    property real menuL: 0                  // левый край капли от левого края капсулы
    property real contentH: 0               // высота содержимого (задаёт бар)
    readonly property real fullH: contentH + 16
    property real shownH: fullH
    Behavior on shownH { enabled: cd.openT >= 1; NumberAnimation { duration: Prefs.ms(180); easing.type: Easing.OutCubic } }
    property real openT: 0
    readonly property real dropH: shownH * openT
    readonly property bool hovered: hover.hovered
    property real popLeft: 0
    property bool closing: false

    color: "transparent"
    implicitWidth: menuW + 2 * fillet + 4
    implicitHeight: Math.max(1, fullH + 16)

    NumberAnimation {
        id: pour
        target: cd; property: "openT"; to: 1
        duration: Prefs.ms(280); easing.type: Easing.OutBack; easing.overshoot: 0.8
    }
    NumberAnimation {
        id: drain
        target: cd; property: "openT"; to: 0
        duration: Prefs.ms(150); easing.type: Easing.InCubic
        onFinished: {
            if (!cd.closing) return
            cd.closing = false; cd.visible = false; cd.key = ""
            if (cd.pending) { var a = cd.pending; cd.pending = null; cd.show(a[0], a[1], a[2], a[3], a[4], a[5], a[6]) }
        }
    }

    // win — окно бара, capItem — капсула, cx — центр капли (от левого края капсулы), w — ширина,
    // src — значок, под которым капля (по нему она пересчитывает место, когда капсула сдвигается)
    property var pending: null              // открыть другую каплю, когда эта втянется
    property var src: null
    property real cx: 0
    function show(k, win, capItem, cx, w, grab, src) {
        if (visible && key !== "" && key !== k && Prefs.anim > 0) {   // переход к соседней капсуле: втянуть и налить заново
            pending = [k, win, capItem, cx, w, grab, src]
            if (!closing) { closing = true; pour.stop(); drain.restart() }
            return true
        }
        if (visible && key === k) { pending = null; if (closing) { closing = false; drain.stop(); pour.restart() } return true }
        pending = null
        drain.stop(); closing = false
        var r = Math.min(capItem.radius, capItem.height / 2)
        var fits = capItem.width - 2 * (r + fillet) >= w
        // не помещается под капсулой — сужаем до доступного (но не уже 180), иначе отказ
        menuW = fits ? w : Math.max(180, capItem.width - 2 * (r + fillet))
        if (capItem.width - 2 * (r + fillet) < menuW) { hide(); return false }
        attached = true
        cd.src = src || null
        cd.cx = cx
        menuL = Math.max(r + fillet, Math.min(capItem.width - r - fillet - menuW, cx - menuW / 2))
        cap = capItem
        key = k
        grabFocus = !!grab
        anchor.window = win
        popLeft = capItem.x + menuL - fillet - 2
        anchor.edges = Edges.Top | Edges.Left
        anchor.gravity = Edges.Bottom | Edges.Right
        anchor.rect.x = popLeft; anchor.rect.y = capItem.y + capItem.height
        anchor.rect.width = 1; anchor.rect.height = 1
        openT = 0
        visible = true
        pour.restart()
        return true
    }
    // капсула сдвинулась или изменила ширину (остров, содержимое) — попап и текст едут вместе с контуром,
    // иначе контур уезжал из окна попапа и обрезался, а текст оставался на старом месте
    function relayout() {
        if (!visible || !cap) return
        if (src && src.visible) cx = src.mapToItem(cap, src.width / 2, 0).x
        var r = Math.min(cap.radius, cap.height / 2)
        menuL = Math.max(r + fillet, Math.min(cap.width - r - fillet - menuW, cx - menuW / 2))
        var pl = cap.x + menuL - fillet - 2
        if (pl === popLeft) return
        popLeft = pl
        anchor.rect.x = pl; anchor.rect.y = cap.y + cap.height
        anchor.updateAnchor()
    }
    Connections {
        target: cd.cap
        function onXChanged() { cd.relayout() }
        function onWidthChanged() { cd.relayout() }
    }
    function hide() {
        pending = null
        if (!visible) { key = ""; openT = 0; return }
        if (Prefs.anim > 0) { closing = true; pour.stop(); drain.restart() }
        else { visible = false; key = ""; openT = 0 }
    }
    onVisibleChanged: if (!visible && !closing) {   // закрыли щелчком мимо — втянуть стык в баре
        key = ""
        if (openT > 0 && !drain.running) drain.restart()
    }

    TrayShape {
        visible: !!cd.cap
        x: cd.cap ? cd.cap.x - cd.popLeft : 0
        y: cd.cap ? -cd.cap.height : 0
        capW: cd.cap ? cd.cap.width : 0
        capH: cd.cap ? cd.cap.height : 0
        capR: cd.cap ? cd.cap.radius : 0
        menuL: cd.menuL
        menuR: cd.menuL + cd.menuW
        menuH: cd.dropH
        fillet: cd.fillet * Math.min(1, cd.openT * 1.5)
        menuRadius: Theme.radiusMd
    }
    Item {
        x: cd.fillet + 2
        width: cd.menuW
        height: Math.max(0, cd.dropH)
        clip: true
        HoverHandler { id: hover }
        Item {
            id: holder
            x: 10; y: 8
            width: cd.menuW - 20
            height: cd.contentH
            opacity: Math.max(0, Math.min(1, (cd.openT - 0.35) / 0.5))
        }
    }
}
