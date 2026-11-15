import QtQuick
import Quickshell

// Фон замка (LockWall, v2.9): файл, папка — случайная и не та же при каждой блокировке, «как обои» — текущая
// картинка рабочего стола или кадр GIF/видео, HTML-сцена (v2.17) — её кадр из webpaper, перечитывается на каждую
// блокировку и раз в 15 с, пока замок на экране. Папка — $GLIDE_TEST_WALLS (три файла).
ShellRoot {
    id: root
    QmlCheck { id: t }
    readonly property string dir: Quickshell.env("GLIDE_TEST_WALLS")
    QtObject { id: wall; property bool on: true; property string current: "/w/a.png"; property string kind: "image"; property var entry: ({ thumb: "/w/t.png" }) }

    Component.onCompleted: {
        Core.wallpaper = wall
        t.ok("один — он и есть", LockWall.pick(["a"], "a", 0.9) === "a")
        t.ok("пусто — пусто", LockWall.pick([], "", 0.5) === "")
        Prefs.data = { lockBackground: "image", lockImage: root.dir + "/one.png" }
        t.ok("файл", LockWall.source === "file://" + root.dir + "/one.png", LockWall.source)
        Prefs.data = { lockBackground: "image", lockImage: root.dir }
        t.then(800, () => {
            var f = LockWall.files()
            t.ok("в папке три картинки (не txt)", f.length === 3, f)
            t.ok("сразу выбрана", f.indexOf(LockWall.picked) >= 0 && LockWall.source === "file://" + LockWall.picked, LockWall.source)
            var same = 0, prev = LockWall.picked
            for (var i = 0; i < 30; i++) { LockWall.next(); if (LockWall.picked === prev) same++; prev = LockWall.picked }
            t.ok("каждый раз другая", same === 0, same)
            Prefs.data = { lockBackground: "wallpaper" }
            t.ok("как обои — картинка", LockWall.source === "file:///w/a.png", LockWall.source)
            wall.kind = "video"; wall.current = "/w/v.mp4"
            t.ok("как обои — кадр видео", LockWall.source === "file:///w/t.png", LockWall.source)
            wall.on = false
            var scene = Quickshell.env("XDG_RUNTIME_DIR") + "/webpaper/scene.png"
            t.ok("сцена — её кадр", LockWall.file === scene && LockWall.source === "file://" + scene + "?v=" + LockWall.rev, LockWall.source)
            var r0 = LockWall.rev
            LockWall.next()
            t.ok("новая блокировка — свежий кадр", LockWall.rev === r0 + 1, LockWall.rev)
            t.ok("пока замка нет — не перечитывается", !LockWall.refresh.running)
            LockWall.live = true
            t.ok("замок на экране — перечитывается", LockWall.refresh.running)
            LockWall.live = false
            Prefs.data = { lockBackground: "glow", lockImage: root.dir }
            LockWall.live = true
            t.ok("сияние — без картинки и без перечитывания", LockWall.source === "" && !LockWall.refresh.running)
            LockWall.live = false
            t.done()
        })
    }
}
