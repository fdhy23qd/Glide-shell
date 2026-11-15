import QtQuick
import Quickshell

// Телефоны (v2.15): Glide Link и KDE Connect одним списком. Главный — на связи по Glide Link, потом по KDE Connect;
// действие уходит своему помощнику; флаг в настройках прячет источник. Помощники-наблюдатели стартуют только
// после «тёплого» старта (6 с) — сценарий укладывается раньше и списки задаёт сам.
ShellRoot {
    QmlCheck { id: t }
    readonly property var link: ({ id: "l1", name: "Pixel", type: "phone", backend: "glidelink", reachable: false,
                                   plugins: ["screen"], streams: { screen_in: true } })
    readonly property var kde: ({ id: "k1", name: "Pixel KDE", type: "phone", backend: "kdeconnect", reachable: true,
                                  plugins: ["sms"] })
    Component.onCompleted: {
        Phones.linkDevices = [link]
        Phones.kdeDevices = [kde]
        t.then(100, () => {
            t.ok("Glide Link не на связи — главный KDE Connect", Phones.phone && Phones.phone.id === "k1", Phones.phone)
            t.ok("список: сначала Glide Link", Phones.devices.map(d => d.id).join() === "l1,k1", Phones.devices.map(d => d.id))
            t.ok("available", Phones.available)
            Phones.linkDevices = [Object.assign({}, link, { reachable: true })]
        })
        t.then(100, () => {
            t.ok("оба на связи — главный Glide Link", Phones.phone.id === "l1", Phones.phone)
            var c1 = Phones.command(Phones.phone, "screen")
            t.ok("действие Glide Link — glide-link.py", c1[2].endsWith("/tools/glide-link.py") && c1.slice(3).join(" ") === "act l1 screen", c1)
            var c2 = Phones.command(kde, "text", "привет")
            t.ok("действие KDE — glide-kdeconnect.py", c2[2].endsWith("/tools/glide-kdeconnect.py") && c2.slice(3).join(" ") === "act k1 text привет", c2)
            t.ok("трансляция видна у Glide Link", Phones.streaming(Phones.phone, "screen_in") && !Phones.streaming(kde, "screen_in"))
            t.ok("has()", Phones.has(kde, "sms") && !Phones.has(kde, "screen") && !Phones.has(null, "sms"))
            // уведомления ПК → телефон: по умолчанию выключено
            Phones.linkUp = true
            Phones.linkDevices = [Object.assign({}, link, { reachable: true, plugins: ["notification"] })]
            t.ok("пересылка выключена по умолчанию", !Phones.forward({ appName: "Firefox", summary: "s", body: "b" }))
            Prefs.set("phoneNotifs", true)
        })
        t.then(1500, () => {
            Notifs.night = true    // тихие часы (по умолчанию 23–8): сценарий не зависит от времени запуска
            t.ok("«не беспокоить» — не уходит", !Phones.forward({ appName: "Firefox", summary: "s", body: "b" }))
            Notifs.night = false
            t.ok("включили — уходит", Phones.forward({ appName: "Firefox", summary: "<b>s</b>", body: "b" }))
            t.ok("зеркала с телефона назад не уходят", !Phones.forward({ appName: "Glide Link", summary: "s", body: "b" })
                 && !Phones.forward({ appName: "KDE Connect", summary: "s", body: "b" }))
            Phones.linkDevices = [Object.assign({}, link, { reachable: false, plugins: ["notification"] })]
            t.ok("телефон не на связи — не уходит", !Phones.forward({ appName: "Firefox", summary: "s", body: "b" }))
            Prefs.set("glidelink", false)
        })
        t.then(1500, () => {
            t.ok("Glide Link выключен — его устройств нет", Phones.devices.map(d => d.id).join() === "k1", Phones.devices.map(d => d.id))
            t.ok("…и главный — KDE Connect", Phones.phone && Phones.phone.id === "k1", Phones.phone)
            Prefs.set("kdeconnect", false)
        })
        t.then(1500, () => {
            t.ok("оба выключены — пусто", Phones.devices.length === 0 && !Phones.available && Phones.phone === null)
            t.done()
        })
    }
}
