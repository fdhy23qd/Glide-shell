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

## 0. Полный пример

Счётчик воды: раздел в панели, элемент бара и две настройки. Здесь — сокращённая версия; полная, с обеими кнопками
и сообщением о выполненной норме, лежит в [`examples/plugins/water`](../examples/plugins/water): скопируй папку в
`~/.config/glide-shell/plugins/water/`.

`plugin.json`:
```json
{
  "id": "water", "api": 1, "name": "Вода", "icon": "󰖌", "category": "quick",
  "qml": "Main.qml", "bar": "Bar.qml",
  "settings": [
    { "key": "goal",    "type": "number", "label": "Норма, стаканов в день", "default": 8, "min": 4, "max": 14, "step": 1 },
    { "key": "showBar", "type": "toggle", "label": "Показывать в баре", "default": true }
  ]
}
```

`Main.qml` — раздел в панели:
```qml
import QtQuick
import QtQuick.Layouts
import qs

ColumnLayout {
    id: root
    property var api                     // приходит сразу после создания, до этого null
    spacing: 12
    readonly property int goal: api ? api.settings.goal : 8
    // api.today меняется в полночь — вчерашний счёт сам перестаёт считаться
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
    Rectangle {   // кнопка с наведением и нажатием
        implicitWidth: 120; implicitHeight: 32; radius: Theme.r(16)
        color: ma.pressed ? Theme.accentPressed : ma.containsMouse ? Theme.accentLight : Theme.accent
        scale: ma.pressed ? 0.95 : 1
        Behavior on color { ColorAnimation { duration: Prefs.ms(120) } }
        Behavior on scale { NumberAnimation { duration: Prefs.ms(140); easing.type: Easing.OutBack } }
        Text { anchors.centerIn: parent; text: "+1 стакан"; color: Theme.accentText; font.pixelSize: Theme.fs(13) }
        MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                    onClicked: root.add(1) }
    }
}
```

`Bar.qml` — элемент бара:
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
| `id`, `name`, `icon` | Обязательны `id` и `name`. Плагин с `id` встроенного заменяет его. `icon` — сам символ (`"󰖌"`, значок Nerd Font) или его код (`"F058C"`); оба вида работают и здесь, и в `widget.json`. |
| `category` | Категория панели: `power`, `control`, `media`, `clipboard`, `apps`, `quick`, `today`, `phone`, `ai`, `dev`, `text`, `system`, `net`, `notify` или своя. Новый id создаёт новую категорию (`categoryName`, `categoryIcon`). |
| `priority` | Порядок внутри категории: больше — выше. |
| `items` | Кнопки, поля и списки, запускающие команды. Код не нужен (см. README). |
| `qml` | Свой интерфейс раздела в панели. Корневой элемент получает `api` (раздел 3). |
| `bar` | QML-элемент для бара (раздел 5). Появляется в «Настройки» → «Бар» и сразу включён. |
| `settings` | Настройки в «Настройки» → «Плагины», под плагином (типы ниже). Читаются как `api.settings.<key>`. |
| `contextActions` | Кнопки над выделенным текстом или буфером: `[{"label", "when", "command", "output"}]`. `when`: `text` (по умолчанию), `multiline`, `json`, `xml`, `url`, `host`, `jwt`, `number`, `timestamp`, `path`, `base64`, `urlenc` или список из них. Команда получает текст в `{text}` и `$QP_TEXT`. |
| `daemon` | Фоновый процесс (argv): стартует вместе с оболочкой и останавливается с ней. |
| `keywords` | Дополнительные слова для поиска. |
| `wide` | `true` — категория с этим плагином открывается широкой карточкой. |
| `handoff` | У элемента вместо `command`: `"handoff": "<id плагина>"` (с необязательным `"prompt"`) передаёт текст другому плагину и открывает его категорию. QML-плагин забирает его через `api.takeHandoff(id)`: один раз вернёт `{text, prompt}`, иначе `null`. |
| `output` | У элемента: `"copy"`, `"notify"` или `"copy+notify"`. Вывод команды уходит в буфер и/или уведомление; ненулевой код возврата тоже придёт уведомлением. |
| `confirm` | У кнопки: срабатывает только со второго нажатия (в течение 3 секунд). |
| `close` | У элемента: `false` — не закрывать панель после действия. |

Типы настроек (у каждой — `key`, `label`, `default`, по желанию `hint` — серая строка под названием):

| `type` | Как выглядит | Дополнительно |
|---|---|---|
| `text` | Поле, Enter применяет | — |
| `number` | Кнопки со всеми значениями, если от `min` до `max` не больше 12 шагов, иначе поле | `min`, `max`, `step` (по умолчанию 1); `api.settings` всегда отдаёт число в этих пределах |
| `toggle` | Переключатель | — |
| `choice` | Ряд вариантов | `options: [{label, value}]` |

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
| `api.theme` | Тот же объект, что `Theme` из `import qs` (оба написания — одно и то же). Все токены дизайна: `theme.surface`, `theme.text`, `theme.accent`, `theme.r(16)` (скругление), `theme.fs(13)` (размер шрифта), `theme.isLight`… С `import qs` доступен и сам `Theme`. |
| `api.accent`, `api.accentText`, `api.iconFont` | Акцентный цвет; цвет текста на заливке акцентом (белый, а на светлых акцентах тёмный); шрифт значков (Nerd Font) |
| `api.date`, `api.today` | Текущая дата (обновляется на каждой минуте и после сна) и `"ГГГГ-ММ-ДД"`. Привяжись к `api.today`, чтобы заметить новый день. |
| `api.shown` | Панель открыта |
| `api.contextText` | Выделение или буфер на момент открытия панели |

### Действия

| | |
|---|---|
| `api.run(argv, text)` | Запустить программу (без shell); `text` — в `$QP_TEXT` |
| `api.copy(text)` | Скопировать в буфер |
| `api.flash(icon, text, color)` | Короткое сообщение в острове. Пустой `icon` — галочка, пустой `color` — `Theme.success`. |
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
`api.storage.all`. Любая привязка, где вызывается `api.storage.get`, обновится при смене значения, даже внутри
условия (`a ? api.storage.get(…) : 0`). У раздела плагина и его элемента бара хранилище общее.

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
`actionLabel` с `onAction` (кнопка), `onClick` (щелчок по строке). `onAction` и `onClick` — обычные функции
JavaScript в том же объекте:

```qml
api.activity.start("tea", {
    title: "Чай заваривается", progress: 0, actionLabel: "Стоп",
    onAction: function () { api.activity.end("tea") },        // кнопка
    onClick: function () { api.openCategory("quick") }        // щелчок по строке
})
```

`update` сохраняет функции, переданные в `start`, если не передать новые. Пользователь может выключить активности в
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

`api` назначается сразу после создания элемента, поэтому в первый момент это `null`. Привязки пиши как
`api ? … : значение`, обработчики — как `root.api.…` (они срабатывают позже). Ширину раздела задаёт панель, высоту
берёт из `implicitHeight`. Корню-`ColumnLayout` или `Column` размер задавать не нужно, фиксированную высоту не ставь.

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
- Виджеты перечитываются после правки файла. Плагины (`plugin.json`, раздел и элемент бара) — при каждом открытии
  панели: правка видна после того, как закроешь и откроешь панель, перезапуск не нужен.

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

---

## 8. Значки и прогресс в доке (Unity LauncherEntry)

Док понимает общий стандарт, которым пользуются Telegram, Chromium и Firefox (загрузки), Steam, Thunderbird и
другие: сигнал сессионной шины `com.canonical.Unity.LauncherEntry.Update(s "application://<id>.desktop", a{sv} props)`.
`count` (x) и `count-visible` (b) дают красное число на значке, `progress` (d) и `progress-visible` (b) — полоску
под ним, `urgent` (b) — красную точку. Когда программа уходит с шины, значки снимаются. Своей программе достаточно
отправить сигнал:

```python
bus.emit_signal(None, "/com/example/app", "com.canonical.Unity.LauncherEntry", "Update",
                GLib.Variant("(sa{sv})", ("application://my-app.desktop",
                                          {"count": GLib.Variant("x", 3), "count-visible": GLib.Variant("b", True)})))
```

---

## 9. Токены Theme

`import qs` даёт `Theme`, тот же объект — `api.theme`. Эти имена стабильны в пределах версии API 1:

| Токен | Для чего |
|---|---|
| `background` | Фон панели и острова |
| `surface`, `surfaceLow`, `surfaceHigh`, `surfaceHigher`, `surfacePressed` | Карточки и кнопки; наведение — `surfaceHigher`, нажатие — `surfacePressed` |
| `outline`, `outlineHover`, `divider` | Обводки и разделители |
| `text`, `textVariant`, `textSecondary`, `textMuted`, `textFaint` | Текст, от главного к самому второстепенному |
| `accent`, `accentSoft`, `accentHover`, `accentLight`, `accentPressed` | Акцент пользователя; кнопка под курсором — `accentLight`, нажатая — `accentPressed`, мягкая заливка — `accentSoft` |
| `accentText` | Текст на заливке акцентом: белый, а на светлых акцентах — тёмный |
| `error`, `errorContainer`, `errorHover`, `errorText`, `success`, `warning` | Цвета состояний |
| `isLight` | Включена светлая тема |
| `r(n)`, `radiusSm/Md/Lg/Xl` | Скругление с учётом настройки пользователя |
| `fs(n)` | Размер шрифта с учётом настройки пользователя |
| `disabledOpacity` | Прозрачность недоступного элемента |

Всё остальное, что видно через `import qs` (`Prefs`, `Niri`, `Notifs`…), — внутреннее и может меняться между
версиями. Где есть поле `api`, бери его. Исключение — стабильная `Prefs.ms(n)`: длительность анимации с учётом
настройки «Анимации».

Чтобы элемент выглядел как остальные, у него должны быть три состояния. Под курсором — светлее и курсор-рука.
При нажатии — темнее и чуть меньше (0.95). Недоступный — `Theme.disabledOpacity` и обычная стрелка.
