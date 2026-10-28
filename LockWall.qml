pragma Singleton
import QtQuick
import Quickshell
import Qt.labs.folderlistmodel

// Картинка фона замка (Prefs.lockBackground): «обои» — то, что сейчас на рабочем столе (у GIF и видео — их кадр;
// HTML-сцена — нет картинки, остаётся сияние), «картинка» — файл или папка Prefs.lockImage. Из папки — случайная,
// новая при каждой блокировке (next() зовёт LockScreen при смене режима — до заслонки, так что замок и заслонка
// после разблокировки показывают одну и ту же).
Singleton {
    id: lw
    readonly property string home: Quickshell.env("HOME")
    readonly property string path: Prefs.lockImage.indexOf("://") > 0 ? Prefs.lockImage : Prefs.lockImage.replace(/^~(?=\/|$)/, home)
    readonly property bool isFile: /\.(jpe?g|png|webp|bmp|gif)$/i.test(path)
    property string picked: ""   // выбранная из папки

    readonly property string file: {
        if (Prefs.lockBackground === "wallpaper") {
            var w = Core.wallpaper
            if (!w || !w.on || !w.current) return ""
            return w.kind === "image" ? w.current : w.entry ? w.entry.thumb : ""
        }
        if (Prefs.lockBackground !== "image" || !path) return ""
        return isFile ? path : picked
    }
    readonly property string source: !file ? "" : file.indexOf("://") > 0 ? file : "file://" + file

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
        if (Prefs.lockBackground !== "image" || isFile) return
        picked = pick(files(), picked, Math.random())
    }
}
