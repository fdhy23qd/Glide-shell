import QtQuick

// Служба: живёт всё время, раз в 5 с пишет счётчик в хранилище — раздел и бар видят, что служба жива.
Item {
    id: svc
    property var api
    property var timer: null
    // раздел просит службу (свой плагин — разрешение не нужно): эхо и цвет острова, который живёт со службой
    Connections {
        target: svc.api
        ignoreUnknownSignals: true
        function onMessage(from, name, data) {
            if (from !== "apitest") return
            if (name === "echo") svc.api.send("apitest", "echo-reply", data)
            if (name === "tint") {
                var ok = svc.api.island.tint(svc.api.accent)
                if (ok) svc.api.setTimeout(() => svc.api.island.clear(), 6000)
                svc.api.send("apitest", "tint-reply", { ok: ok })
            }
        }
    }
    onApiChanged: if (api && !timer) timer = api.setInterval(() => api.storage.set("serviceTicks", api.storage.get("serviceTicks", 0) + 1), 5000)
}
