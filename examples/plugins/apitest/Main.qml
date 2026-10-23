import QtQuick
import QtQuick.Layouts
import qs

// Проверка API: каждая функция api — строкой с результатом. Выключай разрешения в «Настройки» → «Плагины»
// и жми «Проверить всё»: строки с этим разрешением должны стать ✗ («нет разрешения»), остальные — остаться ✓.
ColumnLayout {
    id: root
    property var api
    spacing: 8

    property var results: ({})          // key → {ok: true|false|null (идёт), detail}
    property int notifSeen: 0           // сколько уведомлений пришло через событие (разрешение notifications)
    property int themeEvents: 0

    function set(key, ok, detail) {
        var r = Object.assign({}, results); r[key] = { ok: ok, detail: String(detail || "") }; results = r
        var vals = Object.keys(r).map(k => r[k]).filter(x => x.ok !== null)
        if (api) api.storage.set("summary", { ok: vals.filter(x => x.ok).length, fail: vals.filter(x => !x.ok).length })
    }
    function has(p) { return api && api.permissions.has(p) }

    Connections {
        target: root.api
        ignoreUnknownSignals: true
        function onNotification(e) { root.notifSeen++ }
        function onThemeUpdated() { root.themeEvents++ }
        function onPermissionsUpdated() { root.runAll() }
    }

    // ---- проверки: perm — какое разрешение нужно ("" — без разрешения) ----
    readonly property var tests: [
        { key: "exec", perm: "exec", title: "api.exec — запуск с результатом", run: function (done) {
            root.api.exec(["echo", "привет"], { timeout: 5000 }, (code, out, err) =>
                done(code === 0 && out.trim() === "привет", "код " + code + (err ? " · " + err.trim() : ""))) } },
        { key: "run", perm: "exec", title: "api.run — запустить и забыть", run: function (done) {
            root.api.run(["true"]); done(root.has("exec"), root.has("exec") ? "отправлено" : "нет разрешения — не запущено") } },
        { key: "http", perm: "network", title: "api.http — запрос в сеть", run: function (done) {
            root.api.http(root.api.settings.url, { timeout: 10000 }, (status, text) =>
                done(status >= 200 && status < 400, status ? "HTTP " + status + " · " + text.length + " байт" : "статус 0 (нет разрешения или сети)")) } },
        { key: "context", perm: "clipboard", title: "api.contextText — выделение/буфер", run: function (done) {
            done(root.has("clipboard"), root.has("clipboard") ? "длина " + root.api.contextText.length : "нет разрешения — пусто") } },
        { key: "copy", perm: "clipboard", title: "api.copy — в буфер обмена", run: function (done) {
            root.api.copy("Glide API test " + Date.now())
            if (!root.has("exec") || !root.has("clipboard")) { done(root.has("clipboard"), root.has("clipboard") ? "скопировано (проверить чтение — нужно exec)" : "нет разрешения"); return }
            root.api.exec(["sh", "-c", "sleep 0.3; wl-paste -n -t text"], (c, o) => done(o.indexOf("Glide API test") === 0, "в буфере: " + o.slice(0, 30))) } },
        { key: "notifs", perm: "notifications", title: "api.notifs — история уведомлений", run: function (done) {
            done(root.api.notifs !== null, root.api.notifs ? root.api.notifs.list.length + " в истории · событий получено: " + root.notifSeen : "api.notifs = null") } },
        { key: "niri", perm: "windows", title: "api.niri — окна и столы", run: function (done) {
            done(root.api.niri !== null, root.api.niri ? root.api.niri.workspaces.length + " столов · окон: " + Object.keys(root.api.niri.windows).length : "api.niri = null") } },
        { key: "phone", perm: "phone", title: "api.kdeconnect — телефон", run: function (done) {
            done(root.api.kdeconnect !== null, root.api.kdeconnect ? "объект есть" : "api.kdeconnect = null") } },
        { key: "system", perm: "system", title: "api.recorder / setAwake / setPref", run: function (done) {
            root.api.setAwake(root.api.awake)   // то же значение — ничего не меняет, но проходит через проверку
            done(root.api.recorder !== null, root.api.recorder ? "доступно" : "api.recorder = null, setAwake/setPref — не сработают") } },
        { key: "storage", perm: "", title: "api.storage — get/set/keys/remove", run: function (done) {
            var s = root.api.storage
            s.set("probe", { n: 42, t: "тест" })
            var ok = s.get("probe", null) && s.get("probe").n === 42 && s.keys().indexOf("probe") >= 0
            s.remove("probe")
            done(ok && s.get("probe", "нет") === "нет", "ключей: " + s.keys().length) } },
        { key: "settings", perm: "", title: "api.settings — настройки из plugin.json", run: function (done) {
            var v = root.api.settings.level
            done(typeof v === "number" && v >= 1 && v <= 5, "level = " + v + " · url = " + root.api.settings.url) } },
        { key: "files", perm: "", title: "api.files — своя папка", run: function (done) {
            var f = root.api.files
            f.write("probe.txt", "строка 1\nстрока 2", (ok) => {
                if (!ok) { done(false, "запись не удалась"); return }
                f.read("probe.txt", (text) => f.list((l) => {
                    var good = text === "строка 1\nстрока 2" && l.some(x => x.name === "probe.txt")
                    f.read("../../secret", (bad) => f.remove("probe.txt", () => done(good && bad === null,
                        "прочитано " + (text || "").length + " зн. · файлов " + l.length + " · «../» " + (bad === null ? "не пускает" : "ПУСТИЛ"))))
                }))
            }) } },
        { key: "timers", perm: "", title: "api.setTimeout / setInterval / clearTimer", run: function (done) {
            var n = 0, t0 = Date.now()
            var iv = root.api.setInterval(() => n++, 50)
            root.api.setTimeout(() => { root.api.clearTimer(iv); var k = n; root.api.setTimeout(() => done(k >= 3 && n === k, "тиков " + k + " за " + (Date.now() - t0) + " мс, после clear — стоп"), 200) }, 300) } },
        { key: "activity", perm: "", title: "api.activity — строка в острове", run: function (done) {
            var a = root.api.activity
            a.start("probe", { title: "Проверка API", subtitle: "смотри в остров", progress: 0, actionLabel: "Стоп",
                              onAction: function () { a.end("probe") } })
            root.api.setTimeout(() => a.update("probe", { progress: 0.6 }), 600)
            root.api.setTimeout(() => { a.end("probe"); done(true, "показана 2 с (наведи на остров — будет «Стоп»)") }, 2000) } },
        { key: "flash", perm: "", title: "api.flash и api.notify", run: function (done) {
            root.api.flash("󰙨", "api.flash работает")
            root.api.notify("Проверка API", "api.notify работает", "")
            done(true, "вспышка в острове и уведомление") } },
        { key: "lang", perm: "", title: "api.tr / lang / log / date / today", run: function (done) {
            root.api.log("проверка журнала", { n: 1 })
            done(root.api.today === Qt.formatDate(new Date(), "yyyy-MM-dd") && (root.api.lang === "ru" || root.api.lang === "en"),
                 root.api.tr("по-русски", "in English") + " · " + root.api.today) } },
        { key: "theme", perm: "", title: "api.theme / accent / iconFont", run: function (done) {
            done(!!root.api.theme && root.api.accent !== undefined && !!root.api.iconFont,
                 "акцент " + root.api.accent + " · светлая: " + root.api.theme.isLight + " · событий темы: " + root.themeEvents) } },
        { key: "media", perm: "", title: "api.player / volume / battery / weather", run: function (done) {
            done(true, (root.api.player ? "плеер: " + (root.api.player.identity || "?") : "плеера нет") + " · громкость "
                 + Math.round(root.api.volume * 100) + "% · батарея " + root.api.battery.percent + "%"
                 + (root.api.weather && root.api.weather.ok ? " · погода есть" : "")) } },
        { key: "service", perm: "", title: "service — фоновая служба плагина", run: function (done) {
            var n = root.api.storage.get("serviceTicks", 0)
            done(n > 0, n > 0 ? "жива, тиков: " + n : "ещё не тикала (подожди 5 с после старта)") } },
        { key: "send", perm: "", title: "api.send — сообщение другим плагинам", run: function (done) {
            root.api.send("*", "ping", { from: "apitest" }); done(true, "отправлено всем") } },
        { key: "perms", perm: "", title: "api.permissions — что объявлено и выдано", run: function (done) {
            var p = root.api.permissions
            done(p.requested.length === 7, "выдано " + p.granted.length + " из " + p.requested.length + ": " + p.granted.join(", ")) } }
    ]

    function runAll() {
        if (!api) return
        var r = {}
        for (var t of tests) r[t.key] = { ok: null, detail: "…" }
        results = r
        for (var t2 of tests) (function (t) {
            try { t.run((ok, detail) => root.set(t.key, ok, detail)) }
            catch (e) { root.set(t.key, false, "исключение: " + e) }
        })(t2)
    }
    // проверки — по кнопке и после смены разрешений (не при каждом открытии: иначе каждый раз вспышка и уведомление)

    // ---- шапка: разрешения и кнопка ----
    Text {
        Layout.fillWidth: true
        text: "Выключай разрешения в «Настройки» → «Плагины» и жми «Проверить всё». Строки с выключенным разрешением должны стать ✗."
        color: Theme.textSecondary; font.pixelSize: Theme.fs(11); wrapMode: Text.WordWrap
    }
    Flow {
        Layout.fillWidth: true
        spacing: 6
        Repeater {
            model: root.api ? root.api.permissions.requested : []
            delegate: Rectangle {
                id: pc
                required property string modelData
                readonly property string st: root.api ? root.api.permissions.state(modelData) : "ask"
                implicitWidth: pcText.implicitWidth + 20; implicitHeight: 26; radius: Theme.r(13)
                color: st === "granted" ? Theme.accentSoft : pcMa.containsMouse ? Theme.surfaceHigher : Theme.surface
                border.color: st === "granted" ? Theme.accent : st === "denied" ? Theme.error : Theme.outline
                scale: pcMa.pressed ? 0.95 : 1
                Behavior on color { ColorAnimation { duration: Prefs.ms(120) } }
                Behavior on scale { NumberAnimation { duration: Prefs.ms(140); easing.type: Easing.OutBack } }
                Text { id: pcText; anchors.centerIn: parent; font.pixelSize: Theme.fs(11)
                       text: (pc.st === "granted" ? "✓ " : pc.st === "denied" ? "✗ " : "? ") + pc.modelData
                       color: pc.st === "denied" ? Theme.error : Theme.text }
                MouseArea { id: pcMa; anchors.fill: parent; hoverEnabled: true
                            cursorShape: pc.st === "granted" ? Qt.ArrowCursor : Qt.PointingHandCursor
                            onClicked: if (pc.st !== "granted") root.api.permissions.request(pc.modelData, "Проверка API: попробовать " + pc.modelData) }
            }
        }
    }
    Rectangle {
        implicitWidth: 150; implicitHeight: 34; radius: Theme.r(17)
        color: allMa.pressed ? Theme.accentPressed : allMa.containsMouse ? Theme.accentLight : Theme.accent
        scale: allMa.pressed ? 0.95 : 1
        Behavior on color { ColorAnimation { duration: Prefs.ms(120) } }
        Behavior on scale { NumberAnimation { duration: Prefs.ms(140); easing.type: Easing.OutBack } }
        Text { anchors.centerIn: parent; text: "Проверить всё"; color: Theme.accentText; font.pixelSize: Theme.fs(13) }
        MouseArea { id: allMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.runAll() }
    }

    // ---- результаты ----
    Repeater {
        model: root.tests
        delegate: Rectangle {
            id: row
            required property var modelData
            readonly property var res: root.results[modelData.key] || ({ ok: null, detail: "" })
            Layout.fillWidth: true
            implicitHeight: col.implicitHeight + 14
            radius: Theme.r(12)
            color: Theme.surface
            border.color: res.ok === false ? Theme.error : Theme.outline
            Text {
                x: 10; y: 7
                text: row.res.ok === null ? "…" : row.res.ok ? "✓" : "✗"
                color: row.res.ok === null ? Theme.textMuted : row.res.ok ? Theme.success : Theme.error
                font.pixelSize: Theme.fs(15); font.bold: true
            }
            Column {
                id: col
                x: 32; y: 7
                width: row.width - x - 10
                spacing: 2
                Text {
                    width: parent.width
                    text: row.modelData.title + (row.modelData.perm ? "  · " + row.modelData.perm : "")
                    color: Theme.text; font.pixelSize: Theme.fs(12); elide: Text.ElideRight
                }
                Text {
                    width: parent.width
                    text: row.res.detail
                    color: Theme.textSecondary; font.pixelSize: Theme.fs(11); wrapMode: Text.WordWrap
                }
            }
        }
    }
}
