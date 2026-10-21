pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Погода: раз в 30 минут tools/glide-weather.py (Open-Meteo; город из настроек или по IP/часовому поясу).
// Скрипт сам держит кэш на 20 минут, так что refresh() при открытии панели сеть почти не трогает.
// data — {place, now: {temp, feels, humidity, wind, code, day}, hours[], days[], sunrise, sunset} или {error}.
Singleton {
    id: wx
    property var data: null
    readonly property bool ok: !!data && !data.error && !!data.now
    readonly property bool enabled: Prefs.weather
    readonly property string city: Prefs.weatherCity

    function refresh() { if (enabled && !proc.running) proc.running = true }
    onCityChanged: refresh()

    Process {
        id: proc
        command: ["python3", "-I", Quickshell.shellDir + "/tools/glide-weather.py", wx.city]
        stdout: StdioCollector {
            onStreamFinished: { try { wx.data = JSON.parse(text) } catch (e) {} }
        }
    }
    Timer {
        running: wx.enabled && Prefs.warm   // первый запрос — не в толкотне старта
        interval: 30 * 60 * 1000
        repeat: true
        triggeredOnStart: true
        onTriggered: wx.refresh()
    }

    // после сна: 30-минутный таймер во сне стоял, данные со вчера. Сеть поднимается не сразу —
    // если скрипт отдал старый кэш (stale) или ошибку, пробуем ещё раз через 20 с (до трёх раз)
    property int wakeTries: 0
    function afterSleep() { wakeTries = 3; refresh(); wakeRetry.restart() }
    Timer {
        id: wakeRetry
        interval: 20000
        onTriggered: if (wx.enabled && --wx.wakeTries >= 0 && (!wx.data || wx.data.stale || wx.data.error)) {
            wx.refresh(); restart()
        }
    }

    function temp(t) {
        var r = Math.round(t)
        return (r > 0 ? "+" : r < 0 ? "−" : "") + Math.abs(r) + "°"
    }
    // коды WMO (Open-Meteo) → описание и значок MDI (днём / ночью)
    function describe(c) {
        return c === 0 ? Tr.t("Ясно") : c === 1 ? Tr.t("Преимущественно ясно") : c === 2 ? Tr.t("Переменная облачность")
             : c === 3 ? Tr.t("Пасмурно") : c === 45 || c === 48 ? Tr.t("Туман")
             : c >= 51 && c <= 55 ? Tr.t("Морось") : c === 56 || c === 57 ? Tr.t("Ледяная морось")
             : c === 61 ? Tr.t("Небольшой дождь") : c === 63 ? Tr.t("Дождь") : c === 65 ? Tr.t("Сильный дождь")
             : c === 66 || c === 67 ? Tr.t("Ледяной дождь") : c === 71 ? Tr.t("Небольшой снег") : c === 73 ? Tr.t("Снег")
             : c === 75 ? Tr.t("Сильный снег") : c === 77 ? Tr.t("Снежная крупа") : c >= 80 && c <= 82 ? Tr.t("Ливень")
             : c === 85 || c === 86 ? Tr.t("Снегопад") : c === 95 ? Tr.t("Гроза") : c === 96 || c === 99 ? Tr.t("Гроза с градом") : ""
    }
    function icon(c, day) {
        var cp = c <= 1 ? (day === false ? 0xF0594 : 0xF0599)
               : c === 2 ? (day === false ? 0xF0F31 : 0xF0595)
               : c === 3 ? 0xF0590 : c === 45 || c === 48 ? 0xF0591
               : c === 65 || c === 82 ? 0xF0596 : c === 66 || c === 67 ? 0xF067F
               : c === 75 || c === 86 ? 0xF0F36 : (c >= 71 && c <= 77) || c === 85 ? 0xF0598
               : c === 95 ? 0xF0593 : c === 96 || c === 99 ? 0xF067E
               : 0xF0597   // морось и дождь
        return String.fromCodePoint(cp)
    }
}
