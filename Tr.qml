pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Перевод интерфейса. Ключ — русская строка (как в коде), перевод — i18n/<язык>.json: {"Настройки": "Settings", …}.
// Нет перевода — остаётся русская строка (перевод можно пополнять постепенно). Язык — Prefs.lang
// (auto — по $LANG: ru* — русский, иначе английский). Tr.t("…") — в каждом видимом тексте; Tr.locale — для дат.
Singleton {
    id: tr
    readonly property string sys: (Quickshell.env("LC_ALL") || Quickshell.env("LC_MESSAGES") || Quickshell.env("LANG") || "ru").slice(0, 2)
    readonly property string lang: Prefs.lang === "ru" || Prefs.lang === "en" ? Prefs.lang : (sys === "ru" ? "ru" : "en")
    readonly property bool ru: lang === "ru"
    readonly property var locale: Qt.locale(ru ? "ru_RU" : "en_US")
    property var dict: ({})
    FileView {
        path: tr.ru ? "" : Quickshell.shellDir + "/i18n/" + tr.lang + ".json"
        blockLoading: true
        printErrors: false
        onLoaded: { try { tr.dict = JSON.parse(text()) } catch (e) { tr.dict = {}; console.warn("glide-shell: i18n/" + tr.lang + ".json:", e) } }
    }
    onRuChanged: if (ru) dict = ({})
    function t(s) { return ru ? s : (dict[s] !== undefined ? dict[s] : s) }
    // дата по-человечески: формат Qt (dddd, d MMMM) на языке интерфейса, с заглавной буквы
    function num(x, digits) { var s = Number(x).toFixed(digits); return ru ? s.replace(".", ",") : s }   // 1,5 / 1.5
    function date(d, fmt) { var s = locale.toString(d, fmt); return s.charAt(0).toUpperCase() + s.slice(1) }
}
