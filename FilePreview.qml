import QtQuick

// Быстрый просмотр файла под строкой поиска: картинка, первая страница PDF, кадр видео, начало текста,
// содержимое папки; внизу — размер и дата. Данные — tools/glide-preview.py (info: null — ещё грузится).
Item {
    id: fp
    property var info: null
    readonly property string kind: info ? info.kind : ""
    readonly property bool hasImage: !!info && !!info.image
    implicitHeight: body.implicitHeight
    height: implicitHeight

    function human(b) {
        var u = [Tr.t("Б"), Tr.t("КБ"), Tr.t("МБ"), Tr.t("ГБ")], i = 0
        while (b >= 1024 && i < u.length - 1) { b /= 1024; i++ }
        return (i === 0 ? String(b) : Tr.num(b, b < 10 ? 1 : 0)) + " " + u[i]
    }

    Column {
        id: body
        width: parent.width
        spacing: 6

        Text {
            visible: !fp.info
            text: Tr.t("Загрузка…")
            color: Theme.textMuted; font.pixelSize: Theme.fs(12)
            height: 40; verticalAlignment: Text.AlignVCenter
        }

        Rectangle {   // картинка, страница PDF, кадр видео
            visible: fp.hasImage
            width: parent.width
            height: visible ? Math.min(240, Math.max(80, img.implicitHeight > 0 ? width * img.implicitHeight / img.implicitWidth : 160)) : 0
            radius: Theme.r(10)
            color: Theme.background
            clip: true
            Image {
                id: img
                anchors.fill: parent
                anchors.margins: 2
                source: fp.hasImage ? "file://" + fp.info.image : ""
                sourceSize.width: 720
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                cache: false
                opacity: status === Image.Ready ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Prefs.ms(160) } }
            }
            Rectangle {   // видео — значок «смотреть»
                visible: fp.kind === "video"
                anchors.centerIn: parent
                width: 44; height: 44; radius: 22
                color: Qt.rgba(0, 0, 0, 0.5)
                Text { anchors.centerIn: parent; text: String.fromCodePoint(0xF040A); color: "#ffffff"
                       font.family: Prefs.iconFont; font.pixelSize: 22 }
            }
        }

        Rectangle {   // начало текстового файла
            visible: fp.kind === "text" && !!fp.info.text
            width: parent.width
            height: visible ? Math.min(textBody.implicitHeight + 16, 200) : 0
            radius: Theme.r(10)
            color: Theme.background
            clip: true
            Text {
                id: textBody
                x: 10; y: 8
                width: parent.width - 20
                text: fp.info && fp.info.text ? fp.info.text : ""
                textFormat: Text.PlainText
                color: Theme.textVariant
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: Theme.fs(11)
                wrapMode: Text.NoWrap
                elide: Text.ElideRight
            }
        }

        Flow {   // что в папке
            visible: fp.kind === "dir"
            width: parent.width
            spacing: 4
            Repeater {
                model: fp.kind === "dir" ? fp.info.items : []
                delegate: Rectangle {
                    required property string modelData
                    width: Math.min(itemText.implicitWidth + 16, fp.width)
                    height: 24; radius: 12
                    color: Theme.surface
                    Text {
                        id: itemText
                        anchors.centerIn: parent
                        width: Math.min(implicitWidth, fp.width - 16)
                        text: modelData
                        color: Theme.textVariant; font.pixelSize: Theme.fs(11)
                        elide: Text.ElideMiddle; textFormat: Text.PlainText
                    }
                }
            }
        }

        Text {   // размер · дата (у папки — сколько внутри)
            visible: !!fp.info && fp.kind !== "error"
            width: parent.width
            text: !fp.info ? "" : (fp.kind === "dir" ? Tr.t("Внутри: ") + fp.info.count : fp.human(fp.info.size))
                  + "  ·  " + Tr.t("изменён ") + Tr.date(new Date(fp.info.modified * 1000), "d MMMM yyyy, HH:mm")
                  + (fp.kind === "other" ? "  ·  " + Tr.t("Enter — открыть") : "")
            color: Theme.textMuted; font.pixelSize: Theme.fs(11)
            elide: Text.ElideRight
        }
        Text {
            visible: fp.kind === "error"
            text: Tr.t("Не открывается: ") + (fp.info ? fp.info.error : "")
            color: Theme.error; font.pixelSize: Theme.fs(12)
        }
    }
}
