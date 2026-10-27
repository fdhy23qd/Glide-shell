# Glide Shell API

**English** · [Русский](API.ru.md)

Glide Shell can be extended in three ways:

| What | Where | Language |
|---|---|---|
| **Plugin**: a section in the panel, commands in search, an item in the bar | `~/.config/glide-shell/plugins/<id>/` | JSON + any scripts, or QML |
| **Desktop widget** | `~/.config/glide-shell/widgets/<id>/` | QML |
| **Another app** talking to the shell | D-Bus / `glide-shell` command | any |

API version: **2**. Put `"api": 2` in `plugin.json`. Plugins with `"api": 1` (or no field) still load, but a
third-party one gets no permissions until you allow them (see section 3b). What is new in version 2: [section 3a](#3a-new-in-version-2); permissions:
[section 3b](#3b-permissions); how to move a plugin over: [section 12](#12-moving-from-version-1-to-2).

Quick start: `python3 ~/.config/quickshell/glide-shell/tools/glide-plugin.py new my-plugin "My plugin"`
creates a working plugin that uses all of the API below: a panel section, a bar item and settings. For a widget, run
`… glide-plugin.py widget my-widget`. The plugin appears the next time you open the panel.

> **⚠ Security in short: read this before installing someone else's plugin**
>
> - **There is no sandbox.** A plugin runs inside the shell, with your user's rights.
> - **Permissions only restrain a plugin that sticks to `api`.** Code that uses `Process`, `XMLHttpRequest` or the
>   shell's internals (`import qs`) can do anything you can: read your files, change the shell, rewrite its own
>   permissions. Settings → Plugins marks such code in yellow under the plugin.
> - **Permissions are kept in `~/.config/glide-shell/permissions.json`.** Edits made while the shell runs are undone,
>   but any program running as you can change the file while the shell is stopped.
> - **A third-party plugin starts with no permissions**, old ones with `"api": 1` included. You grant them yourself.
> - **Install only plugins you have read or whose author you trust.** Details: [section 10](#10-security-data-and-compatibility).
> - **Not reviewed by security professionals.** The plugin and permission system was built by one person who is not a
>   security expert, with an AI assistant helping to look for holes. Treat it as a reasonable effort, not a guarantee,
>   and please report anything you find.

## Contents

<!-- toc -->
- [0. A complete example](#0-a-complete-example)
- [1. plugin.json](#1-pluginjson)
- [2. Widgets: widget.json and widget.qml](#2-widgets-widgetjson-and-widgetqml)
- [3. The `api` object (plugins and widgets)](#3-the-api-object-plugins-and-widgets)
  - [Basics](#basics)
  - [Actions](#actions)
  - [Storage](#storage)
  - [Settings](#settings)
  - [System state](#system-state)
  - [Live activities](#live-activities)
  - [Events](#events)
  - [Reference: exact behaviour](#reference-exact-behaviour)
- [3a. New in version 2](#3a-new-in-version-2)
  - [Language and logging](#language-and-logging)
  - [Timers](#timers)
  - [Files](#files)
  - [Network](#network)
  - [Messages between plugins](#messages-between-plugins)
  - [Island color](#island-color)
  - [Search](#search)
  - [Version 2 reference](#version-2-reference)
- [3b. Permissions](#3b-permissions)
  - [How to ask](#how-to-ask)
  - [What the person sees](#what-the-person-sees)
  - [Why only a person](#why-only-a-person)
  - [What permissions do not do](#what-permissions-do-not-do)
- [4. Plugin section (qml)](#4-plugin-section-qml)
- [4a. Where plugin code runs and how long it lives](#4a-where-plugin-code-runs-and-how-long-it-lives)
  - [Performance](#performance)
- [5. Bar item (bar)](#5-bar-item-bar)
- [6. Debugging](#6-debugging)
  - [Sharing a plugin](#sharing-a-plugin)
- [7. Other apps: D-Bus `org.glide.Shell` and the `glide-shell` command](#7-other-apps-d-bus-orgglideshell-and-the-glide-shell-command)
- [8. Dock badges and progress (Unity LauncherEntry)](#8-dock-badges-and-progress-unity-launcherentry)
- [9. Theme tokens](#9-theme-tokens)
- [10. Security, data and compatibility](#10-security-data-and-compatibility)
  - [There is no sandbox](#there-is-no-sandbox)
  - [Turning a broken plugin off](#turning-a-broken-plugin-off)
  - [What happens on errors](#what-happens-on-errors)
  - [Data](#data)
  - [Compatibility](#compatibility)
- [11. Recipes: which mechanism for which task](#11-recipes-which-mechanism-for-which-task)
- [12. Moving from version 1 to 2](#12-moving-from-version-1-to-2)
<!-- /toc -->

---

## 0. A complete example

A water counter: a panel section, a bar item and two settings. This is a shortened version; the full one, with both
buttons and a message when the goal is reached, is in [`examples/plugins/water`](../examples/plugins/water). Copy the folder to
`~/.config/glide-shell/plugins/water/`.

`plugin.json`:
```json
{
  "id": "water", "api": 2, "name": "Water", "icon": "󰖌", "category": "quick",
  "qml": "Main.qml", "bar": "Bar.qml", "permissions": [],
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
    property var api                     // already set in Component.onCompleted
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

[↑ Contents](#contents)

---

## 1. plugin.json

```json
{
  "id": "my-plugin", "api": 2, "name": "My plugin", "icon": "󰐱",
  "category": "quick", "priority": 0, "keywords": ["example"],
  "permissions": ["exec"],
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
| `api` | API version: `1` or `2`. No field means `1`. Newer than the shell knows: the plugin is not loaded. |
| `permissions` | API 2 only: the permissions the plugin needs: `exec`, `network`, `clipboard`, `notifications`, `windows`, `phone`, `system`, `messages`, `island`, `search` (section 3b). A person grants them; no field means none. An API 1 plugin asks for all of them (this field is ignored) and gets them only when you allow it. |
| `id`, `name`, `icon` | Required: `id` and `name`. A plugin with the same `id` as a built-in one replaces it. `icon`: the character itself (`"󰖌"`, a Nerd Font glyph) or its hex code (`"F058C"`); both work here and in `widget.json`. |
| `category` | Panel category: `power`, `control`, `media`, `clipboard`, `apps`, `quick`, `today`, `phone`, `ai`, `dev`, `text`, `system`, `net`, `notify` or your own id. A new id makes a new category (`categoryName`, `categoryIcon`). |
| `priority` | Order inside the category: higher comes first. |
| `items` | Buttons, inputs and lists that run commands. No code needed (see the README). With API 2, commands need the `exec` permission (a `handoff` does not). |
| `qml` | Your own interface for the panel section. Its root item receives `api` (section 3). |
| `service` | A QML object without an interface that lives as long as the shell: background work (section 4a). |
| `bar` | A QML item for the bar (section 5). It shows up in Settings → Bar and is on by default. |
| `settings` | Settings shown in Settings → Plugins under the plugin (types below). Read them as `api.settings.<key>`. |
| `contextActions` | Buttons over the selected text or clipboard: `[{"label", "when", "command", "output"}]`. `when`: `text` (default), `multiline`, `json`, `xml`, `url`, `host`, `jwt`, `number`, `timestamp`, `path`, `base64`, `urlenc`, or a list of these. The command gets the text in `{text}` and `$QP_TEXT`. |
| `daemon` | A background process (argv) started with the shell and stopped with it. With API 2, only with the `exec` permission. |
| `keywords` | Extra words for search. |
| `wide` | `true`: the category with this plugin opens in a wide card. |
| `handoff` | On an item instead of `command`: `"handoff": "<plugin id>"` (with an optional `"prompt"`) passes the text to another plugin and opens its category. A QML plugin takes it with `api.takeHandoff(id)`, which returns `{text, prompt}` once, or `null`. A plugin can only take (and see in `api.handoff`) what was passed to itself. |
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

[↑ Contents](#contents)

---

## 2. Widgets: widget.json and widget.qml

```json
{ "name": "Countdown", "icon": "F051F", "description": "Days until a date", "stats": false,
  "settings": [{ "key": "date", "type": "text", "label": "Date", "default": "2027-01-01" }] }
```

`widget.qml` has a root item with `property var api` and `property var cfg`: the values of `settings` for this
instance of the widget (a widget can be added several times). The size comes from `implicitWidth` and
`implicitHeight`.

`"api": 2` and `"permissions"` in `widget.json` work as for plugins; widget permissions are at the bottom of
Settings → Plugins.

A widget gets the same `api` as plugins, plus:

| | |
|---|---|
| `api.now` | Current date (updated every minute) |
| `api.k` | Scale chosen by the user (multiply sizes by it) |
| `api.tint`, `api.sub` | Main and secondary text colour chosen by the user |
| `api.cpu`, `api.mem` | CPU and memory use in %, when `"stats": true` |

[↑ Contents](#contents)

---

## 3. The `api` object (plugins and widgets)

Every plugin and widget gets its own object. Storage, settings and notifications belong to it.

### Basics

| | |
|---|---|
| `api.version` | The API version the plugin declared: `1` or `2` |
| `api.shellApi` | The API version the shell knows: `2` |
| `api.owner` | Plugin id (`widget-<id>` for widgets) |
| `api.dir` | The plugin folder (same as `pluginDir`) |
| `api.theme` | The same object as `Theme` from `import qs` (both spellings mean one thing). All design tokens: `theme.surface`, `theme.text`, `theme.accent`, `theme.r(16)` (radius), `theme.fs(13)` (font size), `theme.isLight`… With `import qs` you can also use `Theme` directly. |
| `api.accent`, `api.accentText`, `api.iconFont` | The accent colour; text colour on an accent fill (white, or dark on light accents); the icon font (Nerd Font) |
| `api.date`, `api.today` | Current date (updated at every minute and after sleep) and `"yyyy-MM-dd"`. Bind to `api.today` to react to a new day. |
| `api.shown` | The panel is open |
| `api.contextText` | Selected text or clipboard at the moment the panel was opened (`clipboard` permission) |

### Actions

| | |
|---|---|
| `api.run(argv, text)` | Run a program and forget it (no shell, returns nothing). `text` goes to `$QP_TEXT`. Needs `exec`. |
| `api.exec(argv, opts, callback)` | Run a program and get the result: `callback(code, stdout, stderr)` is called once. `opts`: `stdin` (text), `timeout` in ms (60000 by default, 0 means none), `env` (extra variables; `$QP_DIR` is always the plugin folder). Returns a job with `cancel()` and `running`. `code` is -1 when the program could not start, was cancelled or timed out. Arguments go to the program as they are, with no shell: quotes, newlines and `{text}` are not interpreted. `opts` can be omitted: `api.exec(["date"], (code, out) => …)`. Needs `exec`. |
| `api.copy(text)` | Copy to the clipboard (`clipboard` permission) |
| `api.flash(icon, text, color)` | A short message in the island. An empty `icon` shows ✓, an empty `color` means `Theme.success`. |
| `api.notify(title, body, icon)` | A notification under the plugin's name. An empty `icon` means the standard information icon. |
| `api.close()` | Close the panel |
| `api.openCategory(id)` | Switch the panel to a category |
| `api.openUrl(url)` | Open a link: `http(s):` and `mailto:` always, anything else (`file://`, app schemes) needs the `exec` permission |
| `api.launchApp(entry)` | Launch an app: a `DesktopEntry` or its id (`"firefox"`); what runs is what its .desktop file says |
| `api.setAwake(on)` | "Keep awake" on or off (`system` permission) |
| `api.setPref(key, value)` | Change a shell setting (`config.json`, section `panel`; `system` permission) |
| `api.openSettings()` | Open Settings → Plugins |

### Storage

Saved to `~/.local/state/glide-shell/plugin-<id>.json`, written a moment after the last change, survives restarts.

```qml
readonly property int clicks: api.storage.get("clicks", 0)   // the binding updates by itself
onClicked: api.storage.set("clicks", clicks + 1)
```

`api.storage.get(key, default)`, `api.storage.set(key, value)` (any JSON value), `api.storage.remove(key)`,
`api.storage.all`, `api.storage.keys()` (the list of keys), `api.storage.clear()` (remove everything). Any binding that calls `api.storage.get` updates when the value changes, even inside a condition
(`a ? api.storage.get(…) : 0`). The panel section and the bar item of the same plugin share the storage.

### Settings

`api.settings` holds the values of the `settings` from the manifest, or their `default`. The user changes them in
Settings → Plugins. Bindings update by themselves. `api.setSetting(key, value)` changes one from code.

### System state

| | |
|---|---|
| `api.niri` | `windows` permission. niri: `workspaces` (list), `windows` (id → window), `focusedWindow`, `focusedOutput`, `action([...])` — `niri msg action` (action name first; `spawn`, `spawn-sh`, `quit`, `load-config-file` need the `exec` permission; returns `false` if not run), `focusWindow(id)`, `closeWindow(id)`, `iconFor(appId)`, `titleFor(window)`, `layouts`, `layoutIdx` |
| `api.player`, `api.players` | Current and all MPRIS players: `trackTitle`, `trackArtist`, `isPlaying`, `togglePlaying()`… |
| `api.volume`, `api.muted`, `api.setVolume(0…1.5)`, `api.setMuted(bool)` | Default output |
| `api.battery` | `{present, percent, charging}` |
| `api.dnd` | "Do not disturb" is on |
| `api.weather` | `data.now`, `data.days`, `temp(t)`, `icon(code, day)`, `describe(code)` |
| `api.notifs` | Notification history and "do not disturb" (`notifications` permission) |
| `api.recorder` | Screen recording (`system` permission) |
| `api.kdeconnect` | KDE Connect phones (`phone` permission) |
| `api.awake`, `api.powerTimer`, `api.appCounts` | See the names |

Without the permission, `niri`, `notifs`, `recorder` and `kdeconnect` are `null`, so check: `api.niri ? api.niri.windows : {}`.

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
    ignoreUnknownSignals: true          // harmless; needed in Glide Shell before 1.1
    function onOpened() {}               // the panel opened
    function onClosed() {}
    function onThemeUpdated() {}         // accent, tone or light/dark mode changed
    function onNotification(e) {}        // {appName, summary, body, urgency, time}; notifications permission
    function onPermissionsUpdated() {}   // API 2: a person granted or took away a permission
    function onMessage(from, name, data) {}   // API 2: a message from another plugin (api.send)
}
```

### Reference: exact behaviour

Types: `str` = string, `num` = number, `bool`, `obj` = plain JavaScript object, `fn` = function. "Live" means a binding
that reads the property updates by itself; you never need to poll it.

| Member | Type / returns | Live | Errors and notes |
|---|---|---|---|
| `version` | `num`: `1` or `2`, the plugin's `api` field | — | Always `1` for an API 1 plugin, as before |
| `owner` | `str` | — | The plugin `id`, or `widget-<id>` |
| `shown` | `bool` | yes, at once | |
| `contextText` | `str` | when the panel opens | Empty if nothing was selected or copied, or without the `clipboard` permission |
| `date` / `today` | `Date` / `str` `"yyyy-MM-dd"` | at every minute boundary and after sleep | |
| `now` | plugins: `num` ms since 1970, about every 20 s; widgets: `Date`, every minute | yes | Prefer `date` in new code |
| `settings` | `obj` key → value | yes, at once | Missing keys get `default`; `number` values are clamped to `min`…`max` |
| `setSetting(key, value)` | returns nothing | — | Saved to `config.json`; an unknown key is stored anyway |
| `storage.get(key, def)` | stored value or `def` | yes, at once, across all parts of the plugin | |
| `storage.set(key, value)` | returns nothing | — | `value`: anything `JSON.stringify` accepts (string, number, bool, null, array, object). Written about 0.3 s after the last change. `undefined` and functions are dropped. |
| `storage.remove(key)` | returns nothing | — | |
| `storage.all` | `obj` | yes | A copy for reading; changing it does nothing |
| `run(argv, text)` | returns nothing | — | Fire and forget. `argv` is an array of strings; the first is the program, found in `PATH`. The panel's `PATH` may not include `~/.local/bin`, so use a full path for your own scripts. |
| `exec(argv, opts, cb)` | a job: `cancel()`, `running` (`bool`) | — | `cb(code: num, stdout: str, stderr: str)` runs once. `code` is -1 when the program was not found, was cancelled, timed out, or the `exec` permission is missing. An exception thrown in `cb` is written to the log and goes no further. |
| `copy(text)` | returns nothing | — | Needs `wl-copy` |
| `flash(icon, text, color)` | returns nothing | — | Nothing is shown when the island is turned off |
| `notify(title, body, icon)` | returns nothing | — | Through `notify-send`; respects "do not disturb" like any app |
| `openCategory(id)` | returns nothing | — | Opens the panel on that category if it is closed. If the panel is already open on it, it closes, like the hotkey. An unknown `id` does nothing. |
| `openUrl(url)`, `launchApp(entry)`, `close()`, `setAwake(on)` | return nothing | — | |
| `setPref(key, value)` | returns nothing | — | Changes `config.json` → `panel.<key>`. `pluginLock` cannot be changed this way. |
| `activity.start(id, props)` / `update` / `end` | `start`/`update` return the full id (`<plugin>/<id>`) | — | `update` on an unknown id starts it. Activities are not removed when the plugin is turned off. End them yourself, or users dismiss them with ×. |
| `theme`, `accent`, `accentText`, `iconFont` | | yes, at once | |
| `niri` | `obj` or `null` | yes, on niri events | `windows` is a map id → window. `null` without the `windows` permission |
| `player`, `players` | MPRIS player / list | yes | `player` can be `null` |
| `volume`, `muted` | `num` 0…1.5 / `bool` | yes, at once | `null` sink → `0` / `false` |
| `battery` | `{present, percent, charging}` | yes | `present` is false on a desktop |
| `dnd` | `bool` | yes | True when quiet for any reason: by hand, by schedule, while sharing the screen |
| `weather` | object | after each update (every 30 min) | `weather.ok` is false until the first answer |
| Signals `opened`, `closed`, `themeUpdated`, `notification(entry)` | | | Use `Connections { target: api; ignoreUnknownSignals: true }` |

[↑ Contents](#contents)

---

## 3a. New in version 2

Everything below is available to every plugin and widget, including those with `"api": 1`.

### Language and logging

| | |
|---|---|
| `api.lang` | Interface language: `"ru"` or `"en"` |
| `api.tr(ru, en)` | A string in the interface language: `api.tr("Готово", "Done")`. In a binding it follows a language change. |
| `api.log(…)`, `api.warn(…)` | To the log, tagged `[id]`; objects are written as JSON |

### Timers

JavaScript inside QML has no `setTimeout`. `api` has:

```qml
api.setTimeout(() => api.flash("", "A minute has passed"), 60000)
var tick = api.setInterval(() => root.count++, 1000)
api.clearTimer(tick)
```

Timers live no longer than this part of the plugin: when the section is destroyed, so are its timers. Keep long ones
in a service (section 4a).

### Files

Your own folder `api.dataDir`, `~/.local/share/glide-shell/plugin-data/<id>/`, for what does not fit in
`api.storage`: history, cache, exports. No permission needed: you cannot reach other folders from here.

```qml
api.files.write("history.json", JSON.stringify(list), ok => {})
api.files.read("history.json", text => { if (text !== null) root.list = JSON.parse(text) })
api.files.list(files => api.log(files.map(f => f.name)))   // [{name, size, mtime}]
api.files.remove("old.txt")
```

A name is a file in that folder only: Latin letters, digits, `_`, `.` and `-`, not starting with a dot, up to 128
characters. Up to 16 MB per file, written atomically. The folder is created on the first write.

### Network

```qml
api.http("https://api.github.com/repos/owner/repo", { headers: { Accept: "application/json" } }, (status, text) => {
    if (status === 200) root.stars = JSON.parse(text).stargazers_count
})
```

Needs `network`. `opts`: `method` (`GET` by default), `headers`, `body` (a string; an object is sent as JSON),
`timeout` in ms (30000). `status` is 0 when the permission is missing, there is no network, no answer within
`timeout`, or the address is not `http(s)://`. Returns `{abort()}`.

### Messages between plugins

```qml
api.send("water", "drink", { glasses: 1 })   // to one plugin by id; "*" means everyone
Connections {
    target: api
    ignoreUnknownSignals: true
    function onMessage(from, name, data) { if (name === "drink") root.add(data.glasses) }
}
```

Every part of the receiver that exists right now gets the message: the section, the bar item, the service. `data`
arrives as a copy (through JSON). `send` returns `true` if the message went out.

**Your own parts need no permission.** A plugin's section, service and bar item are separate objects.
`api.send("<your id>", …)` reaches the other parts of your plugin, but not the part that sent it. This is how a
section asks its service to do something:

```qml
// Main.qml (section)                                // Service.qml (service)
onClicked: api.send("devhub", "sync", {})           function onMessage(from, name, data) { if (name === "sync") svc.load() }
```

**Other plugins need the `messages` permission** (since Glide Shell 1.3). Without it, `send` to another id sends
nothing and returns `false`, and messages from other plugins don't arrive. Both the sender and the receiver need it.
`"*"` without the permission reaches only your own parts. Old-format plugins that were fully approved before 1.3 got
`messages` automatically. Your parts can also share data through `api.storage`: there is one file, and every part
sees a change.

### Island color

Since Glide Shell 1.3, permission `island`. A plugin can tint the island: a light tinted fill and the outline.

```qml
api.island.tint("#7b61ff")   // true: accepted; a bad color or no permission: false
api.island.clear()           // remove your color
```

With several colors, the island shows all of them as a still left-to-right gradient. Camera (green), microphone
(amber) and screen sharing or recording (red) always come first, so a plugin cannot hide them. At most three plugin
colors are shown, the most recently set ones. A plugin has one color: a new `tint` replaces the old one. Alpha is
dropped. The color goes away by itself when the part that set it is destroyed, and when the person revokes the
permission, so set a long-lived color from the service. `api.island.colors` is what plugins have put on the island
right now (`[{owner, color}]`).

### Search

Since Glide Shell 2.5, `search` permission. A plugin adds its own results to the panel's search — an answer right in
the list: calculator, unit conversion, emoji, notes, bookmarks. Set the provider from a **service** (`service`): it lives
all the time, while the section lives only while open.

```qml
// Service.qml
Component.onCompleted: api.search.provide((q, done) => {
    if (q.indexOf("todo ") !== 0) return []                          // not ours — empty, fast
    return [{ id: "add", title: "Add task: " + q.slice(5), glyph: 0xF0415 }]   // right away — an array
    // or later: api.http(…, (st, text) => done([…])) and return undefined
})
Connections { target: api; ignoreUnknownSignals: true
              function onSearchActivated(id) { if (id === "add") … } }
```

The provider is called after each pause in typing (80 ms) with the query. Answer with an array right away or with
`done(array)` later; an answer to an outdated query is dropped. At most 5 results per plugin. Result fields:

| Field | What it is |
|---|---|
| `title` | Required. The main line (up to 200 characters) |
| `sub` | Small caption on the right |
| `glyph` | Icon: a number is a Nerd Font code (`0xF00EC`), a string is a character in the normal font (emoji, letter) |
| `icon` | Or a theme icon by name (`"firefox"`) |
| `copy` | When picked — this text goes to the clipboard, with a “Copied” flash |
| `url` | When picked — open it (`http:`, `https:`, `mailto:`; other schemes are dropped) |
| `id` | No `copy` and no `url` — when picked, the plugin gets `searchActivated(id)` |
| `top` | `true` — above apps (an answer to the query: a calculation result), otherwise after plugin commands |

The provider runs on the main thread: do long work (network, programs) through `done` — `api.http`, `api.exec` — not
in a loop. An error in the provider is a log warning; the rest of the search keeps working. `api.search.stop()` removes
your provider (it also goes away with the plugin part). The `search` permission sees everything typed into search, so,
like the others, a person grants it.

### Version 2 reference

| Member | Type / returns | Live | Errors and notes |
|---|---|---|---|
| `shellApi` | `num`, `2` | — | |
| `dir` | `str` | — | Empty for built-in widgets |
| `permissions.requested` | list of `str` | — | What `permissions` declares; everything for API 1 |
| `permissions.granted` | list of `str` | yes, at once | What a person granted |
| `permissions.has(p)` | `bool` | yes, in a binding | |
| `permissions.state(p)` | `"granted"`, `"denied"` or `"ask"` | yes, in a binding | `denied`: the person said no, asking is pointless |
| `permissions.request(p, reason)` | `bool`: already granted | — | Opens the question in Settings. Once per session; not declared in `permissions` → `false` and a warning |
| `openSettings()` | returns nothing | — | |
| `lang`, `tr(ru, en)` | `str` | yes | Without `en`, returns `ru` |
| `log(…)`, `warn(…)` | returns nothing | — | |
| `setTimeout(fn, ms)`, `setInterval(fn, ms)` | a timer | — | The interval is at least 16 ms. An exception in `fn` goes to the log |
| `clearTimer(t)` | returns nothing | — | A `setTimeout` that has fired cleans up by itself |
| `storage.keys()`, `storage.clear()` | list of `str` / nothing | — | |
| `dataDir` | `str` | — | |
| `files.read(name, cb)` | `cb(text)`; no file → `cb(null)` | — | |
| `files.write(name, text, cb)` | `cb(ok)` | — | A bad name or more than 16 MB → `false` and a warning |
| `files.list(cb)` | `cb([{name, size, mtime}])` | — | `mtime` in ms since 1970 |
| `files.remove(name, cb)` | `cb(ok)` | — | A missing file also gives `true` |
| `http(url, opts, cb)` | `{abort()}` | — | `cb(status, text, headers)` runs once; header names are lower-case |
| `send(to, name, data)` | `bool`: sent | — | `data`: anything `JSON.stringify` accepts. Another plugin's id needs `messages` |
| `island.tint(color)`, `island.clear()` | `bool` / nothing | — | Permission `island`. Color: `#rgb`, `#rrggbb`, `#aarrggbb` or a name |
| `island.colors` | list of `{owner, color}` | yes | |
| `search.provide(fn)`, `search.stop()` | `bool` / nothing | — | Since Glide Shell 2.5, `search` permission. `fn(q, done)` — an array or `done(array)` |
| `usage.timers`, `usage.exec`, `usage.http` | `num` | yes | Since Glide Shell 1.6: this part's live timers, program runs and network requests since it was created. Shown in Settings → Processes |
| Signals `permissionsUpdated`, `message(from, name, data)`, `searchActivated(id)` | | | Use `Connections { target: api; ignoreUnknownSignals: true }` |

[↑ Contents](#contents)

---

## 3b. Permissions

Without permissions, an API 2 plugin can only do safe things: draw its section and bar item, keep its own data, show
flashes, notifications under its own name and activities, read the theme, weather, player, sound and battery.
Everything else needs a permission. **Only a person grants and changes them**; a plugin can only ask.

| Permission | What it opens |
|---|---|
| `exec` | `api.run`, `api.exec`, plus `daemon` and commands in `items` and `contextActions`. **Full access**: a started program can do anything you can |
| `network` | `api.http` |
| `clipboard` | `api.contextText` (selection and clipboard), `api.copy` |
| `notifications` | `api.notifs` (other apps' notification history) and the `notification` event |
| `windows` | `api.niri`: windows, workspaces, niri actions |
| `phone` | `api.kdeconnect`: phones, their notifications and commands |
| `system` | `api.setPref`, `api.setAwake`, `api.recorder`. **Almost full access**: shell settings can do a lot |
| `messages` | `api.send` to other plugins and messages from them. Not needed between your plugin's own parts |
| `island` | `api.island.tint`: the island's color |
| `search` | `api.search`: see what is typed into the panel's search and add your own results there |

Without the permission, functions do nothing (`exec` answers `code` = -1, `http` answers `status` = 0), properties are
empty (`contextText` = `""`; `niri`, `notifs`, `kdeconnect`, `recorder` = `null`), and the log gets one warning.
A button with a command and no `exec` shows a flash and asks for the permission.

### How to ask

1. Declare it in `plugin.json`: `"permissions": ["network"]`. Undeclared permissions can be neither asked for nor
   granted.
2. Check before use, and ask when the user needs the feature, ideally on their click:

   ```qml
   readonly property bool online: api ? api.permissions.granted.indexOf("network") >= 0 : false
   // …
   onClicked: if (root.api.permissions.request("network", "Load exchange rates")) root.load()
   ```

3. `request` opens Settings → Plugins with a question: the permission name, what it opens, and your explanation.
   The person clicks "Allow" (with the login password when plugin protection is on), "Decline" or "Later". The answer
   arrives in `onPermissionsUpdated`; bindings to `api.permissions.granted` update by themselves.
4. A plugin asks about each permission at most once per session. After "Decline" it does not ask at all; only
   Settings can bring the permission back.

### What the person sees

In Settings → Plugins, every third-party plugin has a line "Permissions: 1 of 2"; a click shows the switches. Turning
one on asks the same question with the password; turning one off happens at once, with no password. Built-in plugins
need no permissions: they are part of the shell. Your widgets' permissions are at the bottom of the same tab.

### Why only a person

- A permission can be granted only through the question in Settings. When plugin protection is on (it is by
  default), that needs the login password, checked by PAM like on the lock screen. Without the password a plugin
  cannot grant itself anything, even if it reaches the shell's internal objects.
- `api` cannot grant: `setPref` does not touch permissions, and D-Bus and `glide-shell` only show them
  (`ListPlugins`).
- Permissions are kept in `~/.config/glide-shell/permissions.json`. If the file changes while the shell runs, the
  shell restores its own copy and shows a warning. Edit it by hand only while the shell is stopped
  (`systemctl --user stop glide-shell`).
- A third-party API 1 plugin (or one with no `api` field) asks for **all** permissions and gets **none** until you
  allow them: one by one, or with "Allow all…" under it (password, with a warning). Until then its commands and
  `daemon` do not run. Otherwise anyone could get every permission silently by writing `"api": 1`. Plugins and own
  widgets that were installed before Glide Shell 1.1 were approved once during the upgrade.
- A plugin that moves from API 1 to 2 starts from scratch: decisions made for the old version do not carry over.
- Built-in plugins get everything, but built-in means only a plugin in the shell's own folder. A `trusted` field in
  your own `plugin.json` gives nothing.

### What permissions do not do

There is still no sandbox (section 10): plugin QML runs inside the shell and can import `Quickshell.Io` and start a
program around `api`. Permissions are an agreement between the plugin and the person, not a wall. That is why the
shell scans the code of third-party plugins and widgets and writes under them: "The code reaches the system around
permissions: Process, XMLHttpRequest". It flags `Quickshell.Io`, `Process`, `execDetached`, `XMLHttpRequest`,
`createQmlObject`, `Pam`, references to `Permissions`, and `Prefs.set`/`run`/`reset`. An API 2 plugin needs none of
these; use `api`. If you see the flag on a plugin you do not trust, turn it off. `exec` and `system` amount to full
access: grant them only if you trust the author.

[↑ Contents](#contents)

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

`api` is passed as an initial property (since Glide Shell 1.1), so it is set before `Component.onCompleted` of a
section, a bar item and a service. Guards like `api ? … : default` are still harmless and keep the plugin working on
older versions, where `api` arrived a moment later. The section's width is set by the panel, and
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

### Performance

The shell usually takes less than 1% of a CPU core. One plugin can easily push that to 15% if it:

- **runs an animation forever** (`loops: Animation.Infinite`, `running: true` all the time). That redraws the bar or
  panel 60 times a second, constantly. Animate only in response to an event: a value changed, the mouse hovered.
  Keep durations short, 300–400 ms at most;
- **updates an activity more than once a second**, or calls `activity.start` from a timer. Call `start` once, then
  `update`, and only when the value really changed. Once a second is cheap; every 150 ms is not;
- **polls** something that has an event (`onOpened`, `api.player` and `api.niri` signals), or runs programs through
  `api.exec` more often than once every few seconds.

Removing your activity when the plugin is turned off is your job too: call `api.activity.end` in the service's
`Component.onDestruction`.

[↑ Contents](#contents)

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

**Tooltip on hover.** Give the item a `tip` property and the shell shows it in the same drop-down as built-in items,
updating it live. `tip` is a string, or `{title, rows: [{name, value, color}], hint}` (up to 10 rows; plain text only,
`color` is optional). `null` or an empty string means no tooltip.

```qml
readonly property var tip: ({ title: "Water today", rows: [{ name: "Glasses", value: count + " of 8" }],
                              hint: "Click to open" })
```

[↑ Contents](#contents)

---

## 6. Debugging

- Logs: `journalctl --user -u glide-shell -f` (QML warnings and `console.log`).
- Check that a QML file compiles without restarting the shell:
  `qs -p <dir>` with a `shell.qml` containing
  `ShellRoot { Component.onCompleted: console.warn(Qt.createComponent("Main.qml").errorString()) }`.
- Desktop widgets reload when their file changes. Plugins (`plugin.json`, the section and the bar item) are re-read
  every time the panel opens, so an edit shows up after closing and opening the panel; no restart is needed.
- Your plugin's errors without the log: Settings → Processes → "errors N" next to the plugin (QML warnings since the
  shell started, with a Copy button). It also warns about timers that fire more than once a second.

### Sharing a plugin

There is no special format: a plugin travels as a plain archive, `.zip`, `.tar.gz` or `.glideplugin` (the same zip).
`plugin.json` sits at the root of the archive or in its only folder.

```sh
tools/glide-plugin.py pack ~/.config/glide-shell/plugins/water      # → water.glideplugin (hidden files are skipped)
glide-shell install-plugin ~/Downloads/water.glideplugin            # opens the install card in Plugins
```

`pack` runs the same checks as installing. You can also install from Settings → Plugins → "Install from an archive",
which lists archives found in Downloads. Before installing you see a card: name, author, `description`, `version`,
the permissions the plugin will ask for, and audit marks. Archives are refused if they contain paths that leave the
folder (`../`), links or special files, use a built-in plugin's id, or exceed 50 MB or 2000 files. File modes from
the archive are not kept. When you replace a plugin, the old version goes to `~/.local/state/glide-shell/plugin-backups`.
With plugin password protection on, a new plugin is installed turned off. Permissions are still granted by a person.

[↑ Contents](#contents)

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
| `GetApiVersion() → u` | Plugin API version: `2` |
| `ListPlugins() → aa{sv}` | Plugins: `id`, `name`, `icon`, `disabled`, `user` (third-party), `api`, `permissions` (asked for), `granted` (given), `problem`. Read-only: a person grants permissions in Settings |
| `OpenSettings(s page)` | Open Settings on a page: `plugins`, `look`, `bar`…; empty means "Look" |

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
glide-shell plugins    # plugins and their permissions, JSON
glide-shell settings plugins
glide-shell version | api
```

`GetApiVersion`, `ListPlugins` and `OpenSettings` appeared in Glide Shell 1.0. The interface is still
`org.glide.Shell1`: the new methods were only added.

Activities started by the command live until you end them, since the command itself exits right away.

[↑ Contents](#contents)

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

[↑ Contents](#contents)

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

[↑ Contents](#contents)

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
  `daemon` or `items` runs commands as well (with API 2, only with the `exec` permission).
- API 2 permissions (section 3b) limit what a plugin does through `api`, not code that goes around it. The shell
  flags such code under the plugin in Settings → Plugins.


**What the permission system does and does not protect against.** Permissions are decided by the shell, not by the
`api` object: the code that creates a plugin's `api` registers it with the plugin's real id and a frozen copy of its
manifest before handing it over. Overwriting `api.owner` or `api.manifest`, or changing the manifest object, does not
change what the plugin may do. Storage, files, settings, activities and messages also use the registered id. The
`api` object gives no way to reach the rest of the shell. A plugin can still get around the system through
`import qs` (`Permissions`, `Core`, `Prefs.set`, creating its own `ApiScope`) or Quickshell types (`Process`,
`XMLHttpRequest`). The audit marks such code under the plugin in Settings → Plugins. Do not install a plugin with
those marks unless you trust its author.

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
| `permissions` is not a list of strings | The plugin is not loaded; the reason is shown under it in Settings → Plugins |
| An unknown name in `permissions` | Skipped, with a warning in the log |
| A permission is missing | The function does nothing, the property is empty, one warning in the log |
| `permissions.json` changed outside Settings | The change is undone, with a warning in the island |
| Exception in your callback (`exec`, `onAction`…) | Written to the log; the shell keeps going |
| Storage file is damaged | Storage starts empty; the old file is kept as `plugin-<id>.json.broken` |

### Data

| Data | Where | On removal |
|---|---|---|
| `api.storage` | `~/.local/state/glide-shell/plugin-<id>.json` | Stays. Delete the file by hand. |
| `api.settings` | `config.json` → `panel.pluginSettings.<id>` | Stays. A reinstalled plugin gets them back. |
| `api.files` | `~/.local/share/glide-shell/plugin-data/<id>/` | Stays. Delete the folder by hand. |
| Permissions | `~/.config/glide-shell/permissions.json` | Stay. A reinstalled plugin gets them back (except when moving from API 1 to 2). |
| Processes from `api.exec` and `daemon` | — | Stopped when the plugin is turned off or the shell exits |

Data is tied to the plugin **`id`**. Renaming the `id` starts with empty storage. A plugin whose `id` matches a
built-in one replaces it and also gets the built-in's storage and settings.

### Compatibility

- The API version is the `api` field: `1` or `2`. Glide Shell 1.0 understands both. A third-party API 1 plugin
  needs your consent for everything (section 3b); the version 2 additions (section 3a) are available to it too.
- Within a version, things are only added: new fields of `api`, new manifest fields, new optional arguments, new
  D-Bus methods and signals.
- **Breaking changes** need version 3: removing or renaming anything listed in this document, changing a type or a
  return value, changing when something is created or destroyed, or changing the meaning of a manifest field. The
  D-Bus interface then becomes `org.glide.Shell2`, and `org.glide.Shell1` keeps working next to it.
- An outdated feature is first marked "deprecated" here and keeps working until the next API version.
- Every release is checked by an automatic test against the version 1 and 2 contracts (`tests/test_api_contract.py`).
- Requirements: Quickshell 0.3+, Qt 6.8+, niri. Tested on Quickshell 0.3.2, Qt 6.12, niri 26.04.
- Only what is described here is stable. Other parts reachable through `import qs` are internal.

[↑ Contents](#contents)

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
| An internet request | `api.http` + `"permissions": ["network"]` | Section 3a |
| History, cache, exports: more than `storage` should hold | `api.files` | Section 3a |
| Delay or repeat an action | `api.setTimeout` / `api.setInterval` | Section 3a |
| Connect two of your plugins | `api.send` + `onMessage` | Section 3a |
| Ask for a permission on a click | `api.permissions.request` + `onPermissionsUpdated` | Section 3b |

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

[↑ Contents](#contents)

---

## 12. Moving from version 1 to 2

1. Set `"api": 2` in `plugin.json`.
2. List what you use in `"permissions"` (the table in section 3b). Nothing needed: `"permissions": []`.
3. Without the permission, `api.niri`, `api.notifs`, `api.kdeconnect` and `api.recorder` are `null`: check before use.
4. Ask for a permission when the user needs it (`api.permissions.request` on a click), not at start-up.
5. Remove the workarounds; the person sees them in Settings → Plugins:

   | Before | After | Permission |
   |---|---|---|
   | `import Quickshell.Io` + `Process { … }` | `api.exec(argv, opts, cb)` | `exec` |
   | `Quickshell.execDetached(…)` | `api.run(argv)` | `exec` |
   | `XMLHttpRequest` | `api.http(url, opts, cb)` | `network` |
   | `FileView` with your own file | `api.files` or `api.storage` | — |
   | A `Timer` for a single delay | `api.setTimeout(fn, ms)` | — |
   | `Prefs.set(…)` | `api.setPref(key, value)` | `system` |

6. Check in Settings → Plugins → Permissions: turn each one off and see that the plugin behaves: it explains what is
   missing and does not flood the log with errors.

`glide-plugin.py new` creates an API 2 plugin that already asks for a permission.

[↑ Contents](#contents)
