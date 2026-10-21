import QtQuick
import QtQml
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower

// Окно панели: фигура (blob), перетекающая из острова, рейка категорий, поиск, контекстные действия,
// разделы плагинов, настройки. Состояние и логика — в shell.qml (свойство root), здесь — разметка.
PanelWindow {
    id: win
    // ядро (shell.qml): всё состояние панели — там, здесь — только вид; обращения — root.…
    required property var root
    readonly property bool blobSettled: blob.settled          // фигура совпала с островом (root.blobAtCompact)
    function clearSearchUi() { searchInput.text = ""; content.forceActiveFocus() }
    function clearSearchField() { searchInput.text = "" }
    function setSearch(t) { searchInput.text = t; searchInput.cursorPosition = t.length }   // IPC search
    screen: root.panelScreen
    visible: root.shown || root.reveal > 0 || root.islandClosing
    anchors { top: true; bottom: true; left: true; right: true }
    // под баром остров и панель отсчитывают координаты от одного края — фигура совпадает
    exclusionMode: root.island && !root.islandOver ? ExclusionMode.Normal : ExclusionMode.Ignore
    // закрываясь, окно не мешает мыши: клики уходят окнам под ним и острову
    mask: root.shown ? null : noInput
    readonly property Region noInput: Region {}
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    WlrLayershell.namespace: "glide-panel"
    color: "transparent"

    Item {
        id: content
        anchors.fill: parent
        focus: true

        // Esc — очистить поиск/закрыть; Ctrl+K — поиск; Alt+1..9, Alt+←/→ — категории;
        // обычная печать, когда фокус не в поле, уходит в поиск
        Keys.onPressed: (e) => {
            var mods = e.modifiers
            if (e.key === Qt.Key_Escape) {
                if (root.query !== "") root.clearSearch(); else root.close()
                e.accepted = true
            } else if ((mods & Qt.ControlModifier) && e.key === Qt.Key_K) {
                searchInput.forceActiveFocus(); e.accepted = true
            } else if (mods & Qt.AltModifier) {
                if (e.key >= Qt.Key_1 && e.key <= Qt.Key_9) { root.pick(e.key - Qt.Key_1); e.accepted = true }
                else if (e.key === Qt.Key_Right) { root.step(1); e.accepted = true }
                else if (e.key === Qt.Key_Left) { root.step(-1); e.accepted = true }
                else if (e.key === Qt.Key_Down || e.key === Qt.Key_PageDown) { root.flipPage(1); e.accepted = true }
                else if (e.key === Qt.Key_Up || e.key === Qt.Key_PageUp) { root.flipPage(-1); e.accepted = true }
                else if (e.key === Qt.Key_Comma) { root.openSettings(); e.accepted = true }
            } else if (content.activeFocus && e.text.length === 1 && e.text.charCodeAt(0) >= 32
                       && !(mods & (Qt.ControlModifier | Qt.MetaModifier))) {
                searchInput.forceActiveFocus()
                searchInput.insert(searchInput.length, e.text)
                e.accepted = true
            }
        }

        Rectangle {   // лёгкое затемнение и «виньетка» со стороны панели (в острове — сверху)
            anchors.fill: parent
            opacity: Prefs.dim ? root.reveal : 0
            gradient: Gradient {
                orientation: root.island ? Gradient.Vertical : Gradient.Horizontal
                GradientStop { position: 0.0; color: root.island ? "#59000000" : "#14000000" }
                GradientStop { position: 1.0; color: root.island ? "#14000000" : "#59000000" }
            }
        }

        MouseArea { anchors.fill: parent; enabled: root.shown; onClicked: root.close() }

        // Фигура острова: из компактного острова пружиной перетекает в панель и обратно.
        // Пока закрыта, повторяет геометрию острова, поэтому старт всегда с того же места.
        Rectangle {
            id: blob
            visible: root.island
            readonly property int openW: Math.max(card.width, rail.width + 16)
            readonly property int openH: rail.height + 4 + card.height
            readonly property bool settled: Math.abs(width - root.compactW) < 1 && Math.abs(height - root.compactH) < 1
            // остров под фигурой показывается, как только она с ним совпала, а окно панели
            // гаснет чуть позже — так между ними не бывает пустого кадра
            onSettledChanged: if (settled && !root.shown) closeDone.restart()
            Timer { id: closeDone; interval: 120; onTriggered: if (blob.settled && !root.shown) root.islandClosing = false }
            x: Math.round((parent.width - width) / 2)
            y: root.islandTop
            width: root.shown ? openW : root.compactW
            height: root.shown ? openH : root.compactH
            radius: Math.min(height / 2, root.shown ? root.islandRadius : root.compactRadius)
            Behavior on radius { NumberAnimation { duration: Prefs.ms(180); easing.type: Easing.OutCubic } }
            // цвет камеры/микрофона — только у острова; раскрытая панель — обычным фоном
            color: root.shown ? Theme.backgroundBar : root.islandColor
            border.color: root.shown ? Theme.outline : root.islandBorder
            Behavior on color { ColorAnimation { duration: Prefs.ms(220) } }
            Behavior on border.color { ColorAnimation { duration: Prefs.ms(220) } }
            clip: true
            // открытие — с отскоком, закрытие — мягко, без провала меньше острова
            Behavior on width { enabled: Prefs.anim > 0; Spring { bounce: root.shown ? 0.3 : 0.06; speed: root.shown ? 1 : 1.25 } }
            Behavior on height { enabled: Prefs.anim > 0; Spring { bounce: root.shown ? 0.22 : 0.04; speed: root.shown ? 0.85 : 1.2 } }
            MouseArea { anchors.fill: parent }   // клик по фигуре не закрывает панель
        }

        // Рейка категорий у самого края: страницы по Prefs.perPage, внизу — настройки.
        // В острове — горизонтальная строка вкладок вверху фигуры.
        Rectangle {
            id: rail
            readonly property bool horiz: root.island
            parent: horiz ? blob : content
            width: horiz ? railCol.implicitWidth + 16 : 48
            height: railCol.implicitHeight + 16
            // координаты, а не anchors: при смене вида рейка и карточка переезжают в другой
            // контейнер, и anchors между ними в этот момент рвутся без восстановления
            x: horiz ? Math.round((parent.width - width) / 2) : parent.width - width - 16
            y: horiz ? 4 : root.edgeTop + Math.round((parent.height - root.edgeTop - height) / 2)
            radius: Theme.radiusLg
            color: horiz ? "transparent" : Theme.backgroundBar
            border.color: horiz ? "transparent" : Theme.outline
            opacity: root.contentReveal
            transform: Translate {
                x: rail.horiz ? 0 : (1 - root.reveal) * 72
                y: rail.horiz ? -(1 - root.contentReveal) * 10 : 0
            }
            Behavior on height { enabled: !rail.horiz; NumberAnimation { duration: Prefs.ms(220); easing.type: Easing.OutCubic } }

            MouseArea {   // колесо листает страницы категорий
                anchors.fill: parent
                onWheel: (w) => {
                    if (wheelCool.running || root.pageCount < 2) return
                    var d = w.angleDelta.y !== 0 ? w.angleDelta.y : -w.angleDelta.x
                    if (Math.abs(d) < 30) return
                    root.flipPage(d < 0 ? 1 : -1)
                    wheelCool.restart()
                }
                Timer { id: wheelCool; interval: 280 }
            }

            component RailBtn: Rectangle {
                id: rb
                property string glyph
                property bool active: true
                property int size: 36
                property int glyphSize: 18
                property bool horiz: false
                signal clicked()
                width: horiz ? size : 36; height: horiz ? 36 : size; radius: Theme.radiusSm
                opacity: active ? 1 : 0.25
                color: rbm.containsMouse && active ? Theme.surfaceHigher : "transparent"
                scale: rbm.pressed && active ? 0.88 : 1
                Behavior on color { ColorAnimation { duration: Prefs.ms(140) } }
                Behavior on scale { NumberAnimation { duration: Prefs.ms(140); easing.type: Easing.OutBack } }
                Behavior on opacity { NumberAnimation { duration: Prefs.ms(160) } }
                Text { anchors.centerIn: parent; text: rb.glyph; color: Theme.textVariant; font.pixelSize: rb.glyphSize }
                MouseArea { id: rbm; anchors.fill: parent; hoverEnabled: true; cursorShape: rb.active ? Qt.PointingHandCursor : Qt.ArrowCursor; onClicked: if (rb.active) rb.clicked() }
            }

            Grid {
                id: railCol
                anchors.centerIn: parent
                columns: rail.horiz ? 20 : 1
                spacing: 6
                horizontalItemAlignment: Grid.AlignHCenter
                verticalItemAlignment: Grid.AlignVCenter

                RailBtn {
                    visible: root.pageCount > 1
                    horiz: rail.horiz
                    glyph: rail.horiz ? "‹" : "︿"; size: 22; glyphSize: rail.horiz ? 18 : 13
                    active: root.railPage > 0
                    onClicked: root.flipPage(-1)
                }

                Item {   // иконки текущей страницы + переезжающая подсветка
                    id: pageBox
                    width: rail.horiz ? pageCol.implicitWidth : 36
                    height: rail.horiz ? 36 : pageCol.implicitHeight
                    readonly property int localIndex: root.categoryIndex - root.railPage * Prefs.perPage
                    readonly property bool onPage: localIndex >= 0 && localIndex < root.pageCategories.length

                    Rectangle {
                        id: railHi
                        width: 36; height: 36; radius: Theme.radiusSm
                        readonly property real slot: Math.max(0, Math.min(pageBox.localIndex, root.pageCategories.length - 1)) * 42
                        x: rail.horiz ? slot : 0
                        y: rail.horiz ? 0 : slot
                        color: Prefs.accent
                        opacity: pageBox.onPage && root.query === "" && !root.settingsOpen ? 1 : 0
                        scale: opacity > 0 ? 1 : 0.6
                        Behavior on x { NumberAnimation { duration: Prefs.ms(280); easing.type: Easing.OutBack; easing.overshoot: 1.2 } }
                        Behavior on y { NumberAnimation { duration: Prefs.ms(280); easing.type: Easing.OutBack; easing.overshoot: 1.2 } }
                        Behavior on opacity { NumberAnimation { duration: Prefs.ms(160) } }
                        Behavior on scale { NumberAnimation { duration: Prefs.ms(200); easing.type: Easing.OutCubic } }
                    }

                    Grid {
                        id: pageCol
                        columns: rail.horiz ? 20 : 1
                        spacing: 6
                        Repeater {
                            model: root.pageCategories
                            delegate: Rectangle {
                                id: railItem
                                required property var modelData
                                required property int index
                                readonly property bool current: modelData.id === root.category && root.query === "" && !root.settingsOpen
                                width: 36; height: 36; radius: Theme.radiusSm
                                color: !current && cma.containsMouse ? Theme.surfaceHigher : "transparent"
                                scale: cma.pressed ? 0.88 : (cma.containsMouse ? 1.08 : 1)
                                Behavior on color { ColorAnimation { duration: Prefs.ms(140) } }
                                Behavior on scale { NumberAnimation { duration: Prefs.ms(160); easing.type: Easing.OutBack } }
                                // при перелистывании иконки въезжают со стороны листания
                                Stagger { id: railSt; target: railItem; delay: railItem.index * 28; distance: root.railDir * 16; duration: Prefs.ms(220) }
                                Connections { target: root; function onOpened() { railSt.play() } }
                                Text {
                                    anchors.centerIn: parent
                                    text: modelData.icon
                                    font.family: Prefs.iconFont
                                    font.pixelSize: Theme.fs(18)
                                    color: parent.current ? Theme.accentText : Theme.text
                                    Behavior on color { ColorAnimation { duration: Prefs.ms(180) } }
                                }
                                MouseArea {
                                    cursorShape: Qt.PointingHandCursor
                                    id: cma
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onClicked: root.setCategory(modelData.id)
                                }
                            }
                        }
                    }
                }

                RailBtn {
                    visible: root.pageCount > 1
                    horiz: rail.horiz
                    glyph: rail.horiz ? "›" : "﹀"; size: 22; glyphSize: rail.horiz ? 18 : 13
                    active: root.railPage < root.pageCount - 1
                    onClicked: root.flipPage(1)
                }

                Row {   // точки страниц; текущая вытянута
                    visible: root.pageCount > 1
                    spacing: 4
                    Repeater {
                        model: root.pageCount
                        delegate: Rectangle {
                            required property int index
                            readonly property bool cur: index === root.railPage
                            width: cur ? 12 : 5; height: 5; radius: 2.5
                            color: cur ? Prefs.accent : dotMa.containsMouse ? Theme.textMuted : Theme.divider
                            scale: dotMa.pressed ? 0.8 : dotMa.containsMouse ? 1.3 : 1
                            Behavior on scale { NumberAnimation { duration: Prefs.ms(140); easing.type: Easing.OutBack } }
                            Behavior on width { NumberAnimation { duration: Prefs.ms(200); easing.type: Easing.OutCubic } }
                            Behavior on color { ColorAnimation { duration: Prefs.ms(200) } }
                            MouseArea { id: dotMa; anchors.fill: parent; anchors.margins: -4; hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor; onClicked: root.setPage(index) }
                        }
                    }
                }

                Rectangle { width: rail.horiz ? 1 : 24; height: rail.horiz ? 24 : 1; color: Theme.outline }

                Rectangle {   // настройки
                    id: gear
                    width: 36; height: 36; radius: Theme.radiusSm
                    color: root.settingsOpen ? Prefs.accent : (gma.containsMouse ? Theme.surfaceHigher : "transparent")
                    scale: gma.pressed ? 0.88 : 1
                    Behavior on color { ColorAnimation { duration: Prefs.ms(160) } }
                    Behavior on scale { NumberAnimation { duration: Prefs.ms(140); easing.type: Easing.OutBack } }
                    Text {
                        anchors.centerIn: parent
                        text: "⚙"
                        font.pixelSize: Theme.fs(17)
                        color: root.settingsOpen ? Theme.accentText : Theme.textVariant
                        rotation: root.settingsOpen ? 90 : (gma.containsMouse ? 30 : 0)
                        Behavior on rotation { NumberAnimation { duration: Prefs.ms(320); easing.type: Easing.OutBack } }
                        Behavior on color { ColorAnimation { duration: Prefs.ms(160) } }
                    }
                    MouseArea { id: gma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.openSettings() }
                }
            }
        }

        // Основная карточка
        // В острове карточка лежит в фигуре под вкладками; её размер — цель, к которой
        // тянется фигура, а лишнее во время роста обрезается краем фигуры
        Rectangle {
            id: card
            parent: root.island ? blob : content
            width: root.wide ? Math.max(Prefs.width, 520) : Prefs.width
            height: root.island
                    ? Math.min(win.height - root.islandTop - rail.height - 28, col.implicitHeight + 32)
                    : Math.min(win.height - root.edgeTop - 48, Math.max(col.implicitHeight + 32, rail.height))
            Behavior on width { enabled: !root.island; NumberAnimation { duration: Prefs.ms(240); easing.type: Easing.OutCubic } }
            x: root.island ? Math.round((parent.width - width) / 2) : rail.x - width - 8
            y: root.island ? rail.y + rail.height
                           : root.edgeTop + Math.round((parent.height - root.edgeTop - height) / 2)
            radius: Theme.radiusLg
            color: root.island ? "transparent" : Theme.backgroundBar
            border.color: root.island ? "transparent" : Theme.outline
            opacity: root.contentReveal
            scale: root.island ? 0.95 + 0.05 * root.contentReveal : 0.94 + 0.06 * root.reveal
            transformOrigin: root.island ? Item.Top : Item.Right
            transform: Translate { x: root.island ? 0 : (1 - root.reveal) * 140 }
            Behavior on height { enabled: !root.island; NumberAnimation { duration: Prefs.ms(240); easing.type: Easing.OutCubic } }
            MouseArea { anchors.fill: parent }

            Flickable {
                id: flick
                anchors.fill: parent
                anchors.margins: 16
                contentHeight: col.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                Connections {
                    target: root
                    function onCategoryChanged() { flick.contentY = 0 }
                    function onSettingsOpenChanged() { flick.contentY = 0 }
                }

                Column {
                    id: col
                    width: parent.width
                    spacing: 14

                    // Поиск по действиям
                    Rectangle {
                        width: col.width
                        height: 40
                        radius: height / 2      // поиск MD3 — пилюля
                        color: Theme.surface
                        // фокус — акцентная обводка, наведение — чуть ярче; клик по пилюле ставит фокус
                        border.color: searchInput.activeFocus ? Prefs.accent : searchHover.hovered ? Theme.textFaint : Theme.outline
                        border.width: searchInput.activeFocus ? 2 : 1
                        Behavior on border.color { ColorAnimation { duration: Prefs.ms(160) } }
                        HoverHandler { id: searchHover; cursorShape: Qt.IBeamCursor }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            x: searchInput.text === "" ? 12 : 22
                            opacity: searchInput.text === "" ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: Prefs.ms(120) } }
                            Behavior on x { NumberAnimation { duration: Prefs.ms(160); easing.type: Easing.OutCubic } }
                            text: Tr.t("Поиск действий…  Ctrl+K")
                            color: Theme.textMuted
                        }
                        TextInput {
                            id: searchInput
                            anchors.fill: parent
                            anchors.margins: 12
                            verticalAlignment: TextInput.AlignVCenter
                            color: Theme.text
                            clip: true
                            onTextChanged: root.query = text
                            onAccepted: root.activateSelected()
                            Keys.onDownPressed: root.moveSelection(1)
                            Keys.onUpPressed: root.moveSelection(-1)
                            Keys.onTabPressed: root.moveSelection(1)
                        }
                    }

                    // Контекстные действия над выделением/буфером
                    Column {
                        width: col.width
                        spacing: 6
                        // в лаунчере действия над выделением только мешают — там их нет
                        visible: root.query === "" && !root.settingsOpen && root.category !== "apps" && root.contextActions.length > 0
                        Text {
                            width: col.width
                            elide: Text.ElideRight
                            text: root.contextLabel + ": " + root.contextText.replace(/\s+/g, " ").slice(0, 60)
                            color: Theme.textSecondary
                            font.pixelSize: Theme.fs(11)
                        }
                        Flow {
                            width: col.width
                            spacing: 6
                            Repeater {
                                model: root.contextActions
                                delegate: Rectangle {
                                    id: chip
                                    required property var modelData
                                    required property int index
                                    width: chipText.implicitWidth + 24
                                    height: 28
                                    radius: Theme.r(14)
                                    color: chipMa.containsMouse ? Prefs.accentHover : Prefs.accentSoft
                                    scale: chipMa.pressed ? 0.93 : 1
                                    Behavior on color { ColorAnimation { duration: Prefs.ms(120) } }
                                    Behavior on scale { NumberAnimation { duration: Prefs.ms(120); easing.type: Easing.OutCubic } }
                                    Stagger { id: chipSt; target: chip; delay: 80 + chip.index * 25; distance: 8 }
                                    Connections { target: root; function onOpened() { chipSt.play() } }
                                    Text {
                                        id: chipText
                                        anchors.centerIn: parent
                                        text: modelData.spec.label
                                        color: Theme.text
                                        font.pixelSize: Theme.fs(12)
                                    }
                                    MouseArea {
                                        cursorShape: Qt.PointingHandCursor
                                        id: chipMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        onClicked: root.run(modelData.plugin, modelData.spec, root.contextText)
                                    }
                                }
                            }
                        }
                    }

                    // Результаты поиска
                    EmptyState {
                        visible: root.query !== "" && root.results.length === 0
                        width: parent.width
                        glyph: 0xF0349
                        text: Tr.t("Ничего не найдено")
                        hint: Tr.t("Ни приложения, ни команды плагина с таким названием")
                    }
                    Repeater {
                        model: root.query !== "" ? root.results : []
                        delegate: Rectangle {
                            id: res
                            required property var modelData
                            required property int index
                            width: col.width
                            height: 36
                            radius: Theme.radiusSm
                            color: index === root.selected ? Theme.surfaceHigher : (resMa.containsMouse ? Theme.surfaceHigher : Theme.surfaceHigh)
                            border.color: index === root.selected ? Prefs.accent : "transparent"
                            scale: resMa.pressed ? 0.98 : 1
                            Behavior on color { ColorAnimation { duration: Prefs.ms(120) } }
                            Behavior on border.color { ColorAnimation { duration: Prefs.ms(120) } }
                            Behavior on scale { NumberAnimation { duration: Prefs.ms(100) } }
                            IconImage {
                                visible: res.modelData.kind === "app"
                                x: 10; anchors.verticalCenter: parent.verticalCenter
                                implicitSize: 20
                                source: visible ? Quickshell.iconPath(res.modelData.icon || "application-x-executable", "application-x-executable") : ""
                            }
                            Text {
                                x: res.modelData.kind === "app" ? 38 : 10
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - x - 110
                                elide: Text.ElideRight
                                text: modelData.label
                                color: Theme.text
                            }
                            Text {
                                anchors.right: parent.right
                                anchors.rightMargin: 10
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData.sub
                                color: Theme.textMuted
                                font.pixelSize: Theme.fs(11)
                            }
                            MouseArea {
                                cursorShape: Qt.PointingHandCursor
                                id: resMa
                                anchors.fill: parent
                                hoverEnabled: true
                                onEntered: root.selected = index
                                onClicked: root.activate(modelData)
                            }
                        }
                    }

                    // Содержимое категории
                    Text {
                        id: catTitle
                        visible: root.query === ""
                        text: root.settingsOpen ? Tr.t("Настройки")
                              : root.categoryName + (root.profile ? "  ·  " + root.profile : "")
                        Stagger { id: titleSt; target: catTitle; distance: 10 }
                        Connections {
                            target: root
                            function onCategoryChanged() { titleSt.play() }
                            function onSettingsOpenChanged() { titleSt.play() }
                            function onOpened() { titleSt.play() }
                        }
                        color: Theme.text
                        font.pixelSize: Theme.fs(16)
                        font.bold: true
                    }
                    Repeater {
                        model: root.query === "" && !root.settingsOpen ? root.visiblePlugins : []
                        delegate: PluginSection {
                            id: sec
                            required property var modelData
                            required property int index
                            Stagger { id: secSt; target: sec; delay: 40 + sec.index * 45 }
                            Connections { target: root; function onOpened() { secSt.play() } }
                            width: col.width
                            plugin: modelData
                            panel: root
                        }
                    }
                    Loader {
                        id: settingsLoader
                        width: col.width
                        active: root.settingsOpen && root.query === ""
                        visible: active
                        sourceComponent: SettingsView { panel: root }
                        onLoaded: settingsSt.play()
                        Stagger { id: settingsSt; target: settingsLoader; delay: 40 }
                    }
                    Text {
                        visible: root.plugins.length === 0 && !root.settingsOpen
                        text: Tr.t("Плагины не найдены.\n~/.config/glide-shell/plugins/")
                        color: Theme.textSecondary
                    }
                }
            }
        }
    }
}
