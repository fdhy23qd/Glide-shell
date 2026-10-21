import QtQuick

// Плагин с полностью своим интерфейсом. Ядро выставляет свойство `api`:
//   api.run(["команда", "арг"], "текст")  — запустить процесс
//   api.close()                            — спрятать панель
Item {
    property var api
    implicitHeight: 40
    Rectangle {
        anchors.fill: parent; radius: 12
        color: api ? api.accent : "#7b61ff"          // акцент и текст на нём — из настроек Glide Shell
        Text { anchors.centerIn: parent; text: "Привет из плагина"; color: api ? api.accentText : "#ffffff" }
        MouseArea {
            anchors.fill: parent
            onClicked: api.run(["notify-send", "Hello", "из QML-плагина"])
        }
    }
}
