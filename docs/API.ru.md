# API Glide Shell

[English](API.md) · **Русский**

Расширить Glide Shell можно тремя способами:

| Что | Где | На чём |
|---|---|---|
| **Плагин** — раздел в панели, команды в поиске, элемент бара | `~/.config/glide-shell/plugins/<id>/` | JSON + любые скрипты или QML |
| **Виджет рабочего стола** | `~/.config/glide-shell/widgets/<id>/` | QML |
| **Чужое приложение**, которое общается с оболочкой | D-Bus / команда `glide-shell` | любой язык |

Версия API — **2**, в `plugin.json` пишется `"api": 2`. Плагины с `"api": 1` (или без поля) загружаются, но сторонний
такой плагин не получает разрешений, пока ты их не выдашь (раздел 3б). Что появилось во второй версии — [раздел 3а](#3a-novoe-v-versii-2), разрешения —
[раздел 3б](#3b-razresheniya), как перевести плагин — [раздел 12](#12-perehod-s-versii-1-na-2).

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
> - **Ставь только плагины, которые прочитал или автору которых доверяешь.** Подробно — [раздел 10](#10-bezopasnost-dannye-i-sovmestimost).
> - **Это не проверяли специалисты по безопасности.** Систему плагинов и разрешений сделал один человек, который не
>   разбирается глубоко в кибербезопасности, а искать дыры ему помогал ИИ-ассистент. Считай это добросовестной
>   попыткой, а не гарантией, и сообщай, если найдёшь уязвимость.

## <a id="oglavlenie"></a>Оглавление

<!-- toc -->
- [0. Полный пример](#0-polnyy-primer)
- [1. plugin.json](#1-pluginjson)
- [2. Виджеты: widget.json и widget.qml](#2-vidzhety-widgetjson-i-widgetqml)
- [3. Объект `api` (плагины и виджеты)](#3-obekt-api-plaginy-i-vidzhety)
  - [Основное](#osnovnoe)
  - [Действия](#deystviya)
  - [Хранилище](#hranilische)
  - [Настройки](#nastroyki)
  - [Состояние системы](#sostoyanie-sistemy)
  - [«Живые активности»](#zhivye-aktivnosti)
  - [События](#sobytiya)
  - [Справочник: точное поведение](#spravochnik-tochnoe-povedenie)
- [3а. Новое в версии 2](#3a-novoe-v-versii-2)
  - [Язык и журнал](#yazyk-i-zhurnal)
  - [Таймеры](#taymery)
  - [Файлы](#fayly)
  - [Сеть](#set)
  - [Сообщения между плагинами](#soobscheniya-mezhdu-plaginami)
  - [Цвет острова](#cvet-ostrova)
  - [Поиск](#poisk)
  - [Вопрос, выбор файла, напоминания, буфер](#vopros-vybor-fayla-napominaniya-bufer)
  - [Справочник версии 2](#spravochnik-versii-2)
- [3б. Разрешения](#3b-razresheniya)
  - [Как попросить](#kak-poprosit)
  - [Что видит человек](#chto-vidit-chelovek)
  - [Почему только человек](#pochemu-tolko-chelovek)
  - [Чего разрешения не делают](#chego-razresheniya-ne-delayut)
- [4. Раздел плагина (qml)](#4-razdel-plagina-qml)
- [4а. Где выполняется код плагина и сколько он живёт](#4a-gde-vypolnyaetsya-kod-plagina-i-skolko-on-zhivet)
  - [Производительность](#proizvoditelnost)
- [5. Элемент бара (bar)](#5-element-bara-bar)
- [6. Отладка](#6-otladka)
  - [Поделиться плагином](#podelitsya-plaginom)
- [7. Другие программы: D-Bus `org.glide.Shell` и команда `glide-shell`](#7-drugie-programmy-d-bus-orgglideshell-i-komanda-glide-shell)
- [8. Значки и прогресс в доке (Unity LauncherEntry)](#8-znachki-i-progress-v-doke-unity-launcherentry)
- [9. Токены Theme](#9-tokeny-theme)
- [10. Безопасность, данные и совместимость](#10-bezopasnost-dannye-i-sovmestimost)
  - [Песочницы нет](#pesochnicy-net)
  - [Как выключить сломанный плагин](#kak-vyklyuchit-slomannyy-plagin)
  - [Что бывает при ошибках](#chto-byvaet-pri-oshibkah)
  - [Данные](#dannye)
  - [Совместимость](#sovmestimost)
- [11. Рецепты: что выбрать для задачи](#11-recepty-chto-vybrat-dlya-zadachi)
- [12. Переход с версии 1 на 2](#12-perehod-s-versii-1-na-2)
<!-- /toc -->

---

## <a id="0-polnyy-primer"></a>0. Полный пример

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
    property var api                     // есть уже в Component.onCompleted
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

[↑ К оглавлению](#oglavlenie)

---

## <a id="1-pluginjson"></a>1. plugin.json

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
| `permissions` | Только API 2: какие разрешения нужны — `exec`, `network`, `clipboard`, `notifications`, `windows`, `phone`, `system`, `messages`, `island`, `search` (раздел 3б). Выдаёт их человек; нет поля — никаких. Плагин API 1 просит все (поле не читается) и получает их, только когда ты разрешишь. |
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
| `handoff` | У элемента вместо `command`: `"handoff": "<id плагина>"` (с необязательным `"prompt"`) передаёт текст другому плагину и открывает его категорию. QML-плагин забирает его через `api.takeHandoff(id)`: один раз вернёт `{text, prompt}`, иначе `null`. Забрать (и увидеть в `api.handoff`) можно только переданное самому плагину. |
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

[↑ К оглавлению](#oglavlenie)

---

## <a id="2-vidzhety-widgetjson-i-widgetqml"></a>2. Виджеты: widget.json и widget.qml

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

[↑ К оглавлению](#oglavlenie)

---

## <a id="3-obekt-api-plaginy-i-vidzhety"></a>3. Объект `api` (плагины и виджеты)

У каждого плагина и виджета свой объект: хранилище, настройки и уведомления — от его имени.

### <a id="osnovnoe"></a>Основное

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

### <a id="deystviya"></a>Действия

| | |
|---|---|
| `api.run(argv, text)` | Запустить программу и забыть (без shell, ничего не возвращает); `text` — в `$QP_TEXT`. Разрешение `exec`. |
| `api.exec(argv, opts, callback)` | Запустить и получить результат: `callback(code, stdout, stderr)` вызывается один раз. `opts`: `stdin` (текст), `timeout` в мс (по умолчанию 60000, 0 — без ограничения), `env` (дополнительные переменные; `$QP_DIR` — всегда папка плагина). Возвращает задачу с `cancel()` и `running`. `code` = -1, если программа не запустилась, отменена или вышло время. Аргументы передаются как есть, без shell: кавычки, переносы строк и `{text}` не толкуются. `opts` можно не писать: `api.exec(["date"], (code, out) => …)`. Разрешение `exec`. |
| `api.copy(text)` | Скопировать в буфер (разрешение `clipboard`) |
| `api.flash(icon, text, color)` | Короткое сообщение в острове. Пустой `icon` — галочка, пустой `color` — `Theme.success`. |
| `api.notify(title, body, icon, opts)` | Уведомление от имени плагина. Пустой `icon` — стандартный значок «информация». С 2.11 — кнопки: `opts` = `{id, actions: [{id, label}]}` (до 3; id кнопки — латиница, цифры, `_.-`; `default` — щелчок по самому уведомлению), нажатая — сигнал `notifyAction(id, кнопка)`. Ждут ответа не дольше часа и не больше 5 уведомлений у части (шестое снимает ожидание со старого). |
| `api.close()` | Закрыть панель |
| `api.openCategory(id)` | Перейти в категорию панели |
| `api.openUrl(url)` | Открыть ссылку: `http(s):` и `mailto:` — всегда, остальное (`file://`, схемы приложений) — с разрешением `exec` |
| `api.launchApp(entry)` | Запустить приложение: `DesktopEntry` или его id (`"firefox"`); запускается то, что записано в .desktop |
| `api.setAwake(on)` | Включить или выключить «не засыпать» (разрешение `system`) |
| `api.setPref(key, value)` | Изменить настройку оболочки (`config.json`, раздел `panel`; разрешение `system`) |
| `api.openSettings()` | Открыть «Настройки» → «Плагины» |

### <a id="hranilische"></a>Хранилище

Файл `~/.local/state/glide-shell/plugin-<id>.json`. Записывается чуть позже последнего изменения и переживает
перезапуск.

```qml
readonly property int clicks: api.storage.get("clicks", 0)   // привязка обновится сама
onClicked: api.storage.set("clicks", clicks + 1)
```

`api.storage.get(key, default)`, `api.storage.set(key, value)` (любое значение JSON), `api.storage.remove(key)`,
`api.storage.all`, `api.storage.keys()` (список ключей), `api.storage.clear()` (очистить всё). Любая привязка, где вызывается `api.storage.get`, обновится при смене значения, даже внутри
условия (`a ? api.storage.get(…) : 0`). У раздела плагина и его элемента бара хранилище общее.

### <a id="nastroyki"></a>Настройки

`api.settings` — значения `settings` из манифеста, а без них — `default`. Пользователь меняет их в
«Настройки» → «Плагины», привязки обновляются сами. Из кода — `api.setSetting(key, value)`.

### <a id="sostoyanie-sistemy"></a>Состояние системы

| | |
|---|---|
| `api.niri` | Разрешение `windows`. niri: `workspaces` (список), `windows` (id → окно), `focusedWindow`, `focusedOutput`, `action([...])` — `niri msg action` (первым — имя действия; `spawn`, `spawn-sh`, `quit`, `load-config-file` — только с разрешением `exec`; вернёт `false`, если не выполнено), `focusWindow(id)`, `closeWindow(id)`, `iconFor(appId)`, `titleFor(окно)`, `layouts`, `layoutIdx` |
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

**Глобальные клавиши** (с 2.12, без разрешения — каждую подтверждает человек). `api.hotkey.request(имя, клавиша,
подпись, cb(ok, причина))` — клавиша в записи niri (`Mod+Shift+W`, `Ctrl+Alt+F5`; без модификатора — только `F1…F24`
и `XF86…`), имя — латиница, цифры, `_.-`. Оболочка спрашивает человека от имени плагина; согласие — привязка niri в
`glide-settings.kdl` (видна в «Устройства» → «Горячие клавиши», там же убирается). Причины отказа: `bad` — кривые
имя или клавиша, `busy` — клавиша уже занята (чужую не отнять), `denied` — человек отказал, `error: …` — niri не
принял. То же имя с другой клавишей — переставить. `api.hotkey.remove(имя, cb(ok))`, `api.hotkey.list()` →
`[{name, key, title}]`. Нажатие — сигнал `hotkeyPressed(имя)` всем живым частям плагина (ловить — в службе).

```qml
api.hotkey.request("grab", "Mod+Shift+G", "Захватить", (ok, why) => console.log(ok, why))
Connections { target: api; ignoreUnknownSignals: true; function onHotkeyPressed(name) { if (name === "grab") … } }
```

**События окон** (с 2.10, разрешение `windows`): `windowOpened(окно)`, `windowChanged(окно)` — сменились заголовок
или приложение (сдвиги и размеры — нет), `windowClosed(окно)`, `windowFocused(окно)` — `null`, если фокуса нет ни у
одного окна. Окно — копия того, что отдаёт niri (`id`, `title`, `app_id`, `workspace_id`, `is_floating`…). Список окон
при запуске оболочки событиями не приходит — он уже в `api.niri.windows`. Фокус приходит последним в пачке событий.

```qml
Connections {
    target: api; ignoreUnknownSignals: true
    function onWindowFocused(w) { cur = w ? w.app_id : "" }   // например, считать время по приложениям
}
```

### <a id="zhivye-aktivnosti"></a>«Живые активности»

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

### <a id="sobytiya"></a>События

```qml
Connections {
    target: api
    ignoreUnknownSignals: true          // не мешает; было нужно до Glide Shell 1.1
    function onOpened() {}               // панель открылась
    function onClosed() {}
    function onThemeUpdated() {}         // сменились акцент, тон или светлая/тёмная тема
    function onNotification(e) {}        // {appName, summary, body, urgency, time}; разрешение notifications
    function onPermissionsUpdated() {}   // API 2: человек выдал или забрал разрешение
    function onMessage(from, name, data) {}   // API 2: сообщение от другого плагина (api.send)
}
```

### <a id="spravochnik-tochnoe-povedenie"></a>Справочник: точное поведение

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
| `notify(title, body, icon, opts)` | `true` | — | Через `notify-send`; «не беспокоить» действует, как на любую программу. `opts.actions` — кнопки (с 2.11), сигнал `notifyAction(id, action)` |
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

[↑ К оглавлению](#oglavlenie)

---

## <a id="3a-novoe-v-versii-2"></a>3а. Новое в версии 2

Всё ниже есть у каждого плагина и виджета, в том числе с `"api": 1`.

### <a id="yazyk-i-zhurnal"></a>Язык и журнал

| | |
|---|---|
| `api.lang` | Язык интерфейса: `"ru"` или `"en"` |
| `api.tr(ru, en)` | Строка на языке интерфейса: `api.tr("Готово", "Done")`. В привязке сменится вместе с языком. |
| `api.log(…)`, `api.warn(…)` | В журнал с пометкой `[id]`; объекты пишутся как JSON |

### <a id="taymery"></a>Таймеры

В JavaScript внутри QML нет `setTimeout`. У `api` есть:

```qml
api.setTimeout(() => api.flash("", "Прошла минута"), 60000)
var tick = api.setInterval(() => root.count++, 1000)
api.clearTimer(tick)
```

Таймеры живут не дольше этой части плагина: раздел уничтожен — его таймеры тоже. Долгие держи в службе (раздел 4а).

### <a id="fayly"></a>Файлы

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

### <a id="set"></a>Сеть

```qml
api.http("https://api.github.com/repos/owner/repo", { headers: { Accept: "application/json" } }, (status, text) => {
    if (status === 200) root.stars = JSON.parse(text).stargazers_count
})
```

Разрешение `network`. `opts`: `method` (по умолчанию `GET`), `headers`, `body` (строка, объект уходит как JSON),
`timeout` в мс (30000). `status` = 0 — нет разрешения, сети, ответа за `timeout` или адрес не `http(s)://`.
Возвращает `{abort()}`.

### <a id="soobscheniya-mezhdu-plaginami"></a>Сообщения между плагинами

```qml
api.send("water", "drink", { glasses: 1 })   // одному плагину по id; "*" — всем
Connections {
    target: api
    ignoreUnknownSignals: true
    function onMessage(from, name, data) { if (name === "drink") root.add(data.glasses) }
}
```

Сообщение получают все созданные сейчас части адресата: раздел, элемент бара, служба. `data` приходит копией (через
JSON). `send` возвращает `true`, если сообщение ушло.

**Свои части — без разрешения.** Раздел, служба и элемент бара одного плагина — разные объекты. `api.send("<свой id>",
…)` доходит до остальных частей своего плагина, но не до той, что отправила. Так раздел просит службу что-то сделать:

```qml
// Main.qml (раздел)                                 // Service.qml (служба)
onClicked: api.send("devhub", "sync", {})           function onMessage(from, name, data) { if (name === "sync") svc.load() }
```

**Другим плагинам — разрешение `messages`** (с Glide Shell 1.3): без него `send` чужому id ничего не отправляет и
возвращает `false`, а сообщения от других плагинов не приходят. Нужно и отправителю, и получателю. `"*"` без
разрешения доходит только до своих частей. Плагины старого формата, одобренные целиком до 1.3, получили `messages`
сами. Общие данные между своими частями можно держать и в `api.storage`: файл один, изменение видят все части.

### <a id="cvet-ostrova"></a>Цвет острова

С Glide Shell 1.3, разрешение `island`. Плагин может окрасить остров: заливку с лёгким оттенком и обводку.

```qml
api.island.tint("#7b61ff")   // true — принято; плохой цвет или нет разрешения — false
api.island.clear()           // убрать свой цвет
```

Если цветов несколько, остров показывает их все неподвижным градиентом слева направо. Камера (зелёный), микрофон
(янтарный) и демонстрация или запись экрана (красный) всегда стоят первыми — плагин не может их скрыть. Цветов
плагинов — не больше трёх, последние заданные. У плагина один цвет: новый `tint` заменяет прежний. Прозрачность
отбрасывается. Цвет снимается сам, когда уничтожается часть, которая его задала, и когда человек забирает разрешение;
поэтому долгий цвет задавай из службы. `api.island.colors` — что сейчас у острова от плагинов (`[{owner, color}]`).

### <a id="poisk"></a>Поиск

С Glide Shell 2.5, разрешение `search`. Плагин добавляет свои результаты в общий поиск панели — ответ прямо в строке:
калькулятор, перевод единиц, смайлики, заметки, закладки. Провайдер задают из **службы** (`service`): она живёт всё
время, а раздел — только пока открыт.

```qml
// Service.qml
Component.onCompleted: api.search.provide((q, done) => {
    if (q.indexOf("todo ") !== 0) return []                          // не наше — пусто, быстро
    return [{ id: "add", title: "Добавить задачу: " + q.slice(5), glyph: 0xF0415 }]   // сразу — массивом
    // или позже: api.http(…, (st, text) => done([…])) и return undefined
})
Connections { target: api; ignoreUnknownSignals: true
              function onSearchActivated(id) { if (id === "add") … } }
```

Провайдера зовут после каждой паузы в наборе (80 мс) с текстом запроса. Ответ — массив сразу или `done(массив)` позже;
ответ на устаревший запрос отбрасывается. От плагина — не больше 5 результатов. Поля результата:

| Поле | Что это |
|---|---|
| `title` | Обязательно. Главная строка (до 200 знаков) |
| `sub` | Подпись справа, мелко |
| `glyph` | Значок: число — код Nerd Font (`0xF00EC`), строка — символ обычным шрифтом (смайлик, буква) |
| `icon` | Или значок темы по имени (`"firefox"`) |
| `copy` | Выбрали — этот текст в буфер, вспышка «Скопировано» |
| `url` | Выбрали — открыть (`http:`, `https:`, `mailto:`; другие схемы отбрасываются) |
| `id` | Нет `copy` и `url` — выбрали, и плагину приходит `searchActivated(id)` |
| `top` | `true` — над приложениями (ответ на запрос: результат вычисления), иначе — после команд плагинов |

Провайдер вызывается в главном потоке: долгую работу (сеть, программы) делай через `done` — `api.http`, `api.exec`, —
а не циклом. Ошибка в провайдере — предупреждение в журнале, остальной поиск работает. `api.search.stop()` — убрать
свой провайдер (он убирается и сам вместе с частью плагина). Разрешение `search` видит всё, что набирают в поиске,
поэтому его, как и остальные, выдаёт человек.

### <a id="vopros-vybor-fayla-napominaniya-bufer"></a>Вопрос, выбор файла, напоминания, буфер

С Glide Shell 2.8.

**Вопрос человеку** — окно рисует оболочка, а не плагин: имя плагина в заголовке берётся из реестра, подделать
его нельзя. Разрешений не нужно — решает человек. Enter — да, Esc — нет; пока экран заперт, вопрос ждёт.

```qml
api.confirm("Удалить 3 заметки?", { yes: "Удалить", no: "Оставить" }, ok => { if (ok) … })
```

От части плагина — один вопрос за раз (второй сразу получает `false`), текст — до 500 знаков, простой.

**Выбор файла** — окно выбора (портал FileChooser, без него — zenity). Разрешений не нужно: выбор человека и есть
согласие. `read: true` — сразу и содержимое (до 16 МБ на файл, как текст).

```qml
api.pickFile({ title: "Импорт", filters: [{ name: "Текст", patterns: ["*.txt", "*.md"] }], read: true },
             (paths, texts) => { if (paths) … })            // отмена — null
api.saveFile("заметки.md", text, { title: "Экспорт" }, path => { … })   // пишет туда, куда выбрал человек
```

**Напоминания** переживают перезапуск оболочки (файл `~/.local/state/glide-shell/schedules.json`, 0600). Срок
пришёл — сигнал `scheduled(id, data, late)` всем живым частям плагина; ловить — в **службе**. Если ни одной части нет
(служба ещё не запустилась), напоминание ждёт. `late` — опоздало больше чем на минуту (оболочка не работала, сон).

```qml
api.schedule.at("call", "2026-11-01T10:00", { who: "мама" })   // или Date, или мс с 1970
api.schedule.after("tea", 5 * 60000, {})                       // через 5 минут
api.schedule.cancel("tea"); api.schedule.list()                // [{id, at, data}]
Connections { target: api; ignoreUnknownSignals: true; function onScheduled(id, data, late) { … } }
```

Одноразовые; у плагина — до 50, `data` — до 4 КБ JSON.

**Смена буфера** — разрешение `clipboard`. `api.clipboard.listen(true)` — и на каждую смену текста приходит
`clipboardUpdated(text)` (до 20 000 байт; пароли, помеченные менеджером паролей, не приходят). Слушатель `wl-paste`
работает, только пока кто-то слушает; `listen(false)` или забранное разрешение — перестать.

**«До перезапуска».** В вопросе о разрешении человек может выбрать «До перезапуска»: разрешение действует до
перезапуска оболочки и в `permissions.json` не пишется. Для плагина это обычное выданное разрешение.

### <a id="spravochnik-versii-2"></a>Справочник версии 2

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
| `send(to, name, data)` | `bool`: ушло | — | `data` — то, что принимает `JSON.stringify`. Чужому id — разрешение `messages` |
| `island.tint(color)`, `island.clear()` | `bool` / ничего | — | Разрешение `island`. Цвет — `#rgb`, `#rrggbb`, `#aarrggbb` или имя |
| `island.colors` | список `{owner, color}` | да | |
| `confirm(text, opts, cb)` | `bool`: спросили | — | С 2.8. `cb(ok)` один раз; второй вопрос от части — `false` |
| `pickFile(opts, cb)`, `saveFile(name, text, opts, cb)` | `bool` | — | С 2.8. `cb(paths, texts)` / `cb(path)`; отмена — `null` |
| `schedule.at(id, when, data)`, `schedule.after(id, ms, data)`, `schedule.cancel(id)`, `schedule.list()` | `bool` / список | — | С 2.8. Сигнал `scheduled(id, data, late)` |
| `clipboard.listen(on)` | `bool` | — | С 2.8, разрешение `clipboard`. Сигнал `clipboardUpdated(text)` |
| `hotkey.request(name, key, title, cb)`, `hotkey.remove(name, cb)`, `hotkey.list()` | `bool` / список | — | С 2.12, каждую клавишу подтверждает человек. Сигнал `hotkeyPressed(name)` |
| `search.provide(fn)`, `search.stop()` | `bool` / ничего | — | С Glide Shell 2.5, разрешение `search`. `fn(q, done)` — массив или `done(массив)` |
| `usage.timers`, `usage.exec`, `usage.http` | `num` | да | С Glide Shell 1.6: живые таймеры этой части, запуски программ и запросы в сеть с её создания. Их показывает «Настройки» → «Процессы» |
| Сигналы `permissionsUpdated`, `message(from, name, data)`, `searchActivated(id)`, `scheduled(id, data, late)`, `clipboardUpdated(text)`, `windowOpened/Changed/Closed/Focused(окно)` (с 2.10, `windows`), `notifyAction(id, кнопка)` (с 2.11), `hotkeyPressed(имя)` (с 2.12) | | | Через `Connections { target: api; ignoreUnknownSignals: true }` |

[↑ К оглавлению](#oglavlenie)

---

## <a id="3b-razresheniya"></a>3б. Разрешения

Плагин API 2 без разрешений может только безопасное: рисовать раздел и элемент бара, хранить свои данные, показывать
вспышки, уведомления от своего имени и активности, читать тему, погоду, плеер, звук и батарею. Остальное — по
разрешениям. **Выдаёт и меняет их только человек**, плагин может лишь попросить.

| Разрешение | Что открывает |
|---|---|
| `exec` | `api.run`, `api.exec`, а ещё `daemon` и команды в `items` и `contextActions`. **Полный доступ**: запущенная программа может всё, что можешь ты |
| `network` | `api.http` |
| `clipboard` | `api.contextText` (выделение и буфер), `api.copy`, `api.clipboard.listen` |
| `notifications` | `api.notifs` (история чужих уведомлений) и событие `notification` |
| `windows` | `api.niri`: окна, рабочие столы, действия niri; события окон `windowOpened`… |
| `phone` | `api.kdeconnect`: телефоны, их уведомления и команды |
| `system` | `api.setPref`, `api.setAwake`, `api.recorder`. **Почти полный доступ**: настройками оболочки можно многое |
| `messages` | `api.send` другим плагинам и сообщения от них. Между частями своего плагина не нужно |
| `island` | `api.island.tint`: цвет острова |
| `search` | `api.search`: видеть, что набирают в поиске панели, и добавлять туда свои результаты |

Без разрешения функции ничего не делают (`exec` отвечает `code` = -1, `http` — `status` = 0), свойства пустые
(`contextText` = `""`, `niri`, `notifs`, `kdeconnect`, `recorder` = `null`), в журнале — одно предупреждение.
Кнопка с командой без `exec` показывает вспышку и спрашивает разрешение.

### <a id="kak-poprosit"></a>Как попросить

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

### <a id="chto-vidit-chelovek"></a>Что видит человек

В «Настройки» → «Плагины» под каждым сторонним плагином — строка «Разрешения: 1 из 2»; щелчок раскрывает
переключатели. Включить — тот же вопрос с паролем, выключить — сразу, без пароля. Встроенным плагинам разрешения не
нужны: они часть оболочки. Разрешения своих виджетов — внизу той же вкладки.

### <a id="pochemu-tolko-chelovek"></a>Почему только человек

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

### <a id="chego-razresheniya-ne-delayut"></a>Чего разрешения не делают

Песочницы по-прежнему нет (раздел 10): QML плагина выполняется внутри оболочки и может импортировать `Quickshell.Io`
и запустить программу в обход `api`. Разрешения — договор между плагином и человеком, а не стена. Поэтому оболочка
просматривает код сторонних плагинов и виджетов и пишет под ними: «Код обращается к системе в обход разрешений:
Process, XMLHttpRequest». Так помечаются `Quickshell.Io`, `Process`, `execDetached`, `XMLHttpRequest`,
`createQmlObject`, `Pam`, обращения к `Permissions` и `Prefs.set`/`run`/`reset`. Плагину API 2 всё это не нужно,
бери `api`. Увидел такую пометку у плагина, которому не доверяешь, — выключи его. `exec` и `system` по сути дают
полный доступ: выдавай их, только если доверяешь автору.

[↑ К оглавлению](#oglavlenie)

---

## <a id="4-razdel-plagina-qml"></a>4. Раздел плагина (qml)

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

`api` передаётся начальным свойством (с Glide Shell 1.1), поэтому он есть уже в `Component.onCompleted` раздела,
элемента бара и службы. Проверки вида `api ? … : значение` не мешают и сохраняют работу на старых версиях, где `api`
приходил чуть позже. Ширину раздела задаёт панель, высоту
берёт из `implicitHeight`. Корню-`ColumnLayout` или `Column` размер задавать не нужно, фиксированную высоту не ставь.

Цвета, скругления и шрифты бери только из `Theme` (`Theme.r(16)`, `Theme.fs(13)`). Тогда плагин следует за тоном,
акцентом, светлой темой, скруглениями и размером текста пользователя. Длительности анимаций — через
`Prefs.ms(200)`: так они слушаются настройки «Анимации», вплоть до выключения. Если QML не собрался, ошибка
показывается прямо в разделе плагина.

## <a id="4a-gde-vypolnyaetsya-kod-plagina-i-skolko-on-zhivet"></a>4а. Где выполняется код плагина и сколько он живёт

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

### <a id="proizvoditelnost"></a>Производительность

Оболочка обычно занимает меньше 1 % ядра. Один плагин легко поднимает это до 15 %, если:

- **крутит анимацию бесконечно** (`loops: Animation.Infinite`, `running: true` навсегда). Это 60 кадров в секунду
  перерисовки бара или панели всё время. Анимируй только в ответ на событие: изменилось значение, навели мышь.
  Длительности — короткие, не больше 300–400 мс;
- **обновляет активность чаще раза в секунду** или зовёт `activity.start` в таймере. `start` — один раз, дальше
  `update`, и только когда значение правда изменилось. Раз в секунду — дёшево, раз в 150 мс — уже нет;
- **опрашивает** то, о чём есть событие (`onOpened`, сигналы `api.player`, `api.niri`), или запускает программы через
  `api.exec` чаще раза в несколько секунд.

Снять активность при выключении плагина — тоже твоя работа: `api.activity.end` в `Component.onDestruction` службы.

[↑ К оглавлению](#oglavlenie)

---

## <a id="5-element-bara-bar"></a>5. Элемент бара (bar)

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

**Подсказка при наведении.** Дай элементу свойство `tip` — оболочка покажет его в той же выпадающей капле, что у
встроенных значков, и будет обновлять на лету. `tip` — строка или `{title, rows: [{name, value, color}], hint}`
(до 10 строк; только текст, `color` — по желанию). `null` или пустая строка — подсказки нет.

```qml
readonly property var tip: ({ title: "Вода сегодня", rows: [{ name: "Выпито", value: count + " из 8" }],
                              hint: "Щелчок — открыть" })
```

[↑ К оглавлению](#oglavlenie)

---

## <a id="6-otladka"></a>6. Отладка

- Журнал: `journalctl --user -u glide-shell -f` (предупреждения QML и `console.log`).
- Проверить, что QML собирается, без перезапуска оболочки: `qs -p <папка>` с `shell.qml`
  `ShellRoot { Component.onCompleted: console.warn(Qt.createComponent("Main.qml").errorString()) }`.
- Виджеты перечитываются после правки файла. Плагины (`plugin.json`, раздел и элемент бара) — при каждом открытии
  панели: правка видна после того, как закроешь и откроешь панель, перезапуск не нужен.
- Ошибки своего плагина без журнала: «Настройки» → «Процессы» → «ошибок N» у плагина (предупреждения QML этого
  запуска оболочки, кнопка «Скопировать»). Там же — предупреждение о таймерах чаще раза в секунду.

### <a id="podelitsya-plaginom"></a>Поделиться плагином

Своего формата нет: плагин передаётся обычным архивом — `.zip`, `.tar.gz` или `.glideplugin` (тот же zip).
`plugin.json` — в корне архива или в единственной папке внутри.

```sh
tools/glide-plugin.py pack ~/.config/glide-shell/plugins/water      # → water.glideplugin (без скрытых файлов)
glide-shell install-plugin ~/Загрузки/water.glideplugin             # карточка установки в «Плагинах»
```

`pack` делает те же проверки, что и установка. Установить можно из «Настройки» → «Плагины» → «Установить из архива»:
там же видны архивы из «Загрузок». Перед установкой показывается карточка: имя, автор, `description`, `version`,
какие разрешения плагин попросит и пометки аудита. Не ставятся архивы с путями наружу (`../`), ссылками и
особыми файлами, с id встроенного плагина, больше 50 МБ или 2000 файлов. Права файлов из архива не переносятся.
Прежняя версия при замене уходит в `~/.local/state/glide-shell/plugin-backups`. При защите плагинов паролем новый
плагин встаёт выключенным. Разрешения после установки всё равно выдаёт человек.

[↑ К оглавлению](#oglavlenie)

---

## <a id="7-drugie-programmy-d-bus-orgglideshell-i-komanda-glide-shell"></a>7. Другие программы: D-Bus `org.glide.Shell` и команда `glide-shell`

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

[↑ К оглавлению](#oglavlenie)

---

## <a id="8-znachki-i-progress-v-doke-unity-launcherentry"></a>8. Значки и прогресс в доке (Unity LauncherEntry)

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

[↑ К оглавлению](#oglavlenie)

---

## <a id="9-tokeny-theme"></a>9. Токены Theme

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

[↑ К оглавлению](#oglavlenie)

---

## <a id="10-bezopasnost-dannye-i-sovmestimost"></a>10. Безопасность, данные и совместимость

### <a id="pesochnicy-net"></a>Песочницы нет

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

### <a id="kak-vyklyuchit-slomannyy-plagin"></a>Как выключить сломанный плагин

- **«Настройки» → «Плагины»**, переключатель рядом с ним. Если включено «Включать и выключать плагины — по паролю»,
  спросит пароль от входа.
- **Экран блокировки**: «Войти без сторонних плагинов». После правильного пароля выключаются все плагины из
  `~/.config/glide-shell/plugins`, встроенные остаются. Выручает, когда плагин сломал панель или бар.
- **Вручную**: добавь id в `"disabled"` в `~/.config/glide-shell/config.json` или убери папку плагина, затем
  `systemctl --user restart glide-shell`.

### <a id="chto-byvaet-pri-oshibkah"></a>Что бывает при ошибках

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

### <a id="dannye"></a>Данные

| Что | Где | При удалении плагина |
|---|---|---|
| `api.storage` | `~/.local/state/glide-shell/plugin-<id>.json` | Остаётся, удаляй файл вручную |
| `api.settings` | `config.json` → `panel.pluginSettings.<id>` | Остаются; переустановленный плагин получит их обратно |
| `api.files` | `~/.local/share/glide-shell/plugin-data/<id>/` | Остаётся, удаляй папку вручную |
| Разрешения | `~/.config/glide-shell/permissions.json` | Остаются; переустановленный плагин получит их обратно (кроме перехода с API 1 на 2) |
| Процессы `api.exec` и `daemon` | — | Останавливаются при выключении плагина и при выходе оболочки |

Данные привязаны к **`id`** плагина. Сменишь `id` — хранилище начнётся с нуля. Плагин с `id` встроенного заменяет
его и получает его хранилище и настройки.

### <a id="sovmestimost"></a>Совместимость

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

[↑ К оглавлению](#oglavlenie)

---

## <a id="11-recepty-chto-vybrat-dlya-zadachi"></a>11. Рецепты: что выбрать для задачи

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

[↑ К оглавлению](#oglavlenie)

---

## <a id="12-perehod-s-versii-1-na-2"></a>12. Переход с версии 1 на 2

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

[↑ К оглавлению](#oglavlenie)
