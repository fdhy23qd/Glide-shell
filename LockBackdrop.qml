import QtQuick
import QtQuick.Effects
import Quickshell

// Фон экрана блокировки (настройка «Фон»): сияние акцента сверху, сплошной цвет, обои рабочего стола или своя
// картинка (LockWall) — с затемнением Prefs.lockDim (текст должен читаться) и размытием Prefs.lockBlur.
// Один и тот же у замка и у заслонки, которая растворяется после разблокировки, — шва не видно.
Item {
    id: bd
    readonly property bool wantImage: Prefs.lockBackground === "image" || Prefs.lockBackground === "wallpaper"
    readonly property bool useImage: wantImage && LockWall.source !== ""

    Rectangle { anchors.fill: parent; color: Theme.background }
    Rectangle {
        anchors.fill: parent
        visible: Prefs.lockBackground === "glow" || (bd.wantImage && !img.visible)
        gradient: Gradient {
            GradientStop { position: 0; color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.16) }
            GradientStop { position: 0.55; color: "transparent" }
        }
    }
    Item {
        anchors.fill: parent
        clip: true
        Image {
            id: img
            anchors.fill: parent
            anchors.margins: -Prefs.lockBlur   // размытый край прозрачен — пусть он будет за экраном
            visible: bd.useImage && status === Image.Ready
            source: bd.useImage ? LockWall.source : ""
            fillMode: Image.PreserveAspectCrop
            sourceSize.width: width
            sourceSize.height: height
            asynchronous: false   // заслонка создаётся за доли секунды до снятия замка — картинка должна быть готова
            cache: true
            layer.enabled: Prefs.lockBlur > 0
            layer.effect: MultiEffect { blurEnabled: true; blur: 1; blurMax: Prefs.lockBlur; autoPaddingEnabled: false }
        }
    }
    Rectangle {   // затемнение поверх картинки
        anchors.fill: parent
        visible: img.visible && Prefs.lockDim > 0
        color: Qt.rgba(0, 0, 0, Prefs.lockDim)
    }
}
