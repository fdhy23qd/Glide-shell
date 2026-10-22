# Glide Shell API

**English** · [Русский](API.ru.md)

Glide Shell can be extended in three ways:

| What | Where | Language |
|---|---|---|
| **Plugin**: a section in the panel, commands in search, an item in the bar | `~/.config/glide-shell/plugins/<id>/` | JSON + any scripts, or QML |
| **Desktop widget** | `~/.config/glide-shell/widgets/<id>/` | QML |
| **Another app** talking to the shell | D-Bus / `glide-shell` command | any |

API version: **1**. Put `"api": 1` in `plugin.json`. New fields are only ever added, so code written for version 1
keeps working.

Quick start: `python3 ~/.config/quickshell/glide-shell/tools/glide-plugin.py new my-plugin "My plugin"`
creates a working plugin that uses all of the API below: a panel section, a bar item and settings. For a widget, run
`… glide-plugin.py widget my-widget`. The plugin appears the next time you open the panel.

Plugins and widgets run with your permissions, like any program. Install only what you have read.

---

## 0. A complete example

A water counter: a panel section, a bar item and two settings. This is a shortened version; the full one, with both
buttons and a message when the goal is reached, is in [`examples/plugins/water`](../examples/plugins/water). Copy the folder to
`~/.config/glide-shell/plugins/water/`.

`plugin.json`:
```json
{
  "id": "water", "api": 1, "name": "Water", "icon": "󰖌", "category": "quick",
  "qml": "Main.qml", "bar": "Bar.qml",
  "settings": [
    { "key": "goal",    "type": "number", "label": "Glasses a day", "default": 8, "min": 4, "max": 14, "step": 1 },
    { "key": "showBar", "type": "toggle", "label": "Show in the bar", "default": true }
  ]
}
```

`Main.qml`, the panel section:
```qml
import QtQuick
import QtQuick.Layouts
import qs

ColumnLayout {
    id: root
    property var api                     // set right after creation: null until then
    spacing: 12
    readonly property int goal: api ? api.settings.goal : 8
    // api.today changes at midnight, so yesterday's count stops counting by itself
    readonly property int count: api && api.storage.get("day", "") === api.today ? api.storage.get("count", 0) : 0
    function add(n) {
        api.storage.set("day", api.today)
        api.storage.set("count", Math.max(0, count + n))
    }
    Text { text: root.count + " / " + root.goal; color: Theme.text; font.pixelSize: Theme.fs(18) }
    Rectangle {
        Layout.fillWidth: true; implicitHeight: 8; radius: Theme.r(4); color: Theme.surface
        Rectangle { width: parent.width * Math.min(1, root.count / root.goal); height: parent.height
                    radius: parent.radius; color: Theme.accent }
    }
    Rectangle {   // a button with hover and press states
        implicitWidth: 120; implicitHeight: 32; radius: Theme.r(16)
        color: ma.pressed ? Theme.accentPressed : ma.containsMouse ? Theme.accentLight : Theme.accent
        scale: ma.pressed ? 0.95 : 1
        Behavior on color { ColorAnimation { duration: Prefs.ms(120) } }
        Behavior on scale { NumberAnimation { duration: Prefs.ms(140); easing.type: Easing.OutBack } }
        Text { anchors.centerIn: parent; text: "+1 glass"; color: Theme.accentText; font.pixelSize: Theme.fs(13) }
        MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                    onClicked: root.add(1) }
    }
}
```

`Bar.qml`, the bar item:
```qml
import QtQuick
import qs

Item {
    id: chip
    property var api
    readonly property bool want: !!api && api.settings.showBar
    readonly property int count: api && api.storage.get("day", "") === api.today ? api.storage.get("count", 0) : 0
    implicitWidth: row.implicitWidth
    implicitHeight: 24
    Row { id: row; anchors.verticalCenter: parent.verticalCenter; spacing: 4
          Text { text: "󰖌"; color: Theme.accent; font.family: chip.api ? chip.api.iconFont : "" }
          Text { text: chip.count + "/" + (chip.api ? chip.api.settings.goal : 8); color: Theme.textVariant
                 font.pixelSize: Theme.fs(12) } }
    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: chip.api.openCategory("quick") }
}
```

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
| `id`, `name`, `icon` | Required: `id` and `name`. A plugin with the same `id` as a built-in one replaces it. `icon`: the character itself (`"󰖌"`, a Nerd Font glyph) or its hex code (`"F058C"`); both work here and in `widget.json`. |
| `category` | Panel category: `power`, `control`, `media`, `clipboard`, `apps`, `quick`, `today`, `phone`, `ai`, `dev`, `text`, `system`, `net`, `notify` or your own id. A new id makes a new category (`categoryName`, `categoryIcon`). |
| `priority` | Order inside the category: higher comes first. |
| `items` | Buttons, inputs and lists that run commands. No code needed (see the README). |
| `qml` | Your own interface for the panel section. Its root item receives `api` (section 3). |
| `bar` | A QML item for the bar (section 5). It shows up in Settings → Bar and is on by default. |
| `settings` | Settings shown in Settings → Plugins under the plugin (types below). Read them as `api.settings.<key>`. |
| `contextActions` | Buttons over the selected text or clipboard: `[{"label", "when", "command", "output"}]`. `when`: `text` (default), `multiline`, `json`, `xml`, `url`, `host`, `jwt`, `number`, `timestamp`, `path`, `base64`, `urlenc`, or a list of these. The command gets the text in `{text}` and `$QP_TEXT`. |
| `daemon` | A background process (argv) started with the shell and stopped with it. |
| `keywords` | Extra words for search. |
| `wide` | `true`: the category with this plugin opens in a wide card. |
| `handoff` | On an item instead of `command`: `"handoff": "<plugin id>"` (with an optional `"prompt"`) passes the text to another plugin and opens its category. A QML plugin takes it with `api.takeHandoff(id)`, which returns `{text, prompt}` once, or `null`. |
| `output` | On an item: `"copy"`, `"notify"` or `"copy+notify"`. The command's stdout goes to the clipboard and/or a notification. A non-zero exit code is reported as a notification too. |
| `confirm` | On a button: it only runs on the second press (within 3 seconds). |
| `close` | On an item: `false` keeps the panel open after the action. |

Settings types (each has `key`, `label`, `default`, and optionally `hint`, a grey line under the label):

| `type` | Shown as | Extra fields |
|---|---|---|
| `text` | Text field, Enter applies | — |
| `number` | Buttons for every value when `min`…`max` has at most 12 steps, otherwise a field | `min`, `max`, `step` (1 by default). `api.settings` always returns a number within the range. |
| `toggle` | Switch | — |
| `choice` | A row of options | `options: [{label, value}]` |

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
| `api.theme` | The same object as `Theme` from `import qs` (both spellings mean one thing). All design tokens: `theme.surface`, `theme.text`, `theme.accent`, `theme.r(16)` (radius), `theme.fs(13)` (font size), `theme.isLight`… With `import qs` you can also use `Theme` directly. |
| `api.accent`, `api.accentText`, `api.iconFont` | The accent colour; text colour on an accent fill (white, or dark on light accents); the icon font (Nerd Font) |
| `api.date`, `api.today` | Current date (updated at every minute and after sleep) and `"yyyy-MM-dd"`. Bind to `api.today` to react to a new day. |
| `api.shown` | The panel is open |
| `api.contextText` | Selected text or clipboard at the moment the panel was opened |

### Actions

| | |
|---|---|
| `api.run(argv, text)` | Run a program (no shell). `text` goes to `$QP_TEXT`. |
| `api.copy(text)` | Copy to the clipboard |
| `api.flash(icon, text, color)` | A short message in the island. An empty `icon` shows ✓, an empty `color` means `Theme.success`. |
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
`api.storage.all`. Any binding that calls `api.storage.get` updates when the value changes, even inside a condition
(`a ? api.storage.get(…) : 0`). The panel section and the bar item of the same plugin share the storage.

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
`actionLabel` with `onAction` (a button), `onClick` (a click on the row). `onAction` and `onClick` are ordinary
JavaScript functions in the same object:

```qml
api.activity.start("tea", {
    title: "Tea is brewing", progress: 0, actionLabel: "Stop",
    onAction: function () { api.activity.end("tea") },        // the button
    onClick: function () { api.openCategory("quick") }        // a click on the row
})
```

`update` keeps the functions you passed to `start` unless you pass new ones. Users can turn activities off in
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

`api` is assigned right after the item is created, so it is `null` during the first moment. Write bindings as
`api ? … : default` and handlers as `root.api.…` (they only run later). The section's width is set by the panel, and
its height comes from `implicitHeight`. A `ColumnLayout` or `Column` root needs no explicit size; do not set a fixed
height.

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
- Desktop widgets reload when their file changes. Plugins (`plugin.json`, the section and the bar item) are re-read
  every time the panel opens, so an edit shows up after closing and opening the panel; no restart is needed.

---

## 7. Other apps: D-Bus `org.glide.Shell` and the `glide-shell` command

Any program can talk to the shell over the session bus: Python, C++, Rust, Go, or a shell script with `gdbus`.
The service starts by itself on the first call (D-Bus activation), so it uses no memory until someone needs it.

Name `org.glide.Shell`, object `/org/glide/Shell`, interface `org.glide.Shell1`:

| Method | |
|---|---|
| `Flash(s icon, s text)` | A short message in the island |
| `StartActivity(s id, a{sv} props)` | A live activity (section 3): `title`, `subtitle`, `icon`, `progress` (d), `color`, `actionLabel`. It disappears by itself when your app leaves the bus; `persist: true` keeps it. |
| `UpdateActivity(s id, a{sv} props)` | Change some fields (applied at most 4 times a second) |
| `EndActivity(s id)` | Remove it |
| `OpenPanel(s category)`, `ClosePanel()`, `Search(s text)` | The panel |
| `SetDnd(b)`, `GetDnd() → b` | "Do not disturb" (set by hand) |
| `GetTheme() → a{sv}` | `accent`, `accentText`, `isLight`, `tone`, `background`, `surface`, `surfaceHigh`, `outline`, `text`, `textSecondary`, `radius`, `font`, `lang` |
| `GetVersion() → s` | Shell version |

| Signal | |
|---|---|
| `ThemeChanged(a{sv} theme)` | The user changed the accent, tone or light/dark mode. Restyle your app. |
| `ActivityClicked(s id)`, `ActivityAction(s id)`, `ActivityClosed(s id)` | A click on your activity, its button, or ×. |

```sh
gdbus call --session --dest org.glide.Shell --object-path /org/glide/Shell \
  --method org.glide.Shell1.StartActivity build "{'title': <'Building'>, 'progress': <0.3>}"
```

```python
from gi.repository import Gio, GLib
bus = Gio.bus_get_sync(Gio.BusType.SESSION)
bus.call_sync("org.glide.Shell", "/org/glide/Shell", "org.glide.Shell1", "Flash",
              GLib.Variant("(ss)", ("", "Export finished")), None, 0, -1, None)
```

For scripts, there is the `glide-shell` command (`~/.local/bin/glide-shell`):

```sh
glide-shell flash "Backup done"
glide-shell activity start backup --title "Backup" --progress 0.1
glide-shell activity update backup --progress 0.8 --subtitle "8 of 10 GB"
glide-shell activity end backup
glide-shell open control | close | search "text"
glide-shell dnd on | off | (no argument: print it)
glide-shell theme      # JSON
glide-shell watch      # signals as JSON lines
```

Activities started by the command live until you end them, since the command itself exits right away.

---

## 8. Dock badges and progress (Unity LauncherEntry)

The dock understands the common standard used by Telegram, Chromium and Firefox (downloads), Steam, Thunderbird and
others: a session bus signal `com.canonical.Unity.LauncherEntry.Update(s "application://<id>.desktop", a{sv} props)`
with `count` (x) and `count-visible` (b) for a red number on the icon, `progress` (d) and `progress-visible` (b) for a
bar under it, and `urgent` (b) for a red indicator. The badges go away when the app leaves the bus. Your own app only
needs to send the signal:

```python
bus.emit_signal(None, "/com/example/app", "com.canonical.Unity.LauncherEntry", "Update",
                GLib.Variant("(sa{sv})", ("application://my-app.desktop",
                                          {"count": GLib.Variant("x", 3), "count-visible": GLib.Variant("b", True)})))
```

---

## 9. Theme tokens

`import qs` gives `Theme`. The same object is `api.theme`. These names are stable within API version 1:

| Token | Use |
|---|---|
| `background` | Panel and island background |
| `surface`, `surfaceLow`, `surfaceHigh`, `surfaceHigher`, `surfacePressed` | Cards and buttons; hover → `surfaceHigher`, press → `surfacePressed` |
| `outline`, `outlineHover`, `divider` | Borders and separators |
| `text`, `textVariant`, `textSecondary`, `textMuted`, `textFaint` | Text, from most to least prominent |
| `accent`, `accentSoft`, `accentHover`, `accentLight`, `accentPressed` | The user's accent colour; button hover → `accentLight`, press → `accentPressed`, soft fill → `accentSoft` |
| `accentText` | Text on an accent-coloured fill: white, or dark on a light accent |
| `error`, `errorContainer`, `errorHover`, `errorText`, `success`, `warning` | Status colours |
| `isLight` | The light theme is on |
| `r(n)`, `radiusSm/Md/Lg/Xl` | Corner radius scaled by the user's setting |
| `fs(n)` | Font size scaled by the user's setting |
| `disabledOpacity` | Opacity of an unavailable control |

Everything else reachable with `import qs` (`Prefs`, `Niri`, `Notifs`…) is internal and can change between versions.
Use it through `api` when an `api` field exists. The exception is `Prefs.ms(n)`, which is stable: it gives an
animation duration that follows the user's "Animations" setting.

Interactive elements look right when they have three states. On hover, use a lighter colour and a hand cursor. On
press, use a darker colour and a slightly smaller scale (0.95). When unavailable, use `Theme.disabledOpacity` and the
arrow cursor.
