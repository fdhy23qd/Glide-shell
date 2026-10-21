import QtQuick
import Quickshell

// Фон экрана блокировки (настройка «Фон»): сияние акцента сверху, сплошной цвет или своя картинка
// с затемнением (текст должен читаться). Один и тот же у замка и у заслонки, которая растворяется
// после разблокировки, — шва не видно.
Item {
    id: bd
    readonly property bool useImage: Prefs.lockBackground === "image" && Prefs.lockImage !== ""

    Rectangle { anchors.fill: parent; color: Theme.background }
    Rectangle {
        anchors.fill: parent
        visible: Prefs.lockBackground === "glow" || (Prefs.lockBackground === "image" && img.status !== Image.Ready)
        gradient: Gradient {
            GradientStop { position: 0; color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.16) }
            GradientStop { position: 0.55; color: "transparent" }
        }
    }
    Image {
        id: img
        anchors.fill: parent
        visible: bd.useImage && status === Image.Ready
        source: bd.useImage ? (Prefs.lockImage.indexOf("://") > 0 ? Prefs.lockImage
                               : "file://" + Prefs.lockImage.replace(/^~/, Quickshell.env("HOME"))) : ""
        fillMode: Image.PreserveAspectCrop
        sourceSize.width: width
        sourceSize.height: height
        asynchronous: false   // заслонка создаётся за доли секунды до снятия замка — картинка должна быть готова
        cache: true
    }
    Rectangle {   // затемнение поверх картинки
        anchors.fill: parent
        visible: img.visible
        color: Qt.rgba(0, 0, 0, 0.45)
    }
}
