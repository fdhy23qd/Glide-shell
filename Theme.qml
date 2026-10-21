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
    readonly property var t: tones[Prefs.themeTone] || tones.glide

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
    readonly property color text: "#f5f7fa"             // TextPrimary
    readonly property color textVariant: "#c3cbd6"      // значки и второстепенные надписи
    readonly property color textSecondary: "#9aa5b5"    // TextSecondary
    readonly property color textMuted: "#6b7686"        // подсказки
    readonly property color textFaint: "#4b5563"        // совсем вторичное (дни чужого месяца, номера недель)

    // ---- акцент (выбирается в настройках) ----
    readonly property color accent: Prefs.accent
    readonly property color accentSoft: Prefs.accentSoft
    readonly property color accentHover: Prefs.accentHover
    readonly property color accentLight: Qt.lighter(Prefs.accent, 1.12)    // залитая акцентом кнопка под курсором
    readonly property color accentPressed: Qt.darker(Prefs.accent, 1.15)   // … и нажатая
    // текст на акценте: белый, а на светлых акцентах — тёмный, как onPrimary в MD3
    readonly property color accentText: 0.299 * accent.r + 0.587 * accent.g + 0.114 * accent.b > 0.62 ? background : "#ffffff"

    // ---- смысловые цвета ----
    readonly property color error: "#ef5b5b"            // ErrorRed
    readonly property color errorSoft: "#e58a8a"        // выходные в календаре
    readonly property color errorContainer: "#3a1f24"
    readonly property color errorHover: "#4a2328"
    readonly property color errorText: "#ffdad6"
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
