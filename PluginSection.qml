import QtQuick
import QtQuick.Layouts

// Карточка плагина: заголовок + элементы из manifest (+ необязательный QML-виджет).
ColumnLayout {
    id: section
    property var plugin
    property var panel
    readonly property bool shown: panel ? panel.shown : false
    spacing: 8
    visible: !!(plugin.qml || (plugin.items && plugin.items.length))

    Row {   // заголовок: значок (Nerd Font) + название
        spacing: 7
        Text {
            visible: !!plugin.icon
            anchors.verticalCenter: parent.verticalCenter
            text: plugin.icon || ""
            color: Prefs.accent
            font.family: Prefs.iconFont
            font.pixelSize: Theme.fs(14)
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: plugin.name
            color: Theme.textSecondary
            font.pixelSize: Theme.fs(12)
            font.bold: true
        }
    }

    Repeater {
        model: plugin.items || []
        delegate: Loader {
            required property var modelData
            Layout.fillWidth: true
            sourceComponent: modelData.type === "input" ? inputC
                           : modelData.type === "list" ? listC : buttonC
            onLoaded: {
                item.spec = modelData
                if (item.start) item.start()
            }
        }
    }

    Text {   // QML-плагин не собрался — показываем причину, а не пустой раздел
        id: qmlError
        visible: text !== ""
        Layout.fillWidth: true
        color: Theme.error
        font.pixelSize: Theme.fs(11)
        wrapMode: Text.Wrap
    }
    Loader {
        Layout.fillWidth: true
        visible: !!plugin.qml
        source: plugin.qml ? "file://" + plugin.dir + "/" + plugin.qml : ""
        onStatusChanged: if (status === Loader.Error)
            qmlError.text = Tr.t("Плагин не загрузился: ") + Qt.createComponent(source).errorString().trim()
        onLoaded: {
            item.api = scope
            if ("pluginDir" in item) item.pluginDir = plugin.dir   // QML-плагину — его папка
        }
    }

    ApiScope {   // свой API у каждого плагина: хранилище, настройки, уведомления — от его имени (docs/API.md)
        id: scope
        shell: section.panel
        owner: section.plugin.id
        ownerName: section.plugin.name
        manifest: section.plugin
    }

    function trigger(spec, text) { panel.run(plugin, spec, text) }

    // ---- кнопка ----
    Component {
        id: buttonC
        Rectangle {
            id: btn
            property var spec: ({})
            property bool armed: false   // "confirm": первое нажатие взводит, второе запускает
            implicitHeight: 36
            radius: Theme.radiusSm
            color: armed ? Theme.errorContainer : ma.pressed ? Theme.surfacePressed : (ma.containsMouse ? Theme.surfaceHigher : Theme.surfaceHigh)
            border.color: armed ? Theme.error : (ma.containsMouse ? Theme.divider : "transparent")
            Timer { id: disarm; interval: 3000; onTriggered: btn.armed = false }
            Rectangle {   // полоска обратного отсчёта подтверждения
                id: countdownBar
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.margins: 3
                height: 2
                radius: Theme.r(1)
                color: Theme.error
                visible: btn.armed
            }
            NumberAnimation {
                id: countdown
                target: countdownBar; property: "width"
                from: btn.width - 6; to: 0; duration: disarm.interval
            }
            scale: ma.pressed ? 0.97 : 1
            Behavior on color { ColorAnimation { duration: Prefs.ms(120) } }
            Behavior on border.color { ColorAnimation { duration: Prefs.ms(120) } }
            Behavior on scale { NumberAnimation { duration: Prefs.ms(110); easing.type: Easing.OutCubic } }
            Text {
                Behavior on color { ColorAnimation { duration: Prefs.ms(140) } }
                anchors.centerIn: parent
                text: btn.armed ? Tr.t("Нажми ещё раз: ") + (spec.label || "")
                                : (spec.icon ? spec.icon + "  " : "") + (spec.label || "")
                color: btn.armed ? Theme.errorText : Theme.text
            }
            MouseArea {
                id: ma
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (spec.confirm && !btn.armed) { btn.armed = true; disarm.restart(); countdown.restart(); return }
                    btn.armed = false
                    section.trigger(spec, "")
                }
            }
        }
    }

    // ---- поле ввода ----
    Component {
        id: inputC
        Rectangle {
            id: box
            property var spec: ({})
            implicitHeight: 38
            radius: Theme.radiusSm
            color: Theme.surface
            property bool flash: false   // короткая зелёная вспышка после Enter
            border.width: ti.activeFocus ? 2 : 1
            border.color: flash ? Theme.success : ti.activeFocus ? Prefs.accent : tiHover.hovered ? Theme.outlineHover : Theme.outline
            HoverHandler { id: tiHover; cursorShape: Qt.IBeamCursor }
            Behavior on border.color { ColorAnimation { duration: Prefs.ms(180) } }
            Timer { id: flashT; interval: 450; onTriggered: box.flash = false }
            function start() { if (section.shown && section.panel.preferItemFocus && spec.autofocus) Qt.callLater(ti.forceActiveFocus) }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                x: ti.text === "" ? 10 : 20
                opacity: ti.text === "" ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Prefs.ms(120) } }
                Behavior on x { NumberAnimation { duration: Prefs.ms(160); easing.type: Easing.OutCubic } }
                text: box.spec.placeholder || ""
                color: Theme.textMuted
            }
            TextInput {
                id: ti
                anchors.fill: parent
                anchors.margins: 10
                verticalAlignment: TextInput.AlignVCenter
                color: Theme.text
                clip: true
                onAccepted: {
                    if (text.trim() !== "") { box.flash = true; flashT.restart(); section.trigger(box.spec, text); text = "" }
                }
            }
            Connections {
                target: section
                function onShownChanged() { box.start() }
            }
        }
    }

    // ---- список ----
    // stdout команды "list": одна запись на строку. "значение<TAB>подпись" — показывается подпись,
    // в {text} уходит значение; третье поле "<TAB>/путь/к/картинке" — строка с миниатюрой.
    // С "filter": true сверху появляется поиск (Enter — первая запись).
    Component {
        id: listC
        ColumnLayout {
            id: lc
            property var spec: ({})
            property var entries: []
            property string query: ""
            spacing: 4

            readonly property var shownEntries: {
                var q = query.toLowerCase(), out = [], max = spec.max || 15
                for (var i = 0; i < entries.length && out.length < max; i++)
                    if (q === "" || entries[i].label.toLowerCase().indexOf(q) >= 0) out.push(entries[i])
                return out
            }

            function start() { refresh(); if (section.shown && section.panel.preferItemFocus && spec.autofocus && spec.filter) Qt.callLater(fi.forceActiveFocus) }
            function refresh() { if (spec.list) lp.running = true }

            OutputProcess {
                id: lp
                argv: lc.spec.list ? section.panel.expand(lc.spec.list, section.plugin.dir, "") : []
                onDone: function(t) {
                    lc.entries = t.split("\n").filter(l => l.length).map(l => {
                        var p = l.split("\t")
                        return { value: p[0], label: p.length > 1 ? p[1] : p[0], image: p[2] || "" }
                    })
                }
            }
            Connections {
                target: section
                function onShownChanged() { if (section.shown) lc.start() }
            }
            Connections {
                target: section.panel
                function onRefresh() { lc.refresh() }
            }

            Rectangle {
                visible: !!lc.spec.filter
                Layout.fillWidth: true
                implicitHeight: 34
                radius: Theme.radiusSm
                color: Theme.surface
                border.width: fi.activeFocus ? 2 : 1
                border.color: fi.activeFocus ? Prefs.accent : fiHover.hovered ? Theme.outlineHover : Theme.outline
                HoverHandler { id: fiHover; cursorShape: Qt.IBeamCursor }
                Behavior on border.color { ColorAnimation { duration: Prefs.ms(160) } }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    x: 10
                    opacity: fi.text === "" ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: Prefs.ms(120) } }
                    text: Tr.t("Поиск…")
                    color: Theme.textMuted
                }
                TextInput {
                    id: fi
                    anchors.fill: parent
                    anchors.margins: 10
                    verticalAlignment: TextInput.AlignVCenter
                    color: Theme.text
                    clip: true
                    onTextChanged: lc.query = text
                    onAccepted: if (lc.shownEntries.length) section.trigger(lc.spec, lc.shownEntries[0].value)
                }
            }

            EmptyState {   // пусто или фильтр ничего не нашёл
                visible: lc.shownEntries.length === 0
                Layout.fillWidth: true
                compact: true
                glyph: lc.query ? 0xF0349 : lc.spec.emptyIcon ? parseInt(lc.spec.emptyIcon, 16) : 0xF0219
                text: lc.query ? Tr.t("Ничего не найдено") : (lc.spec.empty || Tr.t("Пусто"))
            }
            Repeater {
                model: lc.shownEntries
                delegate: Rectangle {
                    id: row
                    required property var modelData
                    readonly property bool pic: modelData.image !== ""
                    Layout.fillWidth: true
                    implicitHeight: pic ? 64 : 32
                    radius: Theme.radiusSm
                    color: lma.pressed ? Theme.surfacePressed : (lma.containsMouse ? Theme.surfaceHigher : Theme.surfaceHigh)
                    scale: lma.pressed ? 0.98 : 1
                    Behavior on color { ColorAnimation { duration: Prefs.ms(110) } }
                    Behavior on scale { NumberAnimation { duration: Prefs.ms(100) } }
                    Rectangle {   // миниатюра; декодируем под размер, а не целиком
                        visible: row.pic
                        x: 6; anchors.verticalCenter: parent.verticalCenter
                        width: 72; height: 52; radius: Theme.r(8)
                        color: Theme.surface
                        clip: true
                        Image {
                            anchors.fill: parent
                            source: row.pic ? "file://" + row.modelData.image : ""
                            sourceSize.width: 144; sourceSize.height: 104
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                        }
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        x: (row.pic ? 88 : 10) + (lma.containsMouse ? 4 : 0)
                        Behavior on x { NumberAnimation { duration: Prefs.ms(140); easing.type: Easing.OutCubic } }
                        width: parent.width - x - 10
                        elide: Text.ElideRight
                        text: modelData.label
                        color: Theme.text
                    }
                    MouseArea {
                        cursorShape: Qt.PointingHandCursor
                        id: lma
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: section.trigger(lc.spec, modelData.value)
                    }
                }
            }
        }
    }
}
