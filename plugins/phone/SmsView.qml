import QtQuick
import QtQuick.Layouts
import Quickshell
import qs

// SMS телефона через Glide Link: список диалогов → переписка с ответом; «Новое» — номер и текст.
// Данные — у телефона (демон спрашивает его по запросу); новые входящие поднимают sms_rev — открытое перечитывается.
ColumnLayout {
    id: sv
    property var device: null          // устройство Phones (Glide Link)
    signal back()
    spacing: 8

    property string mode: "list"       // list | thread | new
    property var conversations: []
    property var thread: null          // {thread_id, address, contact}
    property var messages: []
    property bool loading: false
    property string error: ""
    property bool sending: false
    readonly property int rev: device && device.sms_rev !== undefined ? device.sms_rev : 0
    onRevChanged: reload()
    Component.onCompleted: loadList()

    function nf(code) { return String.fromCodePoint(code) }
    function when(ms) {
        if (!ms) return ""
        var d = new Date(ms), now = new Date()
        return d.toDateString() === now.toDateString() ? Qt.formatDateTime(d, "HH:mm") : Qt.formatDateTime(d, "dd.MM HH:mm")
    }
    function reload() { if (mode === "thread") loadThread(); else if (mode === "list") loadList() }
    function loadList() {
        if (!device) return
        loading = conversations.length === 0
        Phones.request({ cmd: "sms-list", device: device.id }, r => {
            loading = false
            error = r.ok ? "" : (r.error || Tr.t("Не удалось получить SMS"))
            if (r.ok) conversations = r.conversations || []
        })
    }
    function open(c) {
        thread = c
        messages = []
        mode = "thread"
        loadThread()
    }
    function loadThread() {
        if (!device || !thread) return
        loading = messages.length === 0
        Phones.request({ cmd: "sms-read", device: device.id, thread: String(thread.thread_id), limit: 60 }, r => {
            loading = false
            error = r.ok ? "" : (r.error || Tr.t("Не удалось получить переписку"))
            if (r.ok) { messages = r.messages || []; Qt.callLater(() => list.positionViewAtEnd()) }
        })
    }
    function send(address, text, done) {
        if (!device || !address.trim() || !text.trim() || sending) return
        sending = true
        Phones.request({ cmd: "sms-send", device: device.id, address: address.trim(), text: text, timeout: 45 }, r => {
            sending = false
            var res = r.result || {}
            if (r.ok && res.ok) {
                error = ""
                if (done) done()
                if (mode === "thread") {
                    messages = messages.concat([{ id: "local" + Date.now(), body: text, date: Date.now(), outgoing: true }])
                    Qt.callLater(() => list.positionViewAtEnd())
                } else loadList()
            } else error = Tr.t("Не отправлено: ") + (res.error || r.error || "")
        })
    }

    // ---- шапка ----
    RowLayout {
        Layout.fillWidth: true
        spacing: 8
        Btn {
            glyph: sv.nf(0xF004D)
            onClicked: { if (sv.mode === "list") sv.back(); else { sv.mode = "list"; sv.loadList() } }
        }
        Text {
            Layout.fillWidth: true
            text: sv.mode === "thread" && sv.thread ? (sv.thread.contact || sv.thread.address)
                : sv.mode === "new" ? Tr.t("Новое сообщение") : Tr.t("Сообщения")
            color: Theme.text; font.pixelSize: Theme.fs(15); font.bold: true
            elide: Text.ElideRight
        }
        Btn { visible: sv.mode === "list"; glyph: sv.nf(0xF0450); onClicked: sv.loadList() }
        Btn { visible: sv.mode === "list"; glyph: sv.nf(0xF0415); label: Tr.t("Новое"); onClicked: sv.mode = "new" }
    }
    Text {
        visible: !!sv.error
        Layout.fillWidth: true
        text: sv.error
        color: Theme.error; font.pixelSize: Theme.fs(12)
        wrapMode: Text.Wrap
    }
    Text {
        visible: sv.loading
        text: Tr.t("Спрашиваю телефон…")
        color: Theme.textMuted; font.pixelSize: Theme.fs(12)
    }

    // ---- диалоги ----
    Repeater {
        model: sv.mode === "list" ? sv.conversations : []
        delegate: Rectangle {
            id: row
            required property var modelData
            Layout.fillWidth: true
            implicitHeight: 56
            radius: Theme.radiusMd
            color: rm.containsMouse ? Theme.surfaceHigher : Theme.surfaceHigh
            Behavior on color { ColorAnimation { duration: Prefs.ms(120) } }
            Rectangle {   // буква контакта
                x: 10; anchors.verticalCenter: parent.verticalCenter
                width: 36; height: 36; radius: 18
                color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.22)
                Text {
                    anchors.centerIn: parent
                    text: (row.modelData.contact || row.modelData.address || "?").charAt(0).toUpperCase()
                    color: Theme.accent; font.pixelSize: Theme.fs(15); font.bold: true
                }
            }
            Column {
                x: 56; anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 56 - 70
                Text {
                    width: parent.width
                    text: row.modelData.contact || row.modelData.address
                    color: Theme.text; font.pixelSize: Theme.fs(13); font.bold: !row.modelData.read
                    elide: Text.ElideRight
                }
                Text {
                    width: parent.width
                    text: (row.modelData.snippet || "").replace(/\n/g, " ")
                    color: row.modelData.read ? Theme.textMuted : Theme.textSecondary; font.pixelSize: Theme.fs(12)
                    elide: Text.ElideRight
                }
            }
            Column {
                anchors.right: parent.right; anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                spacing: 4
                Text { anchors.right: parent.right; text: sv.when(row.modelData.date); color: Theme.textMuted; font.pixelSize: Theme.fs(11) }
                Rectangle { anchors.right: parent.right; visible: !row.modelData.read; width: 8; height: 8; radius: 4; color: Theme.accent }
            }
            MouseArea { id: rm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: sv.open(row.modelData) }
        }
    }
    Text {
        visible: sv.mode === "list" && !sv.loading && !sv.error && sv.conversations.length === 0
        text: Tr.t("Сообщений нет — или у Glide Link на телефоне нет разрешения на SMS")
        color: Theme.textMuted; font.pixelSize: Theme.fs(12)
        Layout.fillWidth: true; wrapMode: Text.Wrap
    }

    // ---- переписка ----
    ListView {
        id: list
        visible: sv.mode === "thread"
        Layout.fillWidth: true
        Layout.preferredHeight: 300
        clip: true
        spacing: 6
        model: sv.mode === "thread" ? sv.messages : []
        boundsBehavior: Flickable.StopAtBounds
        delegate: Item {
            id: msg
            required property var modelData
            width: ListView.view.width
            height: bubble.height
            Rectangle {
                id: bubble
                readonly property bool mine: !!msg.modelData.outgoing
                anchors.right: mine ? parent.right : undefined
                anchors.left: mine ? undefined : parent.left
                width: Math.min(msg.width * 0.82, body.implicitWidth + 24)
                height: body.height + stamp.height + 16
                radius: Theme.radiusMd
                color: mine ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.28) : Theme.surfaceHigh
                Text {
                    id: body
                    x: 12; y: 8
                    width: Math.min(msg.width * 0.82 - 24, implicitWidth)
                    text: msg.modelData.body || ""
                    color: Theme.text; font.pixelSize: Theme.fs(13)
                    wrapMode: Text.Wrap
                    textFormat: Text.PlainText
                }
                Text {
                    id: stamp
                    anchors.right: parent.right; anchors.rightMargin: 10
                    anchors.top: body.bottom; anchors.topMargin: 2
                    text: sv.when(msg.modelData.date)
                    color: Theme.textMuted; font.pixelSize: Theme.fs(10)
                }
            }
        }
    }

    // ---- новое: номер ----
    Field {
        id: toField
        visible: sv.mode === "new"
        Layout.fillWidth: true
        hint: Tr.t("Номер телефона")
    }
    // ---- ввод текста ----
    RowLayout {
        visible: sv.mode !== "list"
        Layout.fillWidth: true
        spacing: 8
        Field {
            id: textField
            Layout.fillWidth: true
            hint: sv.sending ? Tr.t("Отправляю…") : Tr.t("Сообщение → Enter")
            onAccepted: sv.submit()
        }
        Btn { glyph: sv.nf(0xF048A); onClicked: sv.submit() }
    }
    function submit() {
        var addr = mode === "new" ? toField.text : (thread ? thread.address : "")
        var text = textField.text
        send(addr, text, () => { textField.text = ""; if (mode === "new") { toField.text = ""; mode = "list" } })
    }

    component Btn: Rectangle {
        id: b
        property string glyph
        property string label: ""
        signal clicked()
        implicitWidth: label ? row2.implicitWidth + 20 : 34
        implicitHeight: 34
        radius: Theme.radiusMd
        color: bm.pressed ? Theme.surfacePressed : bm.containsMouse ? Theme.surfaceHigher : Theme.surfaceHigh
        Behavior on color { ColorAnimation { duration: Prefs.ms(120) } }
        Row {
            id: row2
            anchors.centerIn: parent
            spacing: 6
            Text { anchors.verticalCenter: parent.verticalCenter; text: b.glyph; color: Theme.accent; font.family: Prefs.iconFont; font.pixelSize: Theme.fs(16) }
            Text { visible: !!b.label; anchors.verticalCenter: parent.verticalCenter; text: b.label; color: Theme.text; font.pixelSize: Theme.fs(12) }
        }
        MouseArea { id: bm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: b.clicked() }
    }
    component Field: Rectangle {
        id: f
        property string hint
        property alias text: input.text
        signal accepted()
        implicitHeight: 38
        radius: Theme.radiusMd
        color: Theme.surface
        border.width: input.activeFocus ? 2 : 1
        border.color: input.activeFocus ? Theme.accent : Theme.outline
        Behavior on border.color { ColorAnimation { duration: Prefs.ms(150) } }
        TextInput {
            id: input
            anchors.left: parent.left; anchors.right: parent.right
            anchors.leftMargin: 12; anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            color: Theme.text; font.pixelSize: Theme.fs(13)
            clip: true
            onAccepted: f.accepted()
            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: !input.text
                text: f.hint
                color: Theme.textMuted; font.pixelSize: Theme.fs(12)
            }
        }
    }
}
