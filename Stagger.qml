import QtQuick

// Появление элемента: прозрачность + сдвиг снизу, с задержкой (для «лесенки» в списках).
// Stagger { id: st; target: parent; delay: index * 30 }  →  st.play() чтобы проиграть снова.
SequentialAnimation {
    id: a
    required property Item target
    property int delay: 0
    property real distance: 14
    property int duration: Prefs.ms(240)
    readonly property Translate shift: Translate {}

    function play() {
        target.opacity = 0
        shift.y = distance
        restart()
    }

    Component.onCompleted: {
        target.transform = [shift]
        play()
    }

    PauseAnimation { duration: Prefs.ms(Math.min(a.delay, 300)) }
    ParallelAnimation {
        NumberAnimation { target: a.target; property: "opacity"; to: 1; duration: Prefs.ms(a.duration); easing.type: Easing.OutCubic }
        NumberAnimation { target: a.shift; property: "y"; to: 0; duration: Prefs.ms(a.duration + 60); easing.type: Easing.OutCubic }
    }
}
