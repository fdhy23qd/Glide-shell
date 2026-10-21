import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import qs

// Чат с Claude: ответ приходит потоком из ai.py (JSON-строки), история хранится в ai-chat.json.
// Enter — отправить, Shift+Enter — новая строка. Текст из «Спросить ИИ» приходит через api.handoff.
ColumnLayout {
    id: chat
    property var api
    readonly property color accent: api && api.accent ? api.accent : Theme.accent   // акцент из настроек панели
    readonly property color accentText: api && api.accentText ? api.accentText : "#ffffff"   // текст на акценте
    property var info: ({ ready: false, label: "…", hint: "" })
    property bool busy: false
    property bool waiting: false          // запрос ушёл, первых слов ещё нет
    property string error: ""
    readonly property string script: decodeURIComponent(Qt.resolvedUrl("ai.py").toString().replace("file://", ""))
    spacing: 10

    function ai(args) { return ["python3", script].concat(args) }

    function send(text) {
        text = text.trim()
        if (!text || busy || !info.ready) return
        error = ""
        msgs.append({ role: "user", text: text })
        msgs.append({ role: "assistant", text: "" })
        busy = true
        waiting = true
        sendProc.environment = { QP_TEXT: text }
        sendProc.running = true
        view.stick = true
    }
    function stop() { if (sendProc.running) sendProc.signal(15) }
    function newChat() {
        if (busy) return
        msgs.clear()
        error = ""
        resetProc.running = true
    }
    function takeHandoff() {
        if (!api) return
        var h = api.takeHandoff("ai")
        if (!h) return
        var text = (h.prompt ? h.prompt + "\n\n" : "") + h.text
        if (info.ready && !busy) send(text); else input.text = text
    }

    ListModel { id: msgs }

    // ---- процессы ----
    Process {
        id: infoProc
        command: chat.ai(["info"])
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                try { chat.info = JSON.parse(text) } catch (e) {}
                chat.takeHandoff()
            }
        }
    }
    Process {
        id: historyProc
        command: chat.ai(["history"])
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                var list = []
                try { list = JSON.parse(text) } catch (e) {}
                if (chat.busy) return
                msgs.clear()
                for (var i = 0; i < list.length; i++) msgs.append({ role: list[i].role, text: list[i].text })
                view.stick = true
            }
        }
    }
    Process { id: resetProc; command: chat.ai(["reset"]) }
    Process {
        id: setupProc
        command: chat.ai(["setup-api"])
        stderr: StdioCollector { onStreamFinished: if (text.trim()) chat.error = text.trim().split("\n").pop() }
        onExited: infoProc.running = true
    }
    Process {
        id: sendProc
        command: chat.ai(["send"])
        stdout: SplitParser {
            onRead: (line) => {
                var e
                try { e = JSON.parse(line) } catch (err) { return }
                var last = msgs.count - 1
                if (e.t === "delta") {
                    chat.waiting = false
                    msgs.setProperty(last, "text", msgs.get(last).text + e.text)
                } else if (e.t === "error") {
                    chat.error = e.text
                }
            }
        }
        onExited: {
            chat.busy = false
            chat.waiting = false
            var last = msgs.count - 1
            if (last >= 0 && msgs.get(last).role === "assistant" && msgs.get(last).text === "") {
                // ответа нет: убираем пустой пузырь и возвращаем вопрос в поле ввода (ai.py тоже его не сохранил)
                msgs.remove(last)
                last = msgs.count - 1
                if (last >= 0 && msgs.get(last).role === "user") {
                    if (input.text === "") input.text = msgs.get(last).text
                    msgs.remove(last)
                }
            }
        }
    }

    Connections {
        target: chat.api
        function onHandoffChanged() { chat.takeHandoff() }
        function onShownChanged() {
            if (!chat.api.shown) return
            infoProc.running = true
            Qt.callLater(input.forceActiveFocus)
        }
    }
    Component.onCompleted: Qt.callLater(input.forceActiveFocus)

    // ---- шапка ----
    RowLayout {
        Layout.fillWidth: true
        spacing: 8
        Rectangle {
            id: dot
            implicitWidth: 8; implicitHeight: 8; radius: Theme.r(4)
            color: chat.info.ready ? Theme.success : Theme.warning
            SequentialAnimation on opacity {   // мягко «дышит», пока идёт ответ
                running: chat.busy
                loops: Animation.Infinite
                NumberAnimation { to: 0.3; duration: 500 }
                NumberAnimation { to: 1; duration: 500 }
                onRunningChanged: if (!running) dot.opacity = 1
            }
        }
        Text {
            Layout.fillWidth: true
            text: chat.info.label
            color: Theme.textSecondary
            font.pixelSize: Theme.fs(11)
            elide: Text.ElideRight
        }
        HeaderBtn { text: Tr.t("＋ Новый чат"); visible: msgs.count > 0; enabled: !chat.busy; onClicked: chat.newChat() }
    }

    component HeaderBtn: Rectangle {
        id: hb
        property alias text: hbt.text
        signal clicked()
        implicitWidth: hbt.implicitWidth + 16
        implicitHeight: 22
        radius: Theme.r(6)
        opacity: enabled ? 1 : Theme.disabledOpacity
        color: hbm.pressed ? Theme.surfacePressed : hbm.containsMouse ? Theme.surfaceHigher : Theme.surfaceHigh
        scale: hbm.pressed ? 0.94 : 1
        Behavior on color { ColorAnimation { duration: Prefs.ms(120) } }
        Behavior on scale { NumberAnimation { duration: Prefs.ms(140); easing.type: Easing.OutBack } }
        Text { id: hbt; anchors.centerIn: parent; color: Theme.textVariant; font.pixelSize: Theme.fs(11) }
        MouseArea { id: hbm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: if (hb.enabled) hb.clicked() }
    }

    // ---- не настроено ----
    Rectangle {
        visible: !chat.info.ready && chat.info.label !== "…"
        Layout.fillWidth: true
        implicitHeight: setupCol.implicitHeight + 20
        radius: Theme.r(10)
        color: Theme.errorContainer
        border.color: Theme.error
        ColumnLayout {
            id: setupCol
            anchors.fill: parent
            anchors.margins: 10
            spacing: 8
            Text {
                Layout.fillWidth: true
                text: chat.info.hint
                color: Theme.text
                wrapMode: Text.WordWrap
            }
            HeaderBtn {
                visible: chat.info.backend === "api"
                text: setupProc.running ? Tr.t("Устанавливаю…") : Tr.t("Настроить API")
                enabled: !setupProc.running
                onClicked: setupProc.running = true
            }
        }
    }

    // ---- сообщения ----
    ListView {
        id: view
        property bool stick: true   // держаться внизу, пока пользователь сам не прокрутил вверх
        Layout.fillWidth: true
        Layout.preferredHeight: msgs.count ? 380 : 0
        visible: msgs.count > 0
        clip: true
        spacing: 8
        model: msgs
        boundsBehavior: Flickable.StopAtBounds
        Behavior on Layout.preferredHeight { NumberAnimation { duration: Prefs.ms(220); easing.type: Easing.OutCubic } }
        onMovementEnded: stick = atYEnd
        onContentHeightChanged: if (stick) Qt.callLater(positionViewAtEnd)

        add: Transition {
            ParallelAnimation {
                NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Prefs.ms(220) }
                NumberAnimation { property: "scale"; from: 0.94; to: 1; duration: Prefs.ms(260); easing.type: Easing.OutBack }
            }
        }

        delegate: Item {
            id: row
            required property string role
            required property string text
            required property int index
            readonly property bool mine: role === "user"
            readonly property bool live: chat.busy && index === msgs.count - 1 && !mine
            width: view.width
            height: bubble.height

            Rectangle {
                id: bubble
                anchors.right: row.mine ? parent.right : undefined
                anchors.left: row.mine ? undefined : parent.left
                width: Math.min(row.width * (row.mine ? 0.85 : 1), body.implicitWidth + 24)
                height: Math.max(34, body.implicitHeight + 18)
                radius: Theme.r(12)
                color: row.mine ? Qt.rgba(chat.accent.r, chat.accent.g, chat.accent.b, 0.22) : Theme.surfaceHigh
                border.color: row.mine ? accent : Theme.outline
                transformOrigin: row.mine ? Item.Right : Item.Left

                TextEdit {   // TextEdit, а не Text: выделение мышью и копирование куска ответа
                    id: body
                    x: 12; y: 9
                    width: Math.min(implicitWidth, row.width * (row.mine ? 0.85 : 1) - 24)
                    readOnly: true
                    selectByMouse: true
                    wrapMode: TextEdit.Wrap
                    textFormat: row.mine ? TextEdit.PlainText : TextEdit.MarkdownText
                    text: row.text + (row.live && row.text !== "" ? " ▍" : "")
                    color: Theme.text
                    selectionColor: Qt.rgba(chat.accent.r, chat.accent.g, chat.accent.b, 0.42)
                    font.pixelSize: Theme.fs(13)
                    onLinkActivated: (link) => Qt.openUrlExternally(link)
                }

                Row {   // «печатает…», пока не пришли первые слова
                    visible: row.live && row.text === ""
                    anchors.centerIn: parent
                    spacing: 5
                    Repeater {
                        model: 3
                        delegate: Rectangle {
                            required property int index
                            width: 6; height: 6; radius: Theme.r(3)
                            color: Theme.textSecondary
                            SequentialAnimation on y {
                                loops: Animation.Infinite
                                PauseAnimation { duration: index * 140 }
                                NumberAnimation { from: 0; to: -5; duration: Prefs.ms(260); easing.type: Easing.OutQuad }
                                NumberAnimation { from: -5; to: 0; duration: Prefs.ms(260); easing.type: Easing.InQuad }
                                PauseAnimation { duration: (2 - index) * 140 + 200 }
                            }
                        }
                    }
                }

                Rectangle {   // копировать ответ целиком
                    id: copyBtn
                    Behavior on color { ColorAnimation { duration: Prefs.ms(140) } }
                    property bool done: false
                    opacity: !row.mine && !row.live && (bma.containsMouse || cma.containsMouse || done) ? 1 : 0
                    visible: opacity > 0
                    Behavior on opacity { NumberAnimation { duration: Prefs.ms(120) } }
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 4
                    width: 22; height: 22; radius: Theme.r(6)
                    color: cma.pressed ? Theme.surfacePressed : cma.containsMouse ? Theme.surfaceHigher : Theme.surfaceHigh
                    scale: cma.pressed ? 0.88 : 1
                    Behavior on scale { NumberAnimation { duration: Prefs.ms(140); easing.type: Easing.OutBack } }
                    Text { anchors.centerIn: parent; text: copyBtn.done ? "✓" : "⧉"; color: Theme.textVariant; font.pixelSize: Theme.fs(12) }
                    Timer { id: copiedT; interval: 1200; onTriggered: copyBtn.done = false }
                    MouseArea {
                        id: cma
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { chat.api.copy(row.text); copyBtn.done = true; copiedT.restart() }
                    }
                }
                MouseArea { id: bma; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.NoButton }
            }
        }
    }

    // ---- подсказки для пустого чата ----
    Flow {
        visible: msgs.count === 0 && chat.info.ready
        Layout.fillWidth: true
        spacing: 6
        Repeater {
            model: [
                { label: Tr.t("Объясни текст из буфера"), ctx: true, prompt: Tr.t("Объясни простыми словами:") },
                { label: Tr.t("Переведи буфер"), ctx: true, prompt: Tr.t("Переведи (русский ↔ английский):") },
                { label: Tr.t("Команда для терминала…"), ctx: false, prompt: Tr.t("Дай команду для терминала Linux: ") },
                { label: Tr.t("Регулярка…"), ctx: false, prompt: Tr.t("Напиши регулярное выражение, которое ") }
            ]
            delegate: Rectangle {
                id: sug
                required property var modelData
                required property int index
                visible: !modelData.ctx || chat.api.contextText !== ""
                width: sugText.implicitWidth + 22
                height: 28
                radius: Theme.r(14)
                color: sma.containsMouse ? Qt.rgba(chat.accent.r, chat.accent.g, chat.accent.b, 0.42) : Qt.rgba(chat.accent.r, chat.accent.g, chat.accent.b, 0.22)
                scale: sma.pressed ? 0.93 : 1
                Behavior on color { ColorAnimation { duration: Prefs.ms(120) } }
                Behavior on scale { NumberAnimation { duration: Prefs.ms(120) } }
                Text { id: sugText; anchors.centerIn: parent; text: sug.modelData.label; color: Theme.text; font.pixelSize: Theme.fs(12) }
                MouseArea {
                    cursorShape: Qt.PointingHandCursor
                    id: sma
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: {
                        if (sug.modelData.ctx) chat.send(sug.modelData.prompt + "\n\n" + chat.api.contextText)
                        else { input.text = sug.modelData.prompt; input.cursorPosition = input.length; input.forceActiveFocus() }
                    }
                }
            }
        }
    }

    Text {
        visible: chat.error !== ""
        Layout.fillWidth: true
        text: "⚠ " + chat.error
        color: Theme.error
        font.pixelSize: Theme.fs(12)
        wrapMode: Text.WordWrap
    }

    // ---- ввод ----
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: Math.min(140, Math.max(40, input.implicitHeight + 20))
        radius: Theme.r(10)
        color: Theme.surface
        border.width: input.activeFocus ? 2 : 1
        border.color: input.activeFocus ? chat.accent : inputHover.hovered ? Theme.outlineHover : Theme.outline
        opacity: chat.info.ready ? 1 : Theme.disabledOpacity
        HoverHandler { id: inputHover; cursorShape: Qt.IBeamCursor }
        Behavior on border.color { ColorAnimation { duration: Prefs.ms(160) } }
        Behavior on implicitHeight { NumberAnimation { duration: Prefs.ms(120) } }

        Text {
            x: 12
            anchors.verticalCenter: parent.verticalCenter
            visible: input.text === ""
            text: chat.busy ? Tr.t("Claude отвечает…") : Tr.t("Спроси что угодно…  Enter — отправить")
            color: Theme.textMuted
        }
        Flickable {
            id: inputFlick
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 44
            anchors.topMargin: 10
            anchors.bottomMargin: 10
            contentHeight: input.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            TextEdit {
                id: input
                width: inputFlick.width
                wrapMode: TextEdit.Wrap
                color: Theme.text
                selectionColor: Qt.rgba(chat.accent.r, chat.accent.g, chat.accent.b, 0.42)
                selectByMouse: true
                font.pixelSize: Theme.fs(13)
                enabled: chat.info.ready
                onCursorRectangleChanged: {   // держим курсор в видимой части поля
                    if (cursorRectangle.y < inputFlick.contentY) inputFlick.contentY = cursorRectangle.y
                    else if (cursorRectangle.y + cursorRectangle.height > inputFlick.contentY + inputFlick.height)
                        inputFlick.contentY = cursorRectangle.y + cursorRectangle.height - inputFlick.height
                }
                Keys.onPressed: (e) => {
                    if ((e.key === Qt.Key_Return || e.key === Qt.Key_Enter) && !(e.modifiers & Qt.ShiftModifier)) {
                        if (!chat.busy) { chat.send(input.text); input.text = "" }
                        e.accepted = true
                    }
                }
            }
        }

        Rectangle {   // отправить / остановить
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: 6
            width: 30; height: 28; radius: Theme.r(8)
            readonly property bool can: chat.busy || input.text.trim() !== ""
            color: chat.busy ? (sbm.containsMouse ? Theme.errorHover : Theme.errorContainer)
                             : (can ? (sbm.pressed ? Qt.darker(chat.accent, 1.15) : sbm.containsMouse ? Qt.lighter(chat.accent, 1.15) : chat.accent)
                                    : Theme.surfaceHigh)
            scale: sbm.pressed ? 0.9 : 1
            Behavior on color { ColorAnimation { duration: Prefs.ms(140) } }
            Behavior on scale { NumberAnimation { duration: Prefs.ms(110); easing.type: Easing.OutBack } }
            Text {
                Behavior on color { ColorAnimation { duration: Prefs.ms(140) } }
                anchors.centerIn: parent
                text: chat.busy ? "■" : "↑"
                color: chat.busy ? Theme.errorText : (parent.can ? accentText : Theme.textMuted)
                font.pixelSize: chat.busy ? 11 : 15
                font.bold: true
            }
            MouseArea {
                id: sbm
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: parent.can ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: {
                    if (chat.busy) chat.stop()
                    else { chat.send(input.text); input.text = "" }
                }
            }
        }
    }
}
