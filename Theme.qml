pragma Singleton
import QtQuick
import Quickshell

// Дизайн Glide: структура Material 3 и токены Glide Messenger (androidapp/.../glidemessenger/ui/theme/Color.kt).
// Все цвета интерфейса берутся отсюда — и в ядре, и во встроенных плагинах (`import qs`), сторонним —
// через api.theme. Настраивается (раздел «Тема»): тон фона, акцент, скругления, шрифт, прозрачность.
Singleton {
    id: theme

    // ---- тон: графит Glide (как в мессенджере), AMOLED — чистый чёрный, мягкий — светлее и синее ----
    readonly property var tones: ({
        glide:  { background: "#0f1115", surface: "#1b1f26", surfaceLow: "#1f242c", surfaceHigh: "#232831",
                  surfaceHigher: "#2c3340", surfacePressed: "#353d4b", outline: "#2e3a4a", divider: "#334155" },
        amoled: { background: "#000000", surface: "#111216", surfaceLow: "#15171b", surfaceHigh: "#1a1c21",
                  surfaceHigher: "#23262d", surfacePressed: "#2d3139", outline: "#262a31", divider: "#2b3038" },
        soft:   { background: "#161a22", surface: "#212733", surfaceLow: "#262c39", surfaceHigh: "#2a313e",
                  surfaceHigher: "#343c4b", surfacePressed: "#3e4757", outline: "#37445a", divider: "#3d4a5f" }
    })
    // светлая: белые карточки на светло-сером, тёмный текст (те же роли, что у тёмных тонов)
    readonly property var lightTone: ({ background: "#eef0f4", surface: "#ffffff", surfaceLow: "#f6f7f9", surfaceHigh: "#e8ebf0",
                                         surfaceHigher: "#dde2e9", surfacePressed: "#d1d7e0", outline: "#d3d9e2", divider: "#c8d0db" })
    // «авто»: светлая с восхода до заката (время — из погоды, без неё 7:00–21:00), проверка раз в минуту
    property bool dayNow: true
    function checkDay() {
        var n = new Date(), m = n.getHours() * 60 + n.getMinutes()
        function mins(s) { var a = String(s || "").split(":"); return a.length === 2 ? (+a[0]) * 60 + (+a[1]) : NaN }
        var up = mins(NightLight.sunrise), down = mins(NightLight.sunset)
        if (isNaN(up)) up = 420
        if (isNaN(down)) down = 1260
        dayNow = m >= up && m < down
    }
    Timer { running: Prefs.themeMode === "auto"; repeat: true; interval: 60000; triggeredOnStart: true; onTriggered: theme.checkDay() }
    Connections { target: NightLight; function onSunsetChanged() { theme.checkDay() } function onSunriseChanged() { theme.checkDay() } }
    readonly property bool isLight: Prefs.themeMode === "light" || (Prefs.themeMode === "auto" && dayNow)
    readonly property var t: isLight ? lightTone : (tones[Prefs.themeTone] || tones.glide)

    // ---- поверхности: от фона к выделенным слоям ----
    readonly property color background: t.background       // остров, бар, панель
    readonly property color surface: t.surface             // карточки, поля, плитки
    readonly property color surfaceLow: t.surfaceLow       // наведение на строку списка
    readonly property color surfaceHigh: t.surfaceHigh     // кнопки (SecBtn в мессенджере)
    readonly property color surfaceHigher: t.surfaceHigher // наведение
    readonly property color surfacePressed: t.surfacePressed // нажатие
    readonly property color outline: t.outline             // обводки (CardBorder)
    readonly property color divider: t.divider
    readonly property color outlineHover: textFaint          // обводка поля ввода под курсором

    // ---- состояния (как в MD3): наведение — светлее, нажатие — темнее и чуть меньше, недоступно — полупрозрачно,
    // фокус поля — акцентная обводка толщиной 2 ----
    readonly property real disabledOpacity: 0.38
    // фон бара, острова, дока и панели — с настраиваемой непрозрачностью
    readonly property color backgroundBar: Qt.rgba(background.r, background.g, background.b, Prefs.themeOpacity)

    // ---- текст ----
    readonly property color text: isLight ? "#14171c" : "#f5f7fa"             // TextPrimary
    readonly property color textVariant: isLight ? "#364050" : "#c3cbd6"      // значки и второстепенные надписи
    readonly property color textSecondary: isLight ? "#5a6473" : "#9aa5b5"    // TextSecondary
    readonly property color textMuted: isLight ? "#7f8999" : "#6b7686"        // подсказки
    // текст прямо на обоях (виджеты рабочего стола): от темы панели не зависит — обои светлее не становятся
    readonly property color deskText: "#f5f7fa"
    readonly property color deskTextSecondary: "#9aa5b5"
    readonly property color deskTextMuted: "#6b7686"
    readonly property color textFaint: isLight ? "#a3abb8" : "#4b5563"        // совсем вторичное (дни чужого месяца, номера недель)

    // ---- акцент (выбирается в настройках) ----
    readonly property color accent: Prefs.accent
    readonly property color accentSoft: Prefs.accentSoft
    readonly property color accentHover: Prefs.accentHover
    readonly property color accentLight: Qt.lighter(Prefs.accent, 1.12)    // залитая акцентом кнопка под курсором
    readonly property color accentPressed: Qt.darker(Prefs.accent, 1.15)   // … и нажатая
    // текст на акценте: белый, а на светлых акцентах — тёмный, как onPrimary в MD3
    readonly property color accentText: 0.299 * accent.r + 0.587 * accent.g + 0.114 * accent.b > 0.62 ? "#0f1115" : "#ffffff"

    // ---- смысловые цвета ----
    readonly property color error: "#ef5b5b"            // ErrorRed
    readonly property color errorSoft: isLight ? "#d65c5c" : "#e58a8a"        // выходные в календаре
    readonly property color errorContainer: isLight ? "#fde4e4" : "#3a1f24"
    readonly property color errorHover: isLight ? "#fbd2d2" : "#4a2328"
    readonly property color errorText: isLight ? "#8b1d1d" : "#ffdad6"
    readonly property color success: "#34c77b"
    readonly property color warning: "#f5a623"

    // ---- формы: скругления как в Glide Messenger (чаще всего 24, затем 16–20), с масштабом ----
    function r(n) { return Math.round(n * Prefs.themeRadius) }
    readonly property int radiusSm: r(12)     // кнопки, строки списков
    readonly property int radiusMd: r(16)     // поля ввода, плитки
    readonly property int radiusLg: r(24)     // карточки, панель у края
    readonly property int radiusXl: r(28)     // раскрытый остров

    // ---- шрифт — системный (сейчас Inter), как FontFamily.Default в Glide Messenger; размер — с масштабом ----
    function fs(n) { return Math.round(n * Prefs.themeFont) }
}
