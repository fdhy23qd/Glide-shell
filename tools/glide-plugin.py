#!/usr/bin/env python3
"""Заготовки для разработчиков Glide Shell (описание API — docs/API.md).

    glide-plugin.py new ID [ИМЯ]      — плагин в ~/.config/glide-shell/plugins/ID: раздел панели (Main.qml),
                                        элемент бара (Bar.qml) и настройки — рабочий пример всего API
    glide-plugin.py widget ID [ИМЯ]   — свой виджет рабочего стола в ~/.config/glide-shell/widgets/ID

Плагин появится при следующем открытии панели (настройки — «Плагины», элемент бара — «Бар»).
"""
import json
import os
import re
import sys
from pathlib import Path

CFG = Path(os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config") / "glide-shell"

PLUGIN_QML = r'''import QtQuick
import QtQuick.Layouts
import qs

// Раздел плагина в панели. api — docs/API.md: хранилище, настройки, уведомления, события, система.
ColumnLayout {
    id: root
    property var api
    property string pluginDir
    spacing: 8

    readonly property int clicks: api ? api.storage.get("clicks", 0) : 0
    property string lastNotif: ""

    Connections {   // события оболочки (ignoreUnknownSignals: пока api не передан, сигналов у цели нет)
        target: root.api
        ignoreUnknownSignals: true
        function onOpened() { console.log("__ID__: панель открыта") }
        function onNotification(e) { root.lastNotif = e.appName + ": " + e.summary }
    }

    Text {
        text: root.api ? root.api.settings.greeting : ""
        color: Theme.text; font.pixelSize: Theme.fs(15); font.bold: true
    }
    Text {
        Layout.fillWidth: true
        text: "Нажатий: " + root.clicks + (root.api && root.api.player ? "  ·  играет: " + (root.api.player.trackTitle || "—") : "")
              + (root.lastNotif ? "\nПоследнее уведомление: " + root.lastNotif : "")
        color: Theme.textSecondary; font.pixelSize: Theme.fs(12); wrapMode: Text.WordWrap
    }
    Row {
        spacing: 8
        Rectangle {
            width: 120; height: 36; radius: Theme.r(18)
            color: ma.pressed ? Theme.accentPressed : ma.containsMouse ? Theme.accentLight : Theme.accent
            Text { anchors.centerIn: parent; text: "+1"; color: Theme.accentText; font.pixelSize: Theme.fs(13) }
            MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: root.api.storage.set("clicks", root.clicks + 1) }
        }
        Rectangle {
            width: 160; height: 36; radius: Theme.r(18)
            color: nm.pressed ? Theme.surfacePressed : nm.containsMouse ? Theme.surfaceHigher : Theme.surfaceHigh
            Text { anchors.centerIn: parent; text: "Уведомление"; color: Theme.text; font.pixelSize: Theme.fs(13) }
            MouseArea { id: nm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: root.api.notify("__NAME__", "Нажатий: " + root.clicks) }
        }
    }
}
'''

BAR_QML = r'''import QtQuick
import qs

// Элемент бара плагина: want — показывать ли сейчас; щелчок — что угодно через api.
// Размер — от содержимого (implicitWidth), щелчок — MouseArea поверх (anchors.fill), не внутри Row.
Item {
    id: chip
    property var api
    readonly property bool want: !!api && api.settings.showBar && api.storage.get("clicks", 0) > 0
    implicitWidth: row.implicitWidth
    implicitHeight: 24
    Row {
        id: row
        anchors.verticalCenter: parent.verticalCenter
        spacing: 4
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "󰐱"; color: Theme.accent; font.family: chip.api ? chip.api.iconFont : ""; font.pixelSize: Theme.fs(14)
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: chip.api ? chip.api.storage.get("clicks", 0) : ""
            color: Theme.textVariant; font.pixelSize: Theme.fs(12)
        }
    }
    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: chip.api.flash("󰐱", "Нажатий: " + chip.api.storage.get("clicks", 0))
    }
}
'''

WIDGET_QML = r'''import QtQuick

// Свой виджет рабочего стола. api — docs/API.md (плюс k — масштаб, tint/sub — цвета текста), cfg — настройки из widget.json.
Column {
    property var api
    property var cfg: ({})
    spacing: 4 * (api ? api.k : 1)
    Text {
        text: cfg.title || "Виджет"
        color: api ? api.tint : "white"
        font.pixelSize: Math.round(28 * (api ? api.k : 1)); font.weight: Font.DemiBold
    }
    Text {
        text: api ? Qt.formatTime(api.now, "HH:mm") + "  ·  " + Math.round(api.cpu) + "% ЦП" : ""
        color: api ? api.sub : "gray"
        font.pixelSize: Math.round(14 * (api ? api.k : 1))
    }
}
'''


def write(dest, files):
    if dest.exists():
        sys.exit(f"уже есть: {dest}")
    dest.mkdir(parents=True)
    for name, text in files.items():
        (dest / name).write_text(text)
    print(dest)


def main():
    a = sys.argv[1:]
    if len(a) < 2 or a[0] not in ("new", "widget") or not re.fullmatch(r"[a-z0-9][a-z0-9_-]*", a[1]):
        sys.exit(__doc__ + "\nID — латиница, цифры, - и _")
    pid, name = a[1], a[2] if len(a) > 2 else a[1]
    if a[0] == "new":
        manifest = {"id": pid, "api": 1, "name": name, "icon": "󰐱", "category": "quick",
                    "qml": "Main.qml", "bar": "Bar.qml",
                    "settings": [{"key": "greeting", "type": "text", "label": "Приветствие", "default": "Привет!"},
                                 {"key": "showBar", "type": "toggle", "label": "Показывать в баре", "default": True}]}
        write(CFG / "plugins" / pid, {"plugin.json": json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
                                      "Main.qml": PLUGIN_QML.replace("__ID__", pid).replace("__NAME__", name),
                                      "Bar.qml": BAR_QML})
    else:
        manifest = {"name": name, "icon": "F0954", "description": "",
                    "settings": [{"key": "title", "type": "text", "label": "Заголовок", "default": name}]}
        write(CFG / "widgets" / pid, {"widget.json": json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
                                      "widget.qml": WIDGET_QML})


if __name__ == "__main__":
    main()
