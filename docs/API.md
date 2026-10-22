# Glide Shell API

**English** · [Русский](API.ru.md)

Glide Shell can be extended in three ways:

| What | Where | Language |
|---|---|---|
| **Plugin**: a section in the panel, commands in search, an item in the bar | `~/.config/glide-shell/plugins/<id>/` | JSON + any scripts, or QML |
| **Desktop widget** | `~/.config/glide-shell/widgets/<id>/` | QML |
| **Another app** talking to the shell | D-Bus / `glide-shell` command | any (coming in the next versions) |

API version: **1**. Put `"api": 1` in `plugin.json`. New fields are only ever added, so code written for version 1
keeps working.

Quick start: `python3 ~/.config/quickshell/glide-shell/tools/glide-plugin.py new my-plugin "My plugin"`
creates a working plugin that uses all of the API below: a panel section, a bar item and settings. For a widget, run
`… glide-plugin.py widget my-widget`. The plugin appears the next time you open the panel.

Plugins and widgets run with your permissions, like any program. Install only what you have read.

---

## 1. plugin.json

```json
{
  "id": "my-plugin", "api": 1, "name": "My plugin", "icon": "󰐱",
  "category": "quick", "priority": 0, "keywords": ["example"],
  "qml": "Main.qml",
  "bar": "Bar.qml",
  "settings": [
    { "key": "greeting", "type": "text",   "label": "Greeting", "default": "Hello!" },
    { "key": "showBar",  "type": "toggle", "label": "Show in the bar", "default": true },
    { "key": "mode",     "type": "choice", "label": "Mode", "default": "a",
      "options": [{ "label": "A", "value": "a" }, { "label": "B", "value": "b" }] }
  ],
  "items": [ { "type": "button", "label": "Hi", "command": ["notify-send", "Hi"] } ]
}
```

| Field | Meaning |
|---|---|
| `id`, `name`, `icon` | Required: `id` and `name`. A plugin with the same `id` as a built-in one replaces it. `icon` is one character, usually a Nerd Font glyph. |
| `category` | Panel category: `power`, `control`, `media`, `clipboard`, `apps`, `quick`, `today`, `phone`, `ai`, `dev`, `text`, `system`, `net`, `notify` or your own id. A new id makes a new category (`categoryName`, `categoryIcon`). |
| `priority` | Order inside the category: higher comes first. |
| `items` | Buttons, inputs and lists that run commands. No code needed (see the README). |
| `qml` | Your own interface for the panel section. Its root item receives `api` (section 3). |
| `bar` | A QML item for the bar (section 5). It shows up in Settings → Bar and is on by default. |
| `settings` | Settings shown in Settings → Plugins under the plugin. Types: `text`, `number`, `toggle`, `choice`. Read them as `api.settings.<key>`. |
| `contextActions` | Buttons over the selected text or clipboard. |
| `daemon` | A background process started with the shell. |
| `wide`, `keywords`, `output`, `confirm`, `close`, `handoff` | See the README. |

Commands get `$QP_TEXT`, `$QP_DIR` (plugin folder), `$QP_FOCUSED` (focused window as JSON), `$QP_SELECTION`,
`$QP_CLIPBOARD` and `$QP_STYLE`, and the `{text}` and `{dir}` substitutions in argv.

---

## 2. Widgets: widget.json and widget.qml

```json
{ "name": "Countdown", "icon": "F051F", "description": "Days until a date", "stats": false,
  "settings": [{ "key": "date", "type": "text", "label": "Date", "default": "2027-01-01" }] }
```

`widget.qml` has a root item with `property var api` and `property var cfg`: the values of `settings` for this
instance of the widget (a widget can be added several times). The size comes from `implicitWidth` and
`implicitHeight`.

A widget gets the same `api` as plugins, plus:

| | |
|---|---|
| `api.now` | Current date (updated every minute) |
| `api.k` | Scale chosen by the user (multiply sizes by it) |
| `api.tint`, `api.sub` | Main and secondary text colour chosen by the user |
| `api.cpu`, `api.mem` | CPU and memory use in %, when `"stats": true` |

---

## 3. The `api` object (plugins and widgets)

Every plugin and widget gets its own object. Storage, settings and notifications belong to it.

### Basics

| | |
|---|---|
| `api.version` | `1` |
| `api.owner` | Plugin id (`widget-<id>` for widgets) |
| `api.theme` | All design tokens: `theme.surface`, `theme.text`, `theme.accent`, `theme.r(16)` (radius), `theme.fs(13)` (font size), `theme.isLight`… With `import qs` you can also use `Theme` directly. |
| `api.accent`, `api.accentText`, `api.iconFont` | Shortcuts |
| `api.shown` | The panel is open |
| `api.contextText` | Selected text or clipboard at the moment the panel was opened |

### Actions

| | |
|---|---|
| `api.run(argv, text)` | Run a program (no shell). `text` goes to `$QP_TEXT`. |
| `api.copy(text)` | Copy to the clipboard |
| `api.flash(icon, text, color)` | A short message in the island |
| `api.notify(title, body, icon)` | A notification under the plugin's name |
| `api.close()` | Close the panel |
| `api.openCategory(id)` | Switch the panel to a category |
| `api.openUrl(url)` | Open a link or file |
| `api.launchApp(entry)` | Launch a `DesktopEntry` |
| `api.setAwake(on)` | "Keep awake" on or off |
| `api.setPref(key, value)` | Change a shell setting (`config.json`, section `panel`) |

### Storage

Saved to `~/.local/state/glide-shell/plugin-<id>.json`, written a moment after the last change, survives restarts.

```qml
readonly property int clicks: api.storage.get("clicks", 0)   // the binding updates by itself
onClicked: api.storage.set("clicks", clicks + 1)
```

`api.storage.get(key, default)`, `api.storage.set(key, value)` (any JSON value), `api.storage.remove(key)`,
`api.storage.all`.

### Settings

`api.settings` holds the values of the `settings` from the manifest, or their `default`. The user changes them in
Settings → Plugins. Bindings update by themselves. `api.setSetting(key, value)` changes one from code.

### System state

| | |
|---|---|
| `api.niri` | niri: `workspaces` (list), `windows` (id → window), `focusedWindow`, `focusedOutput`, `action([...])` — any `niri msg action`, `focusWindow(id)`, `closeWindow(id)` |
| `api.player`, `api.players` | Current and all MPRIS players: `trackTitle`, `trackArtist`, `isPlaying`, `togglePlaying()`… |
| `api.volume`, `api.muted`, `api.setVolume(0…1.5)`, `api.setMuted(bool)` | Default output |
| `api.battery` | `{present, percent, charging}` |
| `api.dnd` | "Do not disturb" is on |
| `api.weather` | `data.now`, `data.days`, `temp(t)`, `icon(code, day)`, `describe(code)` |
| `api.notifs` | Notification history and "do not disturb" |
| `api.awake`, `api.powerTimer`, `api.recorder`, `api.kdeconnect`, `api.appCounts` | See the names |

### Live activities

A row in the island under the clock, for downloads, builds, countdowns and the like. The newest one is shown; hovering
opens the subtitle, a button and ×.

```qml
api.activity.start("sync", { title: "Syncing photos", progress: 0, icon: "󰓦" })
api.activity.update("sync", { progress: 0.4, subtitle: "120 of 300" })
api.activity.end("sync")
```

Props: `title`, `subtitle`, `icon` (one glyph), `progress` (0…1; below 0 — an indeterminate bar), `color`,
`actionLabel` with `onAction` (a button), `onClick` (a click on the row). Users can turn activities off in
Settings → Island. From a script: `qs -c glide-shell ipc call panel activity ID "Title" 0.5` (an empty title ends it).

### Events

```qml
Connections {
    target: api
    ignoreUnknownSignals: true          // api arrives after the item is created
    function onOpened() {}               // the panel opened
    function onClosed() {}
    function onThemeUpdated() {}         // accent, tone or light/dark mode changed
    function onNotification(e) {}        // {appName, summary, body, urgency, time}
}
```

---

## 4. Plugin section (qml)

```qml
import QtQuick
import QtQuick.Layouts
import qs

ColumnLayout {
    property var api
    property string pluginDir          // filled in with the plugin folder
    Text { text: api ? api.settings.greeting : ""; color: Theme.text; font.pixelSize: Theme.fs(14) }
}
```

Use `Theme` for every colour, radius and font size (`Theme.r(16)`, `Theme.fs(13)`). That way the plugin follows the
user's tone, accent, light mode, corner radius and text size. For durations, use `Prefs.ms(200)`: it follows the
"Animations" setting, including turning them off. If the QML fails to load, the error is shown in the plugin's section.

---

## 5. Bar item (bar)

```qml
import QtQuick
import qs

Item {
    id: chip
    property var api
    readonly property bool want: !!api && api.settings.showBar   // shown only while true
    implicitWidth: row.implicitWidth                            // size from the content…
    implicitHeight: 24
    Row { id: row; anchors.verticalCenter: parent.verticalCenter
          Text { text: "󰐱"; color: Theme.accent; font.family: chip.api ? chip.api.iconFont : "" } }
    MouseArea { anchors.fill: parent; onClicked: chip.api.openCategory("quick") }   // …and the click over it
}
```

The shell places the item in the left or right island. The user chooses which in Settings → Bar. Width is limited to
240 px. Do not size a `Row` from its own children: `width: parent.width` inside a `Row` creates a layout loop.

---

## 6. Debugging

- Logs: `journalctl --user -u glide-shell -f` (QML warnings and `console.log`).
- Check that a QML file compiles without restarting the shell:
  `qs -p <dir>` with a `shell.qml` containing
  `ShellRoot { Component.onCompleted: console.warn(Qt.createComponent("Main.qml").errorString()) }`.
- Desktop widgets reload when their file changes. Plugins are re-read every time the panel opens.
