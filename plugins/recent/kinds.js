.pragma library
// значок по типу файла (Nerd Font) — для раздела и поиска
function glyph(mime, name) {
    var m = mime || "", x = (name || "").toLowerCase().split(".").pop()
    if (m.indexOf("image/") === 0) return 0xF021F
    if (m.indexOf("video/") === 0) return 0xF022B
    if (m.indexOf("audio/") === 0) return 0xF0223
    if (m === "application/pdf" || x === "pdf") return 0xF0226
    if (/zip|tar|compressed|7z|rar|xz|zstd/.test(m)) return 0xF05C4
    if (m.indexOf("text/") === 0 || /^(md|txt|py|js|qml|json|kdl|sh|c|cpp|h|rs|go)$/.test(x)) return 0xF0219
    return 0xF0214
}
function ago(t, tr) {
    var s = Math.max(0, Date.now() / 1000 - t)
    if (s < 3600) return Math.max(1, Math.round(s / 60)) + tr(" мин")
    if (s < 86400) return Math.round(s / 3600) + tr(" ч")
    return Math.round(s / 86400) + tr(" дн.")
}
