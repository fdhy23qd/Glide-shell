pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Состояние niri для бара и дока: воркспейсы, окна, раскладка — из одного потока событий
// (`niri msg --json event-stream`), плюс поиск .desktop-записи и значка для окна и действия.
Singleton {
    id: niri

    property var workspaces: []
    // монитор в фокусе (имя выхода niri, как у Quickshell screen.name) — туда переезжают остров и панель
    readonly property string focusedOutput: {
        for (var w of workspaces) if (w.is_focused) return w.output || ""
        return ""
    }
    property var windows: ({})
    // раскладка окон (id → layout) — отдельно от windows: сдвиги окон частые, а бар и док от них не зависят
    property var tiles: ({})
    function setTile(id, l) {
        var t = Object.assign({}, tiles)
        if (l) t[id] = l; else delete t[id]
        tiles = t
    }
    property var focusedId: null
    // события окон для плагинов (api.windowOpened…): открыто, заголовок или приложение сменились, закрыто, фокус.
    // Полный список при подключении (WindowsChanged) — не «открылись»: окна были и раньше.
    signal windowOpened(var w)
    signal windowChanged(var w)
    signal windowClosed(var w)
    signal windowFocused(var w)             // null — фокуса нет ни у одного окна
    property var lastFocused: null
    onFocusedIdChanged: Qt.callLater(niri.focusSettled)   // WindowsChanged сначала сбрасывает в null — дождаться итога
    function focusSettled() {
        if (focusedId === lastFocused) return
        lastFocused = focusedId
        windowFocused(focusedId !== null && windows[focusedId] ? Object.assign({}, windows[focusedId]) : null)
    }
    property var layouts: []
    property int layoutIdx: 0

    function niriEvent(e) {
        var m, w
        if (e.WorkspacesChanged) {
            workspaces = e.WorkspacesChanged.workspaces.slice().sort((a, b) => a.idx - b.idx)
        } else if (e.WorkspaceActivated) {
            var a = e.WorkspaceActivated, out = null
            for (w of workspaces) if (w.id === a.id) out = w.output
            workspaces = workspaces.map(x => Object.assign({}, x, {
                is_active: x.output === out ? x.id === a.id : x.is_active,
                is_focused: a.focused ? x.id === a.id : x.is_focused
            }))
        } else if (e.WorkspaceActiveWindowChanged) {
            var c = e.WorkspaceActiveWindowChanged
            workspaces = workspaces.map(x => x.id === c.workspace_id
                                        ? Object.assign({}, x, { active_window_id: c.active_window_id }) : x)
        } else if (e.WorkspaceUrgencyChanged) {
            var u = e.WorkspaceUrgencyChanged
            workspaces = workspaces.map(x => x.id === u.id ? Object.assign({}, x, { is_urgent: u.urgent }) : x)
        } else if (e.WindowsChanged) {
            m = {}
            var t = {}
            focusedId = null   // в фокусе может не быть ни одного окна — не оставлять прежнее
            for (w of e.WindowsChanged.windows) {
                m[w.id] = w
                t[w.id] = w.layout
                if (w.is_focused) focusedId = w.id
            }
            windows = m
            tiles = t
        } else if (e.WindowOpenedOrChanged) {
            w = e.WindowOpenedOrChanged.window
            var was = windows[w.id]
            m = Object.assign({}, windows)
            m[w.id] = w
            windows = m
            setTile(w.id, w.layout)
            if (w.is_focused) focusedId = w.id
            if (!was) windowOpened(Object.assign({}, w))
            else if (was.title !== w.title || was.app_id !== w.app_id) windowChanged(Object.assign({}, w))
        } else if (e.WindowClosed) {
            if (windows[e.WindowClosed.id]) windowClosed(Object.assign({}, windows[e.WindowClosed.id]))
            m = Object.assign({}, windows)
            delete m[e.WindowClosed.id]
            windows = m
            setTile(e.WindowClosed.id, null)
            if (focusedId === e.WindowClosed.id) focusedId = null
        } else if (e.WindowLayoutsChanged) {   // окна сдвинулись или изменили размер (для обоев: закрыты ли они)
            var tt = Object.assign({}, tiles)
            for (var ch of e.WindowLayoutsChanged.changes || []) tt[ch[0]] = ch[1]
            tiles = tt
        } else if (e.WindowFocusChanged) {
            focusedId = e.WindowFocusChanged.id
        } else if (e.KeyboardLayoutsChanged) {
            layouts = e.KeyboardLayoutsChanged.keyboard_layouts.names
            layoutIdx = e.KeyboardLayoutsChanged.keyboard_layouts.current_idx
        } else if (e.KeyboardLayoutSwitched) {
            layoutIdx = e.KeyboardLayoutSwitched.idx
        } else if (e.CastsChanged) {
            casts = e.CastsChanged.casts || []
        } else if (e.CastStartedOrChanged || e.CastStopped) {
            niri.refreshCasts()   // поля этих событий не трогаем — перечитываем список целиком
        }
    }

    // трансляции экрана (демонстрация в звонке, запись через портал): во время них — «не беспокоить»
    property var casts: []
    // событие пришло, пока прошлый запрос ещё идёт, — повторить после него (иначе последнее изменение терялось)
    property bool castsAgain: false
    function refreshCasts() { if (castsProc.running) castsAgain = true; else castsProc.running = true }
    Process {
        id: castsProc
        command: ["niri", "msg", "--json", "casts"]
        stdout: StdioCollector { onStreamFinished: { try { niri.casts = JSON.parse(text) } catch (e) {} } }
        onExited: if (niri.castsAgain) { niri.castsAgain = false; running = true }
    }

    Process {
        id: niriStream
        running: true
        command: ["setpriv", "--pdeathsig", "TERM", "niri", "msg", "--json", "event-stream"]   // умирает вместе с оболочкой
        stdout: SplitParser {
            onRead: (line) => { try { niri.niriEvent(JSON.parse(line)) } catch (e) {} }
        }
        onExited: niriRestart.restart()   // niri перезапустился — переподключаемся
    }
    Timer { id: niriRestart; interval: 2000; onTriggered: niriStream.running = true }


    // Доля монитора, закрытая окнами его видимого стола (0…1): обои под ними не видны — анимацию можно остановить.
    // niri не сообщает, где на экране плиточные окна (tile_pos_in_workspace_view у них null), поэтому оценка:
    // колонки стола (ширина — самая широкая плитка колонки) вместе с промежутками; хватает на ширину монитора —
    // экран заполнен (niri держит видимой колонку в фокусе и прокручивает к ней). Плавающие — по их месту, если есть.
    function coveredShare(output, w, h) {
        if (!output || w <= 0 || h <= 0) return 0
        var ws = workspaces.find(x => x.output === output && x.is_active)
        if (!ws) return 0
        var cols = {}, tallest = 0, floatArea = 0
        for (var id in windows) {
            var win = windows[id], l = tiles[id]
            if (win.workspace_id !== ws.id || !l || !l.tile_size) continue
            if (win.is_floating) {
                var p = l.tile_pos_in_workspace_view
                if (p) floatArea += Math.max(0, Math.min(w, p[0] + l.tile_size[0]) - Math.max(0, p[0]))
                                  * Math.max(0, Math.min(h, p[1] + l.tile_size[1]) - Math.max(0, p[1]))
                continue
            }
            var col = l.pos_in_scrolling_layout ? l.pos_in_scrolling_layout[0] : id
            cols[col] = Math.max(cols[col] || 0, l.tile_size[0])
            tallest = Math.max(tallest, l.tile_size[1])
        }
        var width = 0, n = 0
        for (var k in cols) { width += cols[k]; n++ }
        if (n > 1) width += (n - 1) * 12            // промежутки между колонками
        var tiled = Math.min(1, width / w) * Math.min(1, tallest / (h * 0.92))   // по высоте — без бара и полей
        return Math.min(1, tiled + floatArea / (w * h))
    }

    readonly property var focusedWindow: focusedId !== null && windows[focusedId] ? windows[focusedId] : null

    // ---- окно → приложение ----
    property var entryCache: ({})   // app_id → DesktopEntry (или null): поиск по .desktop недешёвый
    // поставили или удалили приложение — кэш сбрасывается, а привязки (значки бара и дока) пересчитываются:
    // они читают cacheGen через entryFor/iconFor
    property int cacheGen: 0
    Connections {
        target: DesktopEntries.applications
        function onValuesChanged() { niri.entryCache = ({}); niri.iconCache = ({}); niri.cacheGen++ }
    }
    function entryFor(appId) {
        if (!appId || cacheGen < 0) return null
        if (entryCache[appId] !== undefined) return entryCache[appId]
        var e = DesktopEntries.heuristicLookup(appId)
        entryCache[appId] = e || null
        return entryCache[appId]
    }
    property var iconCache: ({})
    function iconFor(appId) {
        if (!appId || cacheGen < 0) return ""
        if (iconCache[appId] !== undefined) return iconCache[appId]
        var e = entryFor(appId)
        var path = Quickshell.iconPath(e && e.icon ? e.icon : appId, true)
                   || Quickshell.iconPath("application-x-executable", true)
        iconCache[appId] = path
        return path
    }

    // ---- действия ----
    // заголовок окна для показа: у приложений, скрытых на записи (Prefs.privacyApps), пока экран пишут или
    // показывают — только имя приложения (в заголовке бывает имя чата, страница, файл)
    function titleFor(w) {
        if (!w) return ""
        if (Notifs.capturing && Prefs.privacyApps.indexOf(w.app_id) >= 0) { var e = entryFor(w.app_id); return (e && e.name) || w.app_id || "" }
        return w.title || ""
    }
    function action(args) { Quickshell.execDetached(["niri", "msg", "action"].concat(args)) }
    function focusWindow(id) { action(["focus-window", "--id", String(id)]) }
    function closeWindow(id) { action(["close-window", "--id", String(id)]) }
}
