# API Glide Shell

[English](API.md) · **Русский**

Расширить Glide Shell можно тремя способами:

| Что | Где | На чём |
|---|---|---|
| **Плагин** — раздел в панели, команды в поиске, элемент бара | `~/.config/glide-shell/plugins/<id>/` | JSON + любые скрипты или QML |
| **Виджет рабочего стола** | `~/.config/glide-shell/widgets/<id>/` | QML |
| **Чужое приложение**, которое общается с оболочкой | D-Bus / команда `glide-shell` | любой язык |

Версия API — **1**, в `plugin.json` пишется `"api": 1`. Новое только добавляется, поэтому код для версии 1
продолжит работать.

Быстрый старт: `python3 ~/.config/quickshell/glide-shell/tools/glide-plugin.py new my-plugin "Мой плагин"`
создаёт рабочий плагин, где задействовано всё API ниже: раздел панели, элемент бара и настройки. Для виджета —
`… glide-plugin.py widget my-widget`. Плагин появится при следующем открытии панели.

Плагины и виджеты работают с твоими правами, как любая программа. Ставь только то, что прочитал.

---

## 1. plugin.json

```json
{
  "id": "my-plugin", "api": 1, "name": "Мой плагин", "icon": "󰐱",
  "category": "quick", "priority": 0, "keywords": ["пример"],
  "qml": "Main.qml",
  "bar": "Bar.qml",
  "settings": [
    { "key": "greeting", "type": "text",   "label": "Приветствие", "default": "Привет!" },
    { "key": "showBar",  "type": "toggle", "label": "Показывать в баре", "default": true },
    { "key": "mode",     "type": "choice", "label": "Режим", "default": "a",
      "options": [{ "label": "А", "value": "a" }, { "label": "Б", "value": "b" }] }
  ],
  "items": [ { "type": "button", "label": "Привет", "command": ["notify-send", "Привет"] } ]
}
```

| Поле | Что это |
|---|---|
| `id`, `name`, `icon` | Обязательны `id` и `name`. Плагин с `id` встроенного заменяет его. `icon` — один символ, обычно значок Nerd Font. |
| `category` | Категория панели: `power`, `control`, `media`, `clipboard`, `apps`, `quick`, `today`, `phone`, `ai`, `dev`, `text`, `system`, `net`, `notify` или своя. Новый id создаёт новую категорию (`categoryName`, `categoryIcon`). |
| `priority` | Порядок внутри категории: больше — выше. |
| `items` | Кнопки, поля и списки, запускающие команды. Код не нужен (см. README). |
| `qml` | Свой интерфейс раздела в панели. Корневой элемент получает `api` (раздел 3). |
| `bar` | QML-элемент для бара (раздел 5). Появляется в «Настройки» → «Бар» и сразу включён. |
| `settings` | Настройки в «Настройки» → «Плагины», под плагином. Типы: `text`, `number`, `toggle`, `choice`. Читаются как `api.settings.<key>`. |
| `contextActions` | Кнопки над выделенным текстом или буфером. |
| `daemon` | Фоновый процесс, стартует вместе с оболочкой. |
| `wide`, `keywords`, `output`, `confirm`, `close`, `handoff` | См. README. |

Команды получают `$QP_TEXT`, `$QP_DIR` (папка плагина), `$QP_FOCUSED` (окно в фокусе, JSON), `$QP_SELECTION`,
`$QP_CLIPBOARD`, `$QP_STYLE`, а в argv — подстановки `{text}` и `{dir}`.

---

## 2. Виджеты: widget.json и widget.qml

```json
{ "name": "Обратный отсчёт", "icon": "F051F", "description": "Сколько дней до даты", "stats": false,
  "settings": [{ "key": "date", "type": "text", "label": "Дата", "default": "2027-01-01" }] }
```

В `widget.qml` корневой элемент со свойствами `property var api` и `property var cfg`: в `cfg` — значения
`settings` этого экземпляра (виджет можно добавить несколько раз). Размер — из `implicitWidth` и `implicitHeight`.

Виджет получает тот же `api`, что плагины, плюс:

| | |
|---|---|
| `api.now` | Текущая дата (обновляется раз в минуту) |
| `api.k` | Масштаб, выбранный пользователем (умножай на него размеры) |
| `api.tint`, `api.sub` | Основной и второстепенный цвет текста, выбранные пользователем |
| `api.cpu`, `api.mem` | Загрузка процессора и памяти в %, при `"stats": true` |

---

## 3. Объект `api` (плагины и виджеты)

У каждого плагина и виджета свой объект: хранилище, настройки и уведомления — от его имени.

### Основное

| | |
|---|---|
| `api.version` | `1` |
| `api.owner` | id плагина (у виджета — `widget-<id>`) |
| `api.theme` | Все токены дизайна: `theme.surface`, `theme.text`, `theme.accent`, `theme.r(16)` (скругление), `theme.fs(13)` (размер шрифта), `theme.isLight`… С `import qs` доступен и сам `Theme`. |
| `api.accent`, `api.accentText`, `api.iconFont` | Сокращения |
| `api.shown` | Панель открыта |
| `api.contextText` | Выделение или буфер на момент открытия панели |

### Действия

| | |
|---|---|
| `api.run(argv, text)` | Запустить программу (без shell); `text` — в `$QP_TEXT` |
| `api.copy(text)` | Скопировать в буфер |
| `api.flash(icon, text, color)` | Короткое сообщение в острове |
| `api.notify(title, body, icon)` | Уведомление от имени плагина |
| `api.close()` | Закрыть панель |
| `api.openCategory(id)` | Перейти в категорию панели |
| `api.openUrl(url)` | Открыть ссылку или файл |
| `api.launchApp(entry)` | Запустить приложение (`DesktopEntry`) |
| `api.setAwake(on)` | Включить или выключить «не засыпать» |
| `api.setPref(key, value)` | Изменить настройку оболочки (`config.json`, раздел `panel`) |

### Хранилище

Файл `~/.local/state/glide-shell/plugin-<id>.json`. Записывается чуть позже последнего изменения и переживает
перезапуск.

```qml
readonly property int clicks: api.storage.get("clicks", 0)   // привязка обновится сама
onClicked: api.storage.set("clicks", clicks + 1)
```

`api.storage.get(key, default)`, `api.storage.set(key, value)` (любое значение JSON), `api.storage.remove(key)`,
`api.storage.all`.

### Настройки

`api.settings` — значения `settings` из манифеста, а без них — `default`. Пользователь меняет их в
«Настройки» → «Плагины», привязки обновляются сами. Из кода — `api.setSetting(key, value)`.

### Состояние системы

| | |
|---|---|
| `api.niri` | niri: `workspaces` (список), `windows` (id → окно), `focusedWindow`, `focusedOutput`, `action([...])` — любое `niri msg action`, `focusWindow(id)`, `closeWindow(id)` |
| `api.player`, `api.players` | Текущий и все плееры MPRIS: `trackTitle`, `trackArtist`, `isPlaying`, `togglePlaying()`… |
| `api.volume`, `api.muted`, `api.setVolume(0…1.5)`, `api.setMuted(bool)` | Звук основного выхода |
| `api.battery` | `{present, percent, charging}` |
| `api.dnd` | Включено «не беспокоить» |
| `api.weather` | `data.now`, `data.days`, `temp(t)`, `icon(code, day)`, `describe(code)` |
| `api.notifs` | История уведомлений и «не беспокоить» |
| `api.awake`, `api.powerTimer`, `api.recorder`, `api.kdeconnect`, `api.appCounts` | Понятно по названию |

### «Живые активности»

Строка в острове под часами — загрузка, сборка, отсчёт и т. п. Показывается самая свежая; при наведении — подпись,
кнопка и «×».

```qml
api.activity.start("sync", { title: "Синхронизация фото", progress: 0, icon: "󰓦" })
api.activity.update("sync", { progress: 0.4, subtitle: "120 из 300" })
api.activity.end("sync")
```

Поля: `title`, `subtitle`, `icon` (один значок), `progress` (0…1; меньше 0 — бегущая полоска без процента), `color`,
`actionLabel` с `onAction` (кнопка), `onClick` (щелчок по строке). Пользователь может выключить активности в
«Настройки» → «Остров». Из скрипта: `qs -c glide-shell ipc call panel activity ID "Название" 0.5` (пустое название
убирает строку).

### События

```qml
Connections {
    target: api
    ignoreUnknownSignals: true          // api приходит после создания элемента
    function onOpened() {}               // панель открылась
    function onClosed() {}
    function onThemeUpdated() {}         // сменились акцент, тон или светлая/тёмная тема
    function onNotification(e) {}        // {appName, summary, body, urgency, time}
}
```

---

## 4. Раздел плагина (qml)

```qml
import QtQuick
import QtQuick.Layouts
import qs

ColumnLayout {
    property var api
    property string pluginDir          // сюда запишется папка плагина
    Text { text: api ? api.settings.greeting : ""; color: Theme.text; font.pixelSize: Theme.fs(14) }
}
```

Цвета, скругления и шрифты бери только из `Theme` (`Theme.r(16)`, `Theme.fs(13)`). Тогда плагин следует за тоном,
акцентом, светлой темой, скруглениями и размером текста пользователя. Длительности анимаций — через
`Prefs.ms(200)`: так они слушаются настройки «Анимации», вплоть до выключения. Если QML не собрался, ошибка
показывается прямо в разделе плагина.

---

## 5. Элемент бара (bar)

```qml
import QtQuick
import qs

Item {
    id: chip
    property var api
    readonly property bool want: !!api && api.settings.showBar   // виден, только пока true
    implicitWidth: row.implicitWidth                            // размер — от содержимого…
    implicitHeight: 24
    Row { id: row; anchors.verticalCenter: parent.verticalCenter
          Text { text: "󰐱"; color: Theme.accent; font.family: chip.api ? chip.api.iconFont : "" } }
    MouseArea { anchors.fill: parent; onClicked: chip.api.openCategory("quick") }   // …а щелчок — поверх
}
```

Оболочка ставит элемент в левый или правый остров, пользователь выбирает в «Настройки» → «Бар». Ширина — не больше
240 px. Не задавай размер `Row` через его же детей: `width: parent.width` внутри `Row` даёт бесконечный пересчёт.

---

## 6. Отладка

- Журнал: `journalctl --user -u glide-shell -f` (предупреждения QML и `console.log`).
- Проверить, что QML собирается, без перезапуска оболочки: `qs -p <папка>` с `shell.qml`
  `ShellRoot { Component.onCompleted: console.warn(Qt.createComponent("Main.qml").errorString()) }`.
- Виджеты перечитываются после правки файла, плагины — при каждом открытии панели.

---

## 7. Другие программы: D-Bus `org.glide.Shell` и команда `glide-shell`

С оболочкой может говорить любая программа через сессионную шину: Python, C++, Rust, Go или скрипт с `gdbus`.
Служба запускается сама при первом обращении (D-Bus activation), поэтому памяти не занимает, пока не нужна.

Имя `org.glide.Shell`, объект `/org/glide/Shell`, интерфейс `org.glide.Shell1`:

| Метод | |
|---|---|
| `Flash(s icon, s text)` | Короткое сообщение в острове |
| `StartActivity(s id, a{sv} props)` | «Живая активность» (раздел 3): `title`, `subtitle`, `icon`, `progress` (d), `color`, `actionLabel`. Исчезает сама, когда твоя программа уходит с шины; `persist: true` — оставить. |
| `UpdateActivity(s id, a{sv} props)` | Изменить часть полей (применяется не чаще 4 раз в секунду) |
| `EndActivity(s id)` | Убрать |
| `OpenPanel(s category)`, `ClosePanel()`, `Search(s text)` | Панель |
| `SetDnd(b)`, `GetDnd() → b` | «Не беспокоить» (включённое вручную) |
| `GetTheme() → a{sv}` | `accent`, `accentText`, `isLight`, `tone`, `background`, `surface`, `surfaceHigh`, `outline`, `text`, `textSecondary`, `radius`, `font`, `lang` |
| `GetVersion() → s` | Версия оболочки |

| Сигнал | |
|---|---|
| `ThemeChanged(a{sv} theme)` | Пользователь сменил акцент, тон или светлую/тёмную тему — перекрась программу |
| `ActivityClicked(s id)`, `ActivityAction(s id)`, `ActivityClosed(s id)` | Щелчок по твоей активности, её кнопке или «×» |

```sh
gdbus call --session --dest org.glide.Shell --object-path /org/glide/Shell \
  --method org.glide.Shell1.StartActivity build "{'title': <'Сборка'>, 'progress': <0.3>}"
```

```python
from gi.repository import Gio, GLib
bus = Gio.bus_get_sync(Gio.BusType.SESSION)
bus.call_sync("org.glide.Shell", "/org/glide/Shell", "org.glide.Shell1", "Flash",
              GLib.Variant("(ss)", ("", "Экспорт готов")), None, 0, -1, None)
```

Для скриптов — команда `glide-shell` (`~/.local/bin/glide-shell`):

```sh
glide-shell flash "Копия готова"
glide-shell activity start backup --title "Резервная копия" --progress 0.1
glide-shell activity update backup --progress 0.8 --subtitle "8 из 10 ГБ"
glide-shell activity end backup
glide-shell open control | close | search "текст"
glide-shell dnd on | off | (без аргумента — показать)
glide-shell theme      # JSON
glide-shell watch      # сигналы строками JSON
```

Активности, запущенные командой, живут, пока их не снимут: сама команда сразу завершается.
