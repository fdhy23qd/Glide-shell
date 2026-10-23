import QtQuick

// Служба: живёт всё время, раз в 5 с пишет счётчик в хранилище — раздел и бар видят, что служба жива.
Item {
    id: svc
    property var api
    property var timer: null
    onApiChanged: if (api && !timer) timer = api.setInterval(() => api.storage.set("serviceTicks", api.storage.get("serviceTicks", 0) + 1), 5000)
}
