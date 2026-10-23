# API Glide Shell

[English](API.md) · **Русский**

Расширить Glide Shell можно тремя способами:

| Что | Где | На чём |
|---|---|---|
| **Плагин** — раздел в панели, команды в поиске, элемент бара | `~/.config/glide-shell/plugins/<id>/` | JSON + любые скрипты или QML |
| **Виджет рабочего стола** | `~/.config/glide-shell/widgets/<id>/` | QML |
| **Чужое приложение**, которое общается с оболочкой | D-Bus / команда `glide-shell` | любой язык |

Версия API — **2**, в `plugin.json` пишется `"api": 2`. Плагины с `"api": 1` (или без поля) загружаются, но сторонний
такой плагин не получает разрешений, пока ты их не выдашь (раздел 3б). Что появилось во второй версии — [раздел 3а](#3а-новое-в-версии-2), разрешения —
[раздел 3б](#3б-разрешения), как перевести плагин — [раздел 12](#12-переход-с-версии-1-на-2).

Быстрый старт: `python3 ~/.config/quickshell/glide-shell/tools/glide-plugin.py new my-plugin "Мой плагин"`
создаёт рабочий плагин, где задействовано всё API ниже: раздел панели, элемент бара и настройки. Для виджета —
`… glide-plugin.py widget my-widget`. Плагин появится при следующем открытии панели.

> **⚠ Коротко о безопасности: прочитай, прежде чем ставить чужой плагин**
>
> - **Песочницы нет.** Плагин работает внутри оболочки с правами твоего пользователя.
> - **Разрешения сдерживают только плагин, который пользуется `api`.** Код с `Process`, `XMLHttpRequest` или
>   внутренностями оболочки (`import qs`) может всё, что можешь ты: читать твои файлы, менять оболочку, переписать
>   себе разрешения. Такой код помечен жёлтым под плагином в «Настройки» → «Плагины».
> - **Разрешения хранятся в `~/.config/glide-shell/permissions.json`.** Правку, пока оболочка работает, она отменяет,
>   но пока оболочка не запущена, файл может изменить любая программа от твоего имени.
> - **Сторонний плагин начинает без разрешений**, в том числе старый, с `"api": 1`. Выдаёшь их ты сам.
> - **Ставь только плагины, которые прочитал или автору которых доверяешь.** Подробно — [раздел 10](#10-безопасность-данные-и-совместимость).

## Оглавление

<!-- toc -->
- [0. Полный пример](#0-полный-пример)
- [1. plugin.json](#1-pluginjson)
- [2. Виджеты: widget.json и widget.qml](#2-виджеты-widgetjson-и-widgetqml)
- [3. Объект `api` (плагины и виджеты)](#3-объект-api-плагины-и-виджеты)
  - [Основное](#основное)
  - [Действия](#действия)
  - [Хранилище](#хранилище)
  - [Настройки](#настройки)
  - [Состояние системы](#состояние-системы)
  - [«Живые активности»](#живые-активности)
  - [События](#события)
  - [Справочник: точное поведение](#справочник-точное-поведение)
- [3а. Новое в версии 2](#3а-новое-в-версии-2)
  - [Язык и журнал](#язык-и-журнал)
  - [Таймеры](#таймеры)
  - [Файлы](#файлы)
  - [Сеть](#сеть)
  - [Сообщения между плагинами](#сообщения-между-плагинами)
  - [Справочник версии 2](#справочник-версии-2)
- [3б. Разрешения](#3б-разрешения)
  - [Как попросить](#как-попросить)
  - [Что видит человек](#что-видит-человек)
  - [Почему только человек](#почему-только-человек)
  - [Чего разрешения не делают](#чего-разрешения-не-делают)
- [4. Раздел плагина (qml)](#4-раздел-плагина-qml)
- [4а. Где выполняется код плагина и сколько он живёт](#4а-где-выполняется-код-плагина-и-сколько-он-живёт)
- [5. Элемент бара (bar)](#5-элемент-бара-bar)
- [6. Отладка](#6-отладка)
- [7. Другие программы: D-Bus `org.glide.Shell` и команда `glide-shell`](#7-другие-программы-d-bus-orgglideshell-и-команда-glide-shell)
- [8. Значки и прогресс в доке (Unity LauncherEntry)](#8-значки-и-прогресс-в-доке-unity-launcherentry)
- [9. Токены Theme](#9-токены-theme)
- [10. Безопасность, данные и совместимость](#10-безопасность-данные-и-совместимость)
  - [Песочницы нет](#песочницы-нет)
  - [Как выключить сломанный плагин](#как-выключить-сломанный-плагин)
  - [Что бывает при ошибках](#что-бывает-при-ошибках)
  - [Данные](#данные)
  - [Совместимость](#совместимость)
- [11. Рецепты: что выбрать для задачи](#11-рецепты-что-выбрать-для-задачи)
- [12. Переход с версии 1 на 2](#12-переход-с-версии-1-на-2)
<!-- /toc -->

---

## 0. Полный пример

Счётчик воды: раздел в панели, элемент бара и две настройки. Здесь — сокращённая версия; полная, с обеими кнопками
и сообщением о выполненной норме, лежит в [`examples/plugins/water`](../examples/plugins/water): скопируй папку в
`~/.config/glide-shell/plugins/water/`.

`plugin.json`:
```json
{
  "id": "water", "api": 2, "name": "Вода", "icon": "󰖌", "category": "quick",
  "qml": "Main.qml", "bar": "Bar.qml", "permissions": [],
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

[↑ К оглавлению](#оглавление)

---

## 1. plugin.json

```json
{
  "id": "my-plugin", "api": 2, "name": "Мой плагин", "icon": "󰐱",
  "category": "quick", "priority": 0, "keywords": ["пример"],
  "permissions": ["exec"],
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
| `api` | Версия API: `1` или `2`. Нет поля — `1`. Новее, чем знает оболочка, — плагин не грузится. |
| `permissions` | Только API 2: какие разрешения нужны — `exec`, `network`, `clipboard`, `notifications`, `windows`, `phone`, `system` (раздел 3б). Выдаёт их человек; нет поля — никаких. Плагин API 1 просит все (поле не читается) и получает их, только когда ты разрешишь. |
| `id`, `name`, `icon` | Обязательны `id` и `name`. Плагин с `id` встроенного заменяет его. `icon` — сам символ (`"󰖌"`, значок Nerd Font) или его код (`"F058C"`); оба вида работают и здесь, и в `widget.json`. |
| `category` | Категория панели: `power`, `control`, `media`, `clipboard`, `apps`, `quick`, `today`, `phone`, `ai`, `dev`, `text`, `system`, `net`, `notify` или своя. Новый id создаёт новую категорию (`categoryName`, `categoryIcon`). |
| `priority` | Порядок внутри категории: больше — выше. |
| `items` | Кнопки, поля и списки, запускающие команды. Код не нужен (см. README). У API 2 команды — с разрешением `exec` (передача `handoff` — без него). |
| `qml` | Свой интерфейс раздела в панели. Корневой элемент получает `api` (раздел 3). |
| `service` | QML без интерфейса, живёт столько же, сколько оболочка: фоновая работа (раздел 4а). |
| `bar` | QML-элемент для бара (раздел 5). Появляется в «Настройки» → «Бар» и сразу включён. |
| `settings` | Настройки в «Настройки» → «Плагины», под плагином (типы ниже). Читаются как `api.settings.<key>`. |
| `contextActions` | Кнопки над выделенным текстом или буфером: `[{"label", "when", "command", "output"}]`. `when`: `text` (по умолчанию), `multiline`, `json`, `xml`, `url`, `host`, `jwt`, `number`, `timestamp`, `path`, `base64`, `urlenc` или список из них. Команда получает текст в `{text}` и `$QP_TEXT`. |
| `daemon` | Фоновый процесс (argv): стартует вместе с оболочкой и останавливается с ней. У API 2 — только с разрешением `exec`. |
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

[↑ К оглавлению](#оглавление)

---

## 2. Виджеты: widget.json и widget.qml

```json
{ "name": "Обратный отсчёт", "icon": "F051F", "description": "Сколько дней до даты", "stats": false,
  "settings": [{ "key": "date", "type": "text", "label": "Дата", "default": "2027-01-01" }] }
```

В `widget.qml` корневой элемент со свойствами `property var api` и `property var cfg`: в `cfg` — значения
`settings` этого экземпляра (виджет можно добавить несколько раз). Размер — из `implicitWidth` и `implicitHeight`.

`"api": 2` и `"permissions"` в `widget.json` — как у плагинов; их разрешения — в «Настройки» → «Плагины», внизу.

Виджет получает тот же `api`, что плагины, плюс:

| | |
|---|---|
| `api.now` | Текущая дата (обновляется раз в минуту) |
| `api.k` | Масштаб, выбранный пользователем (умножай на него размеры) |
| `api.tint`, `api.sub` | Основной и второстепенный цвет текста, выбранные пользователем |
| `api.cpu`, `api.mem` | Загрузка процессора и памяти в %, при `"stats": true` |

[↑ К оглавлению](#оглавление)

---

## 3. Объект `api` (плагины и виджеты)

У каждого плагина и виджета свой объект: хранилище, настройки и уведомления — от его имени.

### Основное

| | |
|---|---|
| `api.version` | Версия API, которую объявил плагин: `1` или `2` |
| `api.shellApi` | Версия API, которую знает оболочка: `2` |
| `api.owner` | id плагина (у виджета — `widget-<id>`) |
| `api.dir` | Папка плагина (то же, что `pluginDir`) |
| `api.theme` | Тот же объект, что `Theme` из `import qs` (оба написания — одно и то же). Все токены дизайна: `theme.surface`, `theme.text`, `theme.accent`, `theme.r(16)` (скругление), `theme.fs(13)` (размер шрифта), `theme.isLight`… С `import qs` доступен и сам `Theme`. |
| `api.accent`, `api.accentText`, `api.iconFont` | Акцентный цвет; цвет текста на заливке акцентом (белый, а на светлых акцентах тёмный); шрифт значков (Nerd Font) |
| `api.date`, `api.today` | Текущая дата (обновляется на каждой минуте и после сна) и `"ГГГГ-ММ-ДД"`. Привяжись к `api.today`, чтобы заметить новый день. |
| `api.shown` | Панель открыта |
| `api.contextText` | Выделение или буфер на момент открытия панели (разрешение `clipboard`) |

### Действия

| | |
|---|---|
| `api.run(argv, text)` | Запустить программу и забыть (без shell, ничего не возвращает); `text` — в `$QP_TEXT`. Разрешение `exec`. |
| `api.exec(argv, opts, callback)` | Запустить и получить результат: `callback(code, stdout, stderr)` вызывается один раз. `opts`: `stdin` (текст), `timeout` в мс (по умолчанию 60000, 0 — без ограничения), `env` (дополнительные переменные; `$QP_DIR` — всегда папка плагина). Возвращает задачу с `cancel()` и `running`. `code` = -1, если программа не запустилась, отменена или вышло время. Аргументы передаются как есть, без shell: кавычки, переносы строк и `{text}` не толкуются. `opts` можно не писать: `api.exec(["date"], (code, out) => …)`. Разрешение `exec`. |
| `api.copy(text)` | Скопировать в буфер (разрешение `clipboard`) |
| `api.flash(icon, text, color)` | Короткое сообщение в острове. Пустой `icon` — галочка, пустой `color` — `Theme.success`. |
| `api.notify(title, body, icon)` | Уведомление от имени плагина. Пустой `icon` — стандартный значок «информация». |
| `api.close()` | Закрыть панель |
| `api.openCategory(id)` | Перейти в категорию панели |
| `api.openUrl(url)` | Открыть ссылку или файл |
| `api.launchApp(entry)` | Запустить приложение (`DesktopEntry`) |
| `api.setAwake(on)` | Включить или выключить «не засыпать» (разрешение `system`) |
| `api.setPref(key, value)` | Изменить настройку оболочки (`config.json`, раздел `panel`; разрешение `system`) |
| `api.openSettings()` | Открыть «Настройки» → «Плагины» |

### Хранилище

Файл `~/.local/state/glide-shell/plugin-<id>.json`. Записывается чуть позже последнего изменения и переживает
перезапуск.

```qml
readonly property int clicks: api.storage.get("clicks", 0)   // привязка обновится сама
onClicked: api.storage.set("clicks", clicks + 1)
```

`api.storage.get(key, default)`, `api.storage.set(key, value)` (любое значение JSON), `api.storage.remove(key)`,
`api.storage.all`, `api.storage.keys()` (список ключей), `api.storage.clear()` (очистить всё). Любая привязка, где вызывается `api.storage.get`, обновится при смене значения, даже внутри
условия (`a ? api.storage.get(…) : 0`). У раздела плагина и его элемента бара хранилище общее.

### Настройки

`api.settings` — значения `settings` из манифеста, а без них — `default`. Пользователь меняет их в
«Настройки» → «Плагины», привязки обновляются сами. Из кода — `api.setSetting(key, value)`.

### Состояние системы

| | |
|---|---|
| `api.niri` | Разрешение `windows`. niri: `workspaces` (список), `windows` (id → окно), `focusedWindow`, `focusedOutput`, `action([...])` — любое `niri msg action`, `focusWindow(id)`, `closeWindow(id)` |
| `api.player`, `api.players` | Текущий и все плееры MPRIS: `trackTitle`, `trackArtist`, `isPlaying`, `togglePlaying()`… |
| `api.volume`, `api.muted`, `api.setVolume(0…1.5)`, `api.setMuted(bool)` | Звук основного выхода |
| `api.battery` | `{present, percent, charging}` |
| `api.dnd` | Включено «не беспокоить» |
| `api.weather` | `data.now`, `data.days`, `temp(t)`, `icon(code, day)`, `describe(code)` |
| `api.notifs` | История уведомлений и «не беспокоить» (разрешение `notifications`) |
| `api.recorder` | Запись экрана (разрешение `system`) |
| `api.kdeconnect` | Телефоны KDE Connect (разрешение `phone`) |
| `api.awake`, `api.powerTimer`, `api.appCounts` | Понятно по названию |

Без разрешения `niri`, `notifs`, `recorder` и `kdeconnect` равны `null` — проверяй: `api.niri ? api.niri.windows : {}`.

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
    function onNotification(e) {}        // {appName, summary, body, urgency, time}; разрешение notifications
    function onPermissionsUpdated() {}   // API 2: человек выдал или забрал разрешение
    function onMessage(from, name, data) {}   // API 2: сообщение от другого плагина (api.send)
}
```

### Справочник: точное поведение

Типы: `str` — строка, `num` — число, `bool`, `obj` — обычный объект JavaScript, `fn` — функция. «Обновляется» значит,
что привязка к свойству пересчитается сама, опрашивать его не нужно.

| Член | Тип / что возвращает | Обновляется | Ошибки и замечания |
|---|---|---|---|
| `version` | `num`: `1` или `2` — поле `api` плагина | — | У плагина API 1 — всегда `1`, как раньше |
| `owner` | `str` | — | `id` плагина или `widget-<id>` |
| `shown` | `bool` | да, сразу | |
| `contextText` | `str` | при открытии панели | Пусто, если ничего не выделено и не скопировано или нет разрешения `clipboard` |
| `date` / `today` | `Date` / `str` `"ГГГГ-ММ-ДД"` | на границе каждой минуты и после сна | |
| `now` | у плагинов `num` (мс с 1970), примерно раз в 20 с; у виджетов `Date`, раз в минуту | да | В новом коде лучше `date` |
| `settings` | `obj` ключ → значение | да, сразу | Нет ключа — `default`; `number` ограничен `min`…`max` |
| `setSetting(key, value)` | ничего | — | Пишется в `config.json`; неизвестный ключ тоже сохранится |
| `storage.get(key, def)` | значение или `def` | да, сразу, во всех частях плагина | |
| `storage.set(key, value)` | ничего | — | `value` — всё, что принимает `JSON.stringify` (строка, число, bool, null, массив, объект). Записывается примерно через 0,3 с после последнего изменения. `undefined` и функции не сохраняются. |
| `storage.remove(key)` | ничего | — | |
| `storage.all` | `obj` | да | Копия для чтения; менять её бесполезно |
| `run(argv, text)` | ничего | — | Запустить и забыть. `argv` — массив строк, первая — программа, ищется в `PATH`. В `PATH` панели может не быть `~/.local/bin`: свои скрипты зови по полному пути. |
| `exec(argv, opts, cb)` | задача: `cancel()`, `running` (`bool`) | — | `cb(code: num, stdout: str, stderr: str)` — один раз. `code` = -1, если программа не нашлась, отменена, вышло время или нет разрешения `exec`. Исключение внутри `cb` пишется в журнал и дальше не идёт. |
| `copy(text)` | ничего | — | Нужен `wl-copy` |
| `flash(icon, text, color)` | ничего | — | Если остров выключен, ничего не показывается |
| `notify(title, body, icon)` | ничего | — | Через `notify-send`; «не беспокоить» действует, как на любую программу |
| `openCategory(id)` | ничего | — | Закрытую панель открывает на этой категории. Если панель уже открыта на ней — закрывает, как горячая клавиша. Неизвестный `id` — ничего не происходит. |
| `openUrl(url)`, `launchApp(entry)`, `close()`, `setAwake(on)` | ничего | — | |
| `setPref(key, value)` | ничего | — | Меняет `config.json` → `panel.<key>`. `pluginLock` так не изменить. |
| `activity.start(id, props)` / `update` / `end` | `start`/`update` возвращают полный id (`<плагин>/<id>`) | — | `update` с неизвестным id запускает его. При выключении плагина активности не убираются — снимай их сам, или пользователь закроет их «×». |
| `theme`, `accent`, `accentText`, `iconFont` | | да, сразу | |
| `niri` | `obj` или `null` | да, по событиям niri | `windows` — словарь id → окно. `null` без разрешения `windows` |
| `player`, `players` | плеер MPRIS / список | да | `player` бывает `null` |
| `volume`, `muted` | `num` 0…1,5 / `bool` | да, сразу | Нет выхода звука — `0` / `false` |
| `battery` | `{present, percent, charging}` | да | На настольном ПК `present` = false |
| `dnd` | `bool` | да | Истина при любой «тишине»: вручную, по расписанию, при показе экрана |
| `weather` | объект | после каждого обновления (раз в 30 мин) | До первого ответа `weather.ok` = false |
| Сигналы `opened`, `closed`, `themeUpdated`, `notification(entry)` | | | Через `Connections { target: api; ignoreUnknownSignals: true }` |

[↑ К оглавлению](#оглавление)

---

## 3а. Новое в версии 2

Всё ниже есть у каждого плагина и виджета, в том числе с `"api": 1`.

### Язык и журнал

| | |
|---|---|
| `api.lang` | Язык интерфейса: `"ru"` или `"en"` |
| `api.tr(ru, en)` | Строка на языке интерфейса: `api.tr("Готово", "Done")`. В привязке сменится вместе с языком. |
| `api.log(…)`, `api.warn(…)` | В журнал с пометкой `[id]`; объекты пишутся как JSON |

### Таймеры

В JavaScript внутри QML нет `setTimeout`. У `api` есть:

```qml
api.setTimeout(() => api.flash("", "Прошла минута"), 60000)
var tick = api.setInterval(() => root.count++, 1000)
api.clearTimer(tick)
```

Таймеры живут не дольше этой части плагина: раздел уничтожен — его таймеры тоже. Долгие держи в службе (раздел 4а).

### Файлы

Своя папка `api.dataDir` — `~/.local/share/glide-shell/plugin-data/<id>/` — для того, что не влезает в
`api.storage`: история, кэш, экспорт. Разрешение не нужно: в чужие папки отсюда не попасть.

```qml
api.files.write("history.json", JSON.stringify(list), ok => {})
api.files.read("history.json", text => { if (text !== null) root.list = JSON.parse(text) })
api.files.list(files => api.log(files.map(f => f.name)))   // [{name, size, mtime}]
api.files.remove("old.txt")
```

Имя — только файл в этой папке: латиница, цифры, `_`, `.` и `-`, не с точки, до 128 знаков. До 16 МБ на файл,
запись атомарная. Папка создаётся при первой записи.

### Сеть

```qml
api.http("https://api.github.com/repos/owner/repo", { headers: { Accept: "application/json" } }, (status, text) => {
    if (status === 200) root.stars = JSON.parse(text).stargazers_count
})
```

Разрешение `network`. `opts`: `method` (по умолчанию `GET`), `headers`, `body` (строка, объект уходит как JSON),
`timeout` в мс (30000). `status` = 0 — нет разрешения, сети, ответа за `timeout` или адрес не `http(s)://`.
Возвращает `{abort()}`.

### Сообщения между плагинами

```qml
api.send("water", "drink", { glasses: 1 })   // одному плагину по id; "*" — всем
Connections {
    target: api
    ignoreUnknownSignals: true
    function onMessage(from, name, data) { if (name === "drink") root.add(data.glasses) }
}
```

Сообщение получают все созданные сейчас части адресата: раздел, элемент бара, служба. `data` приходит копией (через
JSON), себе сообщение не приходит. Разрешение не нужно.

### Справочник версии 2

| Член | Тип / что возвращает | Обновляется | Ошибки и замечания |
|---|---|---|---|
| `shellApi` | `num`, `2` | — | |
| `dir` | `str` | — | Пусто у встроенных виджетов |
| `permissions.requested` | список `str` | — | Что объявлено в `permissions`; у API 1 — все |
| `permissions.granted` | список `str` | да, сразу | Что выдал человек |
| `permissions.has(p)` | `bool` | в привязке — да | |
| `permissions.state(p)` | `"granted"`, `"denied"` или `"ask"` | в привязке — да | `denied` — человек отказал, спрашивать бесполезно |
| `permissions.request(p, reason)` | `bool`: уже выдано | — | Открывает вопрос в настройках. Раз за сеанс; не объявлено в `permissions` — `false` и предупреждение |
| `openSettings()` | ничего | — | |
| `lang`, `tr(ru, en)` | `str` | да | Без `en` — `ru` |
| `log(…)`, `warn(…)` | ничего | — | |
| `setTimeout(fn, ms)`, `setInterval(fn, ms)` | таймер | — | Интервал — не меньше 16 мс. Исключение внутри `fn` — в журнал |
| `clearTimer(t)` | ничего | — | Сработавший `setTimeout` убирается сам, звать не нужно |
| `storage.keys()`, `storage.clear()` | список `str` / ничего | — | |
| `dataDir` | `str` | — | |
| `files.read(name, cb)` | `cb(text)`; нет файла — `cb(null)` | — | |
| `files.write(name, text, cb)` | `cb(ok)` | — | Плохое имя или больше 16 МБ — `false` и предупреждение |
| `files.list(cb)` | `cb([{name, size, mtime}])` | — | `mtime` — мс с 1970 |
| `files.remove(name, cb)` | `cb(ok)` | — | Нет файла — тоже `true` |
| `http(url, opts, cb)` | `{abort()}` | — | `cb(status, text, headers)` — один раз; имена заголовков — строчными |
| `send(to, name, data)` | ничего | — | `data` — то, что принимает `JSON.stringify` |
| Сигналы `permissionsUpdated`, `message(from, name, data)` | | | Через `Connections { target: api; ignoreUnknownSignals: true }` |

[↑ К оглавлению](#оглавление)

---

## 3б. Разрешения

Плагин API 2 без разрешений может только безопасное: рисовать раздел и элемент бара, хранить свои данные, показывать
вспышки, уведомления от своего имени и активности, читать тему, погоду, плеер, звук и батарею. Остальное — по
разрешениям. **Выдаёт и меняет их только человек**, плагин может лишь попросить.

| Разрешение | Что открывает |
|---|---|
| `exec` | `api.run`, `api.exec`, а ещё `daemon` и команды в `items` и `contextActions`. **Полный доступ**: запущенная программа может всё, что можешь ты |
| `network` | `api.http` |
| `clipboard` | `api.contextText` (выделение и буфер), `api.copy` |
| `notifications` | `api.notifs` (история чужих уведомлений) и событие `notification` |
| `windows` | `api.niri`: окна, рабочие столы, действия niri |
| `phone` | `api.kdeconnect`: телефоны, их уведомления и команды |
| `system` | `api.setPref`, `api.setAwake`, `api.recorder`. **Почти полный доступ**: настройками оболочки можно многое |

Без разрешения функции ничего не делают (`exec` отвечает `code` = -1, `http` — `status` = 0), свойства пустые
(`contextText` = `""`, `niri`, `notifs`, `kdeconnect`, `recorder` = `null`), в журнале — одно предупреждение.
Кнопка с командой без `exec` показывает вспышку и спрашивает разрешение.

### Как попросить

1. Объяви в `plugin.json`: `"permissions": ["network"]`. Необъявленное нельзя ни попросить, ни выдать.
2. Проверяй перед использованием, а проси, когда это нужно пользователю, — лучше по его нажатию:

   ```qml
   readonly property bool online: api ? api.permissions.granted.indexOf("network") >= 0 : false
   // …
   onClicked: if (root.api.permissions.request("network", "Загрузить курс валют")) root.load()
   ```

3. `request` открывает «Настройки» → «Плагины» с вопросом: название разрешения, что оно открывает и твоё
   объяснение. Человек нажимает «Разрешить» (с паролем от входа, если включена защита плагинов), «Отказать» или
   «Позже». Ответ приходит в `onPermissionsUpdated`, привязки к `api.permissions.granted` пересчитаются сами.
4. О каждом разрешении плагин спрашивает не чаще раза за сеанс. После «Отказать» не спрашивает вовсе: вернуть
   можно только в настройках.

### Что видит человек

В «Настройки» → «Плагины» под каждым сторонним плагином — строка «Разрешения: 1 из 2»; щелчок раскрывает
переключатели. Включить — тот же вопрос с паролем, выключить — сразу, без пароля. Встроенным плагинам разрешения не
нужны: они часть оболочки. Разрешения своих виджетов — внизу той же вкладки.

### Почему только человек

- Выдать можно только через вопрос в настройках. Если включена защита плагинов (по умолчанию включена), нужен пароль
  от входа; его проверяет PAM, как на экране блокировки. Не зная пароля, плагин себе ничего не выдаст, даже если
  доберётся до внутренних объектов оболочки.
- `api` выдавать не умеет: `setPref` разрешений не касается, D-Bus и `glide-shell` их только показывают
  (`ListPlugins`).
- Разрешения лежат в `~/.config/glide-shell/permissions.json`. Если файл меняют, пока оболочка работает, она
  возвращает своё и показывает предупреждение. Править его вручную можно при остановленной оболочке
  (`systemctl --user stop glide-shell`).
- Сторонний плагин API 1 (или без поля `api`) просит **все** разрешения и не получает **ни одного**, пока ты не
  разрешишь: по одному или кнопкой «Разрешить всё…» под ним (паролем, с предупреждением). До этого его команды и
  `daemon` не работают. Иначе любой получил бы всё молча, просто написав `"api": 1`. Плагины и свои виджеты,
  стоявшие до Glide Shell 1.1, одобрены один раз при обновлении.
- Плагин, перешедший с API 1 на 2, начинает с нуля: решения для старой версии не переносятся.
- Встроенным плагинам всё разрешено, но встроенный — только тот, что лежит в папке самой оболочки. Поле `trusted` в
  своём `plugin.json` ничего не даёт.

### Чего разрешения не делают

Песочницы по-прежнему нет (раздел 10): QML плагина выполняется внутри оболочки и может импортировать `Quickshell.Io`
и запустить программу в обход `api`. Разрешения — договор между плагином и человеком, а не стена. Поэтому оболочка
просматривает код сторонних плагинов и виджетов и пишет под ними: «Код обращается к системе в обход разрешений:
Process, XMLHttpRequest». Так помечаются `Quickshell.Io`, `Process`, `execDetached`, `XMLHttpRequest`,
`createQmlObject`, `Pam`, обращения к `Permissions` и `Prefs.set`/`run`/`reset`. Плагину API 2 всё это не нужно,
бери `api`. Увидел такую пометку у плагина, которому не доверяешь, — выключи его. `exec` и `system` по сути дают
полный доступ: выдавай их, только если доверяешь автору.

[↑ К оглавлению](#оглавление)

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

## 4а. Где выполняется код плагина и сколько он живёт

| Часть | Создаётся | Уничтожается | Для чего |
|---|---|---|---|
| `qml` — раздел | Когда показана его категория | Когда пользователь переключает категорию, начинает поиск или открывает настройки. Закрытие панели его **не** уничтожает. | Интерфейс |
| `bar` — элемент бара | При старте оболочки, если элемент включён («Настройки» → «Бар») | Когда пользователь его скрыл | Компактный индикатор |
| `service` — `"service": "Service.qml"` | Через 6 с после старта оболочки | Когда плагин выключили или оболочка завершилась | **Фоновая работа**: таймеры, слежение за файлами, активности |
| `daemon` — любая программа | Вместе с оболочкой | Вместе с оболочкой | Работа вне QML |

Служба — QML-объект без интерфейса (`QtObject` или `Item`), получает тот же `api`. Таймеры и `api.activity` держи
там. В разделе только пиши в `api.storage`: служба и элемент бара увидят изменение сразу. Если работу делает элемент
бара, она остановится, когда пользователь уберёт его из бара.

```qml
// Service.qml
import QtQuick
Item {
    id: svc
    property var api
    Timer { interval: 1000; repeat: true; running: !!svc.api; onTriggered: { /* … */ } }
}
```

После правки все части плагина — раздел, элемент бара и служба — перезагружаются при следующем открытии панели.

**Имена, которые нельзя давать своим свойствам.** `left`, `right`, `top`, `bottom`, `x`, `y`, `z`, `width`, `height`,
`data`, `children`, `parent`, `state`, `states`, `visible`, `enabled`, `opacity`, `scale`, `clip` и другие свойства
`Item` заняты. Свойство `left` не даёт загрузиться всему файлу с ошибкой «Cannot override FINAL property». Имена,
начинающиеся с `on` и заглавной буквы, — это обработчики сигналов, а не свойства. Бери `remaining`, `endAt` и
подобные.

QML: нужен Qt 6.8 или новее, так что встроенные компоненты (`component Btn: Rectangle {…}`) можно.
`api.activity.update` из QML ничем не ограничен, раз в секунду — дёшево.

[↑ К оглавлению](#оглавление)

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

[↑ К оглавлению](#оглавление)

---

## 6. Отладка

- Журнал: `journalctl --user -u glide-shell -f` (предупреждения QML и `console.log`).
- Проверить, что QML собирается, без перезапуска оболочки: `qs -p <папка>` с `shell.qml`
  `ShellRoot { Component.onCompleted: console.warn(Qt.createComponent("Main.qml").errorString()) }`.
- Виджеты перечитываются после правки файла. Плагины (`plugin.json`, раздел и элемент бара) — при каждом открытии
  панели: правка видна после того, как закроешь и откроешь панель, перезапуск не нужен.

[↑ К оглавлению](#оглавление)

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
| `GetApiVersion() → u` | Версия API плагинов: `2` |
| `ListPlugins() → aa{sv}` | Плагины: `id`, `name`, `icon`, `disabled`, `user` (сторонний), `api`, `permissions` (что просит), `granted` (что выдано), `problem`. Только чтение: выдаёт разрешения человек в настройках |
| `OpenSettings(s page)` | Открыть настройки на разделе: `plugins`, `look`, `bar`…; пусто — «Вид» |

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
glide-shell plugins    # плагины и их разрешения, JSON
glide-shell settings plugins
glide-shell version | api
```

`GetApiVersion`, `ListPlugins` и `OpenSettings` появились в Glide Shell 1.0. Интерфейс по-прежнему
`org.glide.Shell1`: новые методы только добавлены.

Активности, запущенные командой, живут, пока их не снимут: сама команда сразу завершается.

[↑ К оглавлению](#оглавление)

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

[↑ К оглавлению](#оглавление)

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

[↑ К оглавлению](#оглавление)

---

## 10. Безопасность, данные и совместимость

### Песочницы нет

Плагин или виджет работает **от твоего имени** и с твоими правами, а QML-части выполняются **внутри процесса
оболочки**:

- Он может читать и менять любые твои файлы, в том числе хранилища других плагинов в `~/.local/state/glide-shell/`
  и настройки самой оболочки. Он может запускать любые программы и ходить в сеть.
- Он видит то же, что панель: выделенный текст, буфер обмена, уведомления.
- Бесконечный цикл в QML подвешивает всю оболочку. При падении её перезапустит systemd, а после нескольких падений
  подряд включится аварийный запасной вариант.
- Оболочка не проверяет, откуда плагин. Читай код перед установкой. `plugin.json` с `daemon` или `items` тоже
  запускает команды (у API 2 — только с разрешением `exec`).
- Разрешения API 2 (раздел 3б) ограничивают то, что плагин делает через `api`, но не код в обход него. Такой код
  оболочка помечает под плагином в «Плагинах».


**От чего защищают разрешения, а от чего нет.** Решение принимает оболочка, а не объект `api`. Код, создающий `api`
плагина, до передачи регистрирует его с настоящим id и замороженной копией манифеста. Поэтому перезапись `api.owner`
или `api.manifest`, как и правка объекта манифеста, ничего не даёт. Хранилище, файлы, настройки, активности и
сообщения тоже идут от зарегистрированного id. Через объект `api` до остальной оболочки не добраться. Обойти систему
плагин может только через `import qs` (`Permissions`, `Core`, `Prefs.set`, свой `ApiScope`) или типы Quickshell
(`Process`, `XMLHttpRequest`). Такой код аудит помечает под плагином в «Настройки» → «Плагины»: плагин с такими
пометками ставь, только если доверяешь автору.

### Как выключить сломанный плагин

- **«Настройки» → «Плагины»**, переключатель рядом с ним. Если включено «Включать и выключать плагины — по паролю»,
  спросит пароль от входа.
- **Экран блокировки**: «Войти без сторонних плагинов». После правильного пароля выключаются все плагины из
  `~/.config/glide-shell/plugins`, встроенные остаются. Выручает, когда плагин сломал панель или бар.
- **Вручную**: добавь id в `"disabled"` в `~/.config/glide-shell/config.json` или убери папку плагина, затем
  `systemctl --user restart glide-shell`.

### Что бывает при ошибках

| Что сломалось | Что видно |
|---|---|
| QML раздела не загрузился | Текст ошибки на месте раздела |
| Элемент бара не загрузился | Элемент скрыт, предупреждение в журнале |
| Служба не загрузилась | Предупреждение в журнале |
| Поле `api` новее, чем знает оболочка, или не число | Плагин не грузится, причина — под ним в «Плагинах» |
| `permissions` — не список строк | Плагин не грузится, причина — под ним в «Плагинах» |
| В `permissions` неизвестное имя | Пропускается, предупреждение в журнале |
| Нет разрешения | Функция ничего не делает, свойство пустое, одно предупреждение в журнале |
| `permissions.json` изменили в обход настроек | Изменение отменяется, предупреждение в острове |
| Исключение в твоём обработчике (`exec`, `onAction`…) | Пишется в журнал, оболочка работает дальше |
| Файл хранилища повреждён | Хранилище начинается пустым, старый файл сохраняется как `plugin-<id>.json.broken` |

### Данные

| Что | Где | При удалении плагина |
|---|---|---|
| `api.storage` | `~/.local/state/glide-shell/plugin-<id>.json` | Остаётся, удаляй файл вручную |
| `api.settings` | `config.json` → `panel.pluginSettings.<id>` | Остаются; переустановленный плагин получит их обратно |
| `api.files` | `~/.local/share/glide-shell/plugin-data/<id>/` | Остаётся, удаляй папку вручную |
| Разрешения | `~/.config/glide-shell/permissions.json` | Остаются; переустановленный плагин получит их обратно (кроме перехода с API 1 на 2) |
| Процессы `api.exec` и `daemon` | — | Останавливаются при выключении плагина и при выходе оболочки |

Данные привязаны к **`id`** плагина. Сменишь `id` — хранилище начнётся с нуля. Плагин с `id` встроенного заменяет
его и получает его хранилище и настройки.

### Совместимость

- Версия API — поле `api`: `1` или `2`. Glide Shell 1.0 понимает обе. Стороннему плагину API 1 на всё нужно
  твоё согласие (раздел 3б); новое из версии 2 (раздел 3а) есть и у него.
- В пределах версии только добавляется новое: поля `api`, поля манифеста, необязательные аргументы, методы и
  сигналы D-Bus.
- **Несовместимое** требует версии 3. Это убрать или переименовать что-то из этого справочника, сменить тип или
  возвращаемое значение, изменить, когда что-то создаётся или уничтожается, изменить смысл поля манифеста. Интерфейс
  D-Bus тогда станет `org.glide.Shell2`, а `org.glide.Shell1` продолжит работать рядом.
- Устаревшее сначала помечается здесь словом «устарело» и работает до следующей версии API.
- Каждую версию проверяет автотест на соответствие контрактам версий 1 и 2 (`tests/test_api_contract.py`).
- Требования: Quickshell 0.3+, Qt 6.8+, niri. Проверено на Quickshell 0.3.2, Qt 6.12, niri 26.04.
- Стабильно только описанное здесь. Остальное, что видно через `import qs`, — внутреннее.

[↑ К оглавлению](#оглавление)

---

## 11. Рецепты: что выбрать для задачи

| Задача | Что взять | Пример |
|---|---|---|
| Кнопка, запускающая команду, без кода | `items` с `command` и `output` | `{"type": "button", "label": "IP", "command": ["curl", "-s", "ifconfig.me"], "output": "copy+notify"}` |
| Действие над выделенным текстом | `contextActions` с `when` | `{"label": "Слова", "when": "text", "command": ["sh", "-c", "printf %s \"$QP_TEXT\" \| wc -w"], "output": "notify"}` |
| Интерфейс в панели | `qml` + `api.storage` + `api.settings` | Раздел 0 |
| Число в баре, открывающее твой раздел | `bar` с `want` + `api.openCategory` | Раздел 5 |
| Работа, пока панель закрыта (таймер, слежение) | `service` + `api.storage` | Раздел 4а; раздел панели только пишет настройки |
| Долгая задача с прогрессом и «Отмена» | `service` + `api.exec` + `api.activity` с `actionLabel` / `onAction: job.cancel` | ниже |
| Заметить новый день или смену темы | привязка к `api.today` / `onThemeUpdated` | Раздел 3 |
| Виджет с настройками | `settings` в `widget.json` + `cfg` | Раздел 2 |
| Своя программа показывает прогресс или читает тему | D-Bus `org.glide.Shell` или `glide-shell` | Раздел 7 |
| Число непрочитанных на значке своей программы в доке | Сигнал Unity LauncherEntry | Раздел 8 |
| Запрос в интернет | `api.http` + `"permissions": ["network"]` | Раздел 3а |
| История, кэш, экспорт — больше, чем для `storage` | `api.files` | Раздел 3а |
| Отложить действие или повторять его | `api.setTimeout` / `api.setInterval` | Раздел 3а |
| Связать два своих плагина | `api.send` + `onMessage` | Раздел 3а |
| Попросить разрешение по нажатию | `api.permissions.request` + `onPermissionsUpdated` | Раздел 3б |

Долгая задача с прогрессом и «Отмена» — в службе:

```qml
import QtQuick
Item {
    id: svc
    property var api
    property var job: null
    function backup() {
        api.activity.start("backup", { title: "Резервная копия", progress: -1, actionLabel: "Отмена",
                                       onAction: function () { if (svc.job) svc.job.cancel() } })
        job = api.exec(["rsync", "-a", "/home/me/Документы/", "/mnt/backup/"], { timeout: 0 }, (code, out, err) => {
            api.activity.end("backup")
            api.flash("", code === 0 ? "Копия готова" : "Копия не удалась: " + (err.trim() || code))
            svc.job = null
        })
    }
}
```

[↑ К оглавлению](#оглавление)

---

## 12. Переход с версии 1 на 2

1. В `plugin.json` поставь `"api": 2`.
2. Перечисли в `"permissions"` то, чем пользуешься (таблица в разделе 3б). Ничего не нужно — `"permissions": []`.
3. `api.niri`, `api.notifs`, `api.kdeconnect` и `api.recorder` без разрешения равны `null`: проверяй перед
   обращением.
4. Проси разрешение, когда оно понадобилось пользователю (`api.permissions.request` по нажатию), а не при запуске.
5. Убери обходы — их видит человек в «Плагинах»:

   | Было | Стало | Разрешение |
   |---|---|---|
   | `import Quickshell.Io` + `Process { … }` | `api.exec(argv, opts, cb)` | `exec` |
   | `Quickshell.execDetached(…)` | `api.run(argv)` | `exec` |
   | `XMLHttpRequest` | `api.http(url, opts, cb)` | `network` |
   | `FileView` со своим файлом | `api.files` или `api.storage` | — |
   | `Timer` ради одной задержки | `api.setTimeout(fn, ms)` | — |
   | `Prefs.set(…)` | `api.setPref(key, value)` | `system` |

6. Проверь в «Настройки» → «Плагины» → «Разрешения»: выключи каждое и посмотри, что плагин ведёт себя прилично —
   объясняет, чего не хватает, и не сыплет ошибками в журнал.

Заготовка `glide-plugin.py new` сразу делает плагин API 2 с запросом разрешения.

[↑ К оглавлению](#оглавление)
