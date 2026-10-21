import QtQuick

// Пружина для Behavior, как у Dynamic Island: прерываемая, сохраняет скорость при смене цели.
// bounce — сила отскока (0 — без отскока, 0.3 — заметный), speed — относительная скорость.
// Behavior on width { enabled: Prefs.anim > 0; Spring { bounce: 0.3 } }
SpringAnimation {
    property real bounce: 0.25
    property real speed: 1
    // собственная частота, рад/с; настройка «Анимации» растягивает время как и у остальных
    readonly property real omega: 14 * speed / Math.max(0.3, Prefs.anim)
    // SpringAnimation считает шагами по 16 мс: ω² = 62.5·spring, 2ζω = 62.5·damping
    spring: omega * omega / 62.5
    // настройка «Упругость» масштабирует отскок; 0.85 — предел, дальше пружина почти не гаснет
    damping: 2 * (1 - Math.min(0.85, bounce * Prefs.bounce)) * omega / 62.5
    epsilon: 0.25
}
