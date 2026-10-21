pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Тема экрана входа — те же токены, что у Glide Shell (Theme.qml), и настройки выбранного пользователя:
// акцент, тон, скругления, размер текста, фон и часы замка. Читаются прямо из его
// ~/.config/glide-shell/config.json (у пользователя greeter есть право читать домашнюю папку и .config —
// его ставит установка экрана входа, раньше — DMS). Не прочиталось — умолчания Glide.
Singleton {
    id: look
    property string home: ""                      // домашняя папка пользователя, чьи настройки берём
    property var data: ({})
    FileView {
        path: look.home ? look.home + "/.config/glide-shell/config.json" : ""
        printErrors: false
        onLoaded: { try { look.data = JSON.parse(text()).panel || {} } catch (e) { look.data = {} } }
        onLoadFailed: look.data = {}
    }
    function num(v, d) { var n = Number(v); return v === undefined || v === null || isNaN(n) ? d : n }

    readonly property var tones: ({
        glide:  { background: "#0f1115", surface: "#1b1f26", surfaceHigh: "#232831", surfaceHigher: "#2c3340",
                  surfacePressed: "#353d4b", outline: "#2e3a4a" },
        amoled: { background: "#000000", surface: "#111216", surfaceHigh: "#1a1c21", surfaceHigher: "#23262d",
                  surfacePressed: "#2d3139", outline: "#262a31" },
        soft:   { background: "#161a22", surface: "#212733", surfaceHigh: "#2a313e", surfaceHigher: "#343c4b",
                  surfacePressed: "#3e4757", outline: "#37445a" }
    })
    readonly property var t: tones[data.themeTone] || tones.glide
    readonly property color background: t.background
    readonly property color surface: t.surface
    readonly property color surfaceHigh: t.surfaceHigh
    readonly property color surfaceHigher: t.surfaceHigher
    readonly property color surfacePressed: t.surfacePressed
    readonly property color outline: t.outline
    readonly property color outlineHover: textFaint

    readonly property color text: "#f5f7fa"
    readonly property color textVariant: "#c3cbd6"
    readonly property color textSecondary: "#9aa5b5"
    readonly property color textMuted: "#6b7686"
    readonly property color textFaint: "#4b5563"
    readonly property color error: "#ef5b5b"
    readonly property color success: "#34c77b"
    readonly property color warning: "#f5a623"

    readonly property color accent: /^#[0-9a-fA-F]{6}$/.test(data.accent || "") ? data.accent : "#7b61ff"
    readonly property color accentHover: Qt.rgba(accent.r, accent.g, accent.b, 0.42)
    readonly property color accentLight: Qt.lighter(accent, 1.12)
    readonly property color accentPressed: Qt.darker(accent, 1.15)
    readonly property color accentText: 0.299 * accent.r + 0.587 * accent.g + 0.114 * accent.b > 0.62 ? background : "#ffffff"
    readonly property real disabledOpacity: 0.38

    readonly property real radiusScale: Math.max(0, Math.min(1.6, num(data.themeRadius, 1)))
    readonly property real fontScale: Math.max(0.85, Math.min(1.2, num(data.themeFont, 1)))
    function r(n) { return Math.round(n * radiusScale) }
    function fs(n) { return Math.round(n * fontScale) }
    readonly property real anim: num(data.anim, 1)
    function ms(d) { return Math.round(d * anim) }
    readonly property string iconFont: "JetBrainsMono Nerd Font"

    // как на экране блокировки — чтобы вход и замок выглядели одним экраном
    readonly property int clockSize: num(data.lockClockSize, 112)
    readonly property bool clockBold: data.lockClockBold === true
    readonly property string background_: ["glow", "solid", "image"].indexOf(data.lockBackground) >= 0 ? data.lockBackground : "glow"
    readonly property string image: typeof data.lockImage === "string" ? data.lockImage.trim().replace(/^~/, home) : ""
}
