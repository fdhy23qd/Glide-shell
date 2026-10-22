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
| `service` | A QML object without an interface that lives as long as the shell: background work (section 4a). |
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
| `api.run(argv, text)` | Run a program and forget it (no shell, returns nothing). `text` goes to `$QP_TEXT`. |
| `api.exec(argv, opts, callback)` | Run a program and get the result: `callback(code, stdout, stderr)` is called once. `opts`: `stdin` (text), `timeout` in ms (60000 by default, 0 means none), `env` (extra variables; `$QP_DIR` is always the plugin folder). Returns a job with `cancel()` and `running`. `code` is -1 when the program could not start, was cancelled or timed out. Arguments go to the program as they are, with no shell: quotes, newlines and `{text}` are not interpreted. `opts` can be omitted: `api.exec(["date"], (code, out) => …)`. |
| `api.copy(text)` | Copy to the clipboard |
| `api.flash(icon, text, color)` | A short message in the island. An empty `icon` shows ✓, an empty `color` means `Theme.success`. |
| `api.notify(title, body, icon)` | A notification under the plugin's name. An empty `icon` means the standard information icon. |
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

### Reference: exact behaviour

Types: `str` = string, `num` = number, `bool`, `obj` = plain JavaScript object, `fn` = function. "Live" means a binding
that reads the property updates by itself; you never need to poll it.

| Member | Type / returns | Live | Errors and notes |
|---|---|---|---|
| `version` | `num`, always `1` here | — | |
| `owner` | `str` | — | The plugin `id`, or `widget-<id>` |
| `shown` | `bool` | yes, at once | |
| `contextText` | `str` | when the panel opens | Empty if nothing was selected or copied |
| `date` / `today` | `Date` / `str` `"yyyy-MM-dd"` | at every minute boundary and after sleep | |
| `now` | plugins: `num` ms since 1970, about every 20 s; widgets: `Date`, every minute | yes | Prefer `date` in new code |
| `settings` | `obj` key → value | yes, at once | Missing keys get `default`; `number` values are clamped to `min`…`max` |
| `setSetting(key, value)` | returns nothing | — | Saved to `config.json`; an unknown key is stored anyway |
| `storage.get(key, def)` | stored value or `def` | yes, at once, across all parts of the plugin | |
| `storage.set(key, value)` | returns nothing | — | `value`: anything `JSON.stringify` accepts (string, number, bool, null, array, object). Written about 0.3 s after the last change. `undefined` and functions are dropped. |
| `storage.remove(key)` | returns nothing | — | |
| `storage.all` | `obj` | yes | A copy for reading; changing it does nothing |
| `run(argv, text)` | returns nothing | — | Fire and forget. `argv` is an array of strings; the first is the program, found in `PATH`. The panel's `PATH` may not include `~/.local/bin`, so use a full path for your own scripts. |
| `exec(argv, opts, cb)` | a job: `cancel()`, `running` (`bool`) | — | `cb(code: num, stdout: str, stderr: str)` runs once. `code` is -1 when the program was not found, was cancelled or timed out. An exception thrown in `cb` is written to the log and goes no further. |
| `copy(text)` | returns nothing | — | Needs `wl-copy` |
| `flash(icon, text, color)` | returns nothing | — | Nothing is shown when the island is turned off |
| `notify(title, body, icon)` | returns nothing | — | Through `notify-send`; respects "do not disturb" like any app |
| `openCategory(id)` | returns nothing | — | Opens the panel on that category if it is closed. If the panel is already open on it, it closes, like the hotkey. An unknown `id` does nothing. |
| `openUrl(url)`, `launchApp(entry)`, `close()`, `setAwake(on)` | return nothing | — | |
| `setPref(key, value)` | returns nothing | — | Changes `config.json` → `panel.<key>`. `pluginLock` cannot be changed this way. |
| `activity.start(id, props)` / `update` / `end` | `start`/`update` return the full id (`<plugin>/<id>`) | — | `update` on an unknown id starts it. Activities are not removed when the plugin is turned off. End them yourself, or users dismiss them with ×. |
| `theme`, `accent`, `accentText`, `iconFont` | | yes, at once | |
| `niri` | `obj` | yes, on niri events | `windows` is a map id → window |
| `player`, `players` | MPRIS player / list | yes | `player` can be `null` |
| `volume`, `muted` | `num` 0…1.5 / `bool` | yes, at once | `null` sink → `0` / `false` |
| `battery` | `{present, percent, charging}` | yes | `present` is false on a desktop |
| `dnd` | `bool` | yes | True when quiet for any reason: by hand, by schedule, while sharing the screen |
| `weather` | object | after each update (every 30 min) | `weather.ok` is false until the first answer |
| Signals `opened`, `closed`, `themeUpdated`, `notification(entry)` | | | Use `Connections { target: api; ignoreUnknownSignals: true }` |

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

## 4a. Where plugin code runs and how long it lives

| Part | Created | Destroyed | Use it for |
|---|---|---|---|
| `qml`: section | When its category is shown | When the user switches category, starts typing in search or opens settings. Closing the panel does **not** destroy it. | The interface |
| `bar`: bar item | When the shell starts, if the item is on (Settings → Bar) | When the user hides it | A compact indicator |
| `service`: `"service": "Service.qml"` | 6 s after the shell starts | When the plugin is disabled or the shell exits | **Background work**: timers, watching files, activities |
| `daemon`: any program | With the shell | With the shell | Work outside QML |

A service is a QML object without an interface (`QtObject` or `Item`) and gets the same `api`. Keep timers and
`api.activity` there. In the section, only write to `api.storage`: the service and the bar item see the change at
once. If a bar item does the work, it stops when the user hides it from the bar.

```qml
// Service.qml
import QtQuick
Item {
    id: svc
    property var api
    Timer { interval: 1000; repeat: true; running: !!svc.api; onTriggered: { /* … */ } }
}
```

All parts of a plugin, its section, bar item and service, are reloaded after an edit the next time the panel opens.

**Names you cannot use for your own properties.** `left`, `right`, `top`, `bottom`, `x`, `y`, `z`, `width`, `height`,
`data`, `children`, `parent`, `state`, `states`, `visible`, `enabled`, `opacity`, `scale`, `clip` and other `Item`
properties are taken. A property named `left` stops the whole file from loading with "Cannot override FINAL property".
Names that start with `on` and a capital letter are signal handlers, not properties. Use `remaining`, `endAt` and
similar names instead.

QML: Qt 6.8 or newer is required, so inline components (`component Btn: Rectangle {…}`) are fine.
`api.activity.update` from QML has no rate limit; once a second is cheap.

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

---

## 10. Security, data and compatibility

### There is no sandbox

A plugin or widget runs **as you**, with your permissions, and QML parts run **inside the shell process**:

- It can read and write any of your files, including other plugins' storage in `~/.local/state/glide-shell/` and
  the shell's own settings. It can run any program and use the network.
- It sees what the panel sees: the selected text, the clipboard and notifications.
- A QML loop that never ends freezes the whole shell. A crash restarts it (systemd); after several crashes in a row
  the emergency fallback starts.
- The shell does not check where a plugin came from. Read the code before installing. A `plugin.json` with
  `daemon` or `items` runs commands as well.

### Turning a broken plugin off

- **Settings → Plugins**, the switch next to it. When "Turning plugins on and off requires the password" is on,
  this asks for your login password.
- **The lock screen**: "Unlock without third-party plugins". After the correct password, every plugin from
  `~/.config/glide-shell/plugins` is turned off and built-in ones stay. This helps when a plugin has broken the panel
  or the bar.
- **By hand**: add the id to `"disabled"` in `~/.config/glide-shell/config.json`, or move the plugin folder away,
  then `systemctl --user restart glide-shell`.

### What happens on errors

| What fails | What you see |
|---|---|
| Section QML does not load | The error text in place of the section |
| Bar item does not load | The item is hidden, with a warning in the log |
| Service does not load | A warning in the log |
| `api` field newer than the shell, or not a number | The plugin is not loaded; the reason is shown under it in Settings → Plugins |
| Exception in your callback (`exec`, `onAction`…) | Written to the log; the shell keeps going |
| Storage file is damaged | Storage starts empty; the old file is kept as `plugin-<id>.json.broken` |

### Data

| Data | Where | On removal |
|---|---|---|
| `api.storage` | `~/.local/state/glide-shell/plugin-<id>.json` | Stays. Delete the file by hand. |
| `api.settings` | `config.json` → `panel.pluginSettings.<id>` | Stays. A reinstalled plugin gets them back. |
| Processes from `api.exec` and `daemon` | — | Stopped when the plugin is turned off or the shell exits |

Data is tied to the plugin **`id`**. Renaming the `id` starts with empty storage. A plugin whose `id` matches a
built-in one replaces it and also gets the built-in's storage and settings.

### Compatibility

- The API version is the `api` field. Within version 1, things are only added: new fields of `api`, new manifest
  fields, new optional arguments, new D-Bus methods and signals.
- **Breaking changes** need version 2: removing or renaming anything listed in this document, changing a type or a
  return value, changing when something is created or destroyed, or changing the meaning of a manifest field. The
  D-Bus interface then becomes `org.glide.Shell2`, and `org.glide.Shell1` keeps working next to it.
- An outdated feature is first marked "deprecated" here and keeps working until the next API version.
- Every release is checked by an automatic test against the version 1 contract (`tests/test_api_contract.py`).
- Requirements: Quickshell 0.3+, Qt 6.8+, niri. Tested on Quickshell 0.3.2, Qt 6.12, niri 26.04.
- Only what is described here is stable. Other parts reachable through `import qs` are internal.

---

## 11. Recipes: which mechanism for which task

| Task | Use | Example |
|---|---|---|
| A button that runs a command, no code | `items` with `command` and `output` | `{"type": "button", "label": "IP", "command": ["curl", "-s", "ifconfig.me"], "output": "copy+notify"}` |
| Act on the selected text | `contextActions` with `when` | `{"label": "Words", "when": "text", "command": ["sh", "-c", "printf %s \"$QP_TEXT\" \| wc -w"], "output": "notify"}` |
| An interface in the panel | `qml` + `api.storage` + `api.settings` | Section 0 |
| A number in the bar that opens your section | `bar` with `want` + `api.openCategory` | Section 5 |
| Something that runs while the panel is closed (a timer, watching) | `service` + `api.storage` | Section 4a; the section only writes the settings |
| A long task with progress and Cancel | `service` + `api.exec` + `api.activity` with `actionLabel` / `onAction: job.cancel` | below |
| Reacting to a new day or a theme change | bind to `api.today` / `onThemeUpdated` | Section 3 |
| A widget with user settings | `widget.json` `settings` + `cfg` | Section 2 |
| Your own app shows progress or reads the theme | D-Bus `org.glide.Shell` or `glide-shell` | Section 7 |
| Unread count on your app's dock icon | Unity LauncherEntry signal | Section 8 |

A long task with progress and Cancel, in a service:

```qml
import QtQuick
Item {
    id: svc
    property var api
    property var job: null
    function backup() {
        api.activity.start("backup", { title: "Backup", progress: -1, actionLabel: "Cancel",
                                       onAction: function () { if (svc.job) svc.job.cancel() } })
        job = api.exec(["rsync", "-a", "/home/me/Documents/", "/mnt/backup/"], { timeout: 0 }, (code, out, err) => {
            api.activity.end("backup")
            api.flash("", code === 0 ? "Backup done" : "Backup failed: " + (err.trim() || code))
            svc.job = null
        })
    }
}
```
