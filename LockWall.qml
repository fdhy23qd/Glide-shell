pragma Singleton
import QtQuick
import Quickshell
import Qt.labs.folderlistmodel

// Картинка фона замка (Prefs.lockBackground): «обои» — то, что сейчас на рабочем столе (у GIF и видео — их кадр;
// у HTML-сцены — её кадр, если сцена его отдаёт, иначе остаётся сияние), «картинка» — файл или папка Prefs.lockImage.
// Из папки — случайная, новая при каждой блокировке (next() зовёт LockScreen при смене режима — до заслонки, так что
// замок и заслонка после разблокировки показывают одну и ту же).
Singleton {
    id: lw
    readonly property string home: Quickshell.env("HOME")
    readonly property string path: Prefs.lockImage.indexOf("://") > 0 ? Prefs.lockImage : Prefs.lockImage.replace(/^~(?=\/|$)/, home)
    readonly property bool isFile: /\.(jpe?g|png|webp|bmp|gif)$/i.test(path)
    property string picked: ""   // выбранная из папки

    // Кадр HTML-сцены webpaper: страница с хуком __webpaperExportScene (ASCII-обои) раз в 15 с (на батарее — 60 с)
    // пишет его сюда без своих часов. Нет файла — Image не загрузится, и LockBackdrop оставит сияние.
    readonly property string sceneFile: Quickshell.env("XDG_RUNTIME_DIR")
        ? Quickshell.env("XDG_RUNTIME_DIR") + "/webpaper/scene.png" : ""
    property bool live: false    // замок на экране и не уходит (ставит LockScreen) — кадр сцены перечитывается
    property int rev: 0          // часть адреса кадра: смена → Image читает файл заново (запрос file:// не мешает)
    property Timer refresh: Timer {
        interval: 15000; repeat: true
        running: lw.live && lw.file !== "" && lw.file === lw.sceneFile
        onTriggered: lw.rev++
    }

    readonly property string file: {
        if (Prefs.lockBackground === "wallpaper") {
            var w = Core.wallpaper
            if (!w) return ""
            if (!w.on) return sceneFile          // обои — HTML-сцена
            if (!w.current) return ""
            return w.kind === "image" ? w.current : w.entry ? w.entry.thumb : ""
        }
        if (Prefs.lockBackground !== "image" || !path) return ""
        return isFile ? path : picked
    }
    readonly property string source: !file ? "" : file.indexOf("://") > 0 ? file
        : "file://" + file + (file === sceneFile ? "?v=" + rev : "")

    property FolderListModel folder: FolderListModel {
        folder: Prefs.lockBackground === "image" && lw.path && !lw.isFile ? "file://" + lw.path : ""
        nameFilters: ["*.jpg", "*.jpeg", "*.png", "*.webp", "*.bmp"]
        caseSensitive: false
        showDirs: false
        onStatusChanged: if (status === FolderListModel.Ready && lw.files().indexOf(lw.picked) < 0) lw.next()
        onCountChanged: if (status === FolderListModel.Ready && lw.files().indexOf(lw.picked) < 0) lw.next()
    }
    function files() {
        var out = []
        for (var i = 0; i < folder.count; i++) out.push(String(folder.get(i, "filePath")))
        return out
    }
    // случайная из списка, но не прежняя (если есть из чего выбрать); r — число 0…1
    function pick(list, prev, r) {
        if (!list.length) return ""
        var c = list.length > 1 ? list.filter(x => x !== prev) : list
        return c[Math.min(c.length - 1, Math.floor(r * c.length))]
    }
    function next() {
        if (file !== "" && file === sceneFile) rev++   // на каждую блокировку — свежий кадр сцены
        if (Prefs.lockBackground !== "image" || isFile) return
        picked = pick(files(), picked, Math.random())
    }
}
