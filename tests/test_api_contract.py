"""Контракт API версий 1 и 2 (docs/API.md): всё, что обещано плагинам, виджетам и другим программам, должно оставаться.

Добавлять новое можно; убрать или переименовать что-то из списков ниже — несовместимое изменение (нужна версия 3,
см. «Совместимость» в docs/API.md). install.sh гоняет этот тест перед каждой установкой.
"""
import json
import os
import re
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# api.* — свойства, функции и сигналы (ApiScope.qml)
API_V1 = {
    # основное
    "version", "owner", "theme", "accent", "accentText", "iconFont", "shown", "contextText", "handoff",
    # действия
    "run", "exec", "copy", "flash", "notify", "close", "openCategory", "openUrl", "launchApp", "setAwake", "setPref",
    "takeHandoff",
    # хранилище, настройки, активности
    "storage", "settings", "setSetting", "activity",
    # система
    "niri", "player", "players", "volume", "muted", "setVolume", "setMuted", "battery", "dnd", "weather", "notifs",
    "awake", "powerTimer", "recorder", "kdeconnect", "appCounts", "date", "today", "now",
    # виджеты
    "k", "tint", "sub", "cpu", "mem",
    # события
    "opened", "closed", "themeUpdated", "notification",
}
# версия 2: всё из версии 1 и это
API_V2 = API_V1 | {
    "shellApi", "dir", "permissions", "permissionsUpdated", "openSettings",
    "lang", "tr", "log", "warn", "setTimeout", "setInterval", "clearTimer",
    "dataDir", "files", "http", "send", "message",
}
PERMISSIONS_OBJ_V2 = {"requested", "granted", "has", "request", "state"}
FILES_V2 = {"read", "write", "list", "remove"}
PERMISSIONS_V2 = ["exec", "network", "clipboard", "notifications", "windows", "phone", "system", "messages", "island"]
STORAGE_V1 = {"get", "set", "remove", "all"}
STORAGE_V2 = STORAGE_V1 | {"keys", "clear"}
ACTIVITY_V1 = {"start", "update", "end"}
THEME_V1 = {"background", "surface", "surfaceLow", "surfaceHigh", "surfaceHigher", "surfacePressed", "outline",
            "outlineHover", "divider", "text", "textVariant", "textSecondary", "textMuted", "textFaint", "accent",
            "accentSoft", "accentHover", "accentLight", "accentPressed", "accentText", "error", "errorContainer",
            "errorHover", "errorText", "success", "warning", "isLight", "r", "fs", "radiusSm", "radiusMd", "radiusLg",
            "radiusXl", "disabledOpacity"}
DBUS_METHODS_V1 = {"Flash", "StartActivity", "UpdateActivity", "EndActivity", "OpenPanel", "ClosePanel", "Search",
                   "SetDnd", "GetDnd", "GetTheme", "GetVersion"}
DBUS_SIGNALS_V1 = {"ThemeChanged", "ActivityClicked", "ActivityAction", "ActivityClosed"}
DBUS_METHODS_V2 = DBUS_METHODS_V1 | {"GetApiVersion", "ListPlugins", "OpenSettings"}
MANIFEST_V1 = {"id", "api", "name", "icon", "category", "priority", "keywords", "qml", "bar", "service", "settings",
               "items", "contextActions", "daemon", "wide", "handoff", "output", "confirm", "close"}
MANIFEST_V2 = MANIFEST_V1 | {"permissions"}


def members(qml_text):
    """Имена свойств, функций и сигналов верхнего уровня и вложенных объектов QML (грубо, по объявлениям)."""
    names = set()
    for m in re.finditer(r"^\s*(?:readonly\s+)?(?:required\s+)?property\s+[\w<>.]+\s+(\w+)", qml_text, re.M):
        names.add(m.group(1))
    names.update(re.findall(r"^\s*function\s+(\w+)\s*\(", qml_text, re.M))
    names.update(re.findall(r"^\s*signal\s+(\w+)", qml_text, re.M))
    return names


def block(qml_text, name):
    """Тело вложенного объекта «readonly property QtObject <name>: QtObject { … }»."""
    m = re.search(r"property\s+QtObject\s+" + name + r"\s*:\s*QtObject\s*\{", qml_text)
    if not m:
        return ""
    depth, i = 1, m.end()
    while depth and i < len(qml_text):
        depth += {"{": 1, "}": -1}.get(qml_text[i], 0)
        i += 1
    return qml_text[m.end():i]


class Contract(unittest.TestCase):
    def test_api_object(self):
        qml = (ROOT / "ApiScope.qml").read_text()
        missing = API_V2 - members(qml)
        self.assertFalse(missing, f"из api пропало: {sorted(missing)}")
        self.assertFalse(STORAGE_V2 - members(block(qml, "storage")), "api.storage неполный")
        self.assertFalse(ACTIVITY_V1 - members(block(qml, "activity")), "api.activity неполный")
        self.assertFalse(PERMISSIONS_OBJ_V2 - members(block(qml, "permissions")), "api.permissions неполный")
        self.assertFalse(FILES_V2 - members(block(qml, "files")), "api.files неполный")
        self.assertIn("readonly property int shellApi: 2", qml)

    def test_permission_names(self):
        """Один и тот же список разрешений — в оболочке, в qp-discover и в обоих справочниках."""
        sys.path.insert(0, str(ROOT / "tools"))
        from qp_audit import PERMISSIONS
        self.assertEqual(PERMISSIONS, PERMISSIONS_V2)
        qml = (ROOT / "Permissions.qml").read_text()
        self.assertIn("readonly property var all: " + json.dumps(PERMISSIONS_V2).replace('", "', '", "'), qml)
        for doc in ("docs/API.md", "docs/API.ru.md"):
            text = (ROOT / doc).read_text()
            for name in PERMISSIONS_V2:
                self.assertIn(f"`{name}`", text, f"{doc}: не описано разрешение {name}")

    def test_theme_tokens(self):
        missing = THEME_V1 - members((ROOT / "Theme.qml").read_text())
        self.assertFalse(missing, f"из Theme пропало: {sorted(missing)}")

    def test_dbus_interface(self):
        src = (ROOT / "tools/glide-shell.py").read_text()
        self.assertIn('"org.glide.Shell1"', src)   # имя интерфейса с версией: несовместимое — только в Shell2
        self.assertFalse(DBUS_METHODS_V2 - set(re.findall(r'<method name="(\w+)"', src)), "пропал метод D-Bus")
        self.assertFalse(DBUS_SIGNALS_V1 - set(re.findall(r'<signal name="(\w+)"', src)), "пропал сигнал D-Bus")

    def test_manifest_fields_documented(self):
        for doc in ("docs/API.md", "docs/API.ru.md"):
            text = (ROOT / doc).read_text()
            for field in MANIFEST_V2:
                self.assertIn(f"`{field}`", text, f"{doc}: нет поля {field}")
            signals = {"opened", "closed", "themeUpdated", "notification", "permissionsUpdated", "message"}   # onOpened…
            for name in API_V2 - {"k", "tint", "sub", "cpu", "mem", "now", "notifs", "handoff"}:
                shown = ("on" + name[0].upper() + name[1:]) if name in signals else name
                self.assertTrue(shown in text, f"{doc}: не описано api.{shown}")

    def test_manifest_api_version(self):
        """Нет поля api — версия 1; новее, чем знает оболочка, или не число — плагин не грузится, причина — в списке."""
        with tempfile.TemporaryDirectory() as tmp:
            cfg = Path(tmp) / "cfg"
            for pid, api in (("noapi", None), ("v1", 1), ("v2", 2), ("v3", 3), ("bad", "1")):
                d = cfg / "glide-shell" / "plugins" / pid
                d.mkdir(parents=True)
                m = {"id": pid, "name": pid, "category": "test"}
                if api is not None:
                    m["api"] = api
                (d / "plugin.json").write_text(json.dumps(m))
            r = subprocess.run([sys.executable, "-I", str(ROOT / "tools/qp-discover.py")], capture_output=True, text=True,
                               stdin=subprocess.DEVNULL, timeout=30,
                               env={**os.environ, "XDG_CONFIG_HOME": str(cfg), "XDG_STATE_HOME": str(Path(tmp) / "st"),
                                    "XDG_CACHE_HOME": str(Path(tmp) / "cache")})
            out = json.loads(r.stdout)
            loaded = {p["id"] for p in out["plugins"]}
            self.assertTrue({"noapi", "v1", "v2"} <= loaded)
            self.assertFalse({"v3", "bad"} & loaded)
            problems = {p["id"]: p.get("problem", "") for p in out["allPlugins"]}
            self.assertIn("API 3", problems["v3"])
            self.assertTrue(problems["bad"])
            users = {p["id"]: p.get("user") for p in out["allPlugins"]}
            self.assertTrue(users["v1"])                                   # из ~/.config — сторонний
            self.assertFalse(any(v for k, v in users.items() if k not in ("noapi", "v1", "v2", "v3", "bad")))   # встроенные — нет
            # безопасный режим: выключить список разом, повторно — без дублей
            (cfg / "glide-shell" / "config.json").write_text('{"disabled": ["v1"]}')
            for _ in range(2):
                subprocess.run([sys.executable, "-I", str(ROOT / "tools/qp-config.py"), "disable-many", '["v1", "noapi"]'],
                               check=True, stdin=subprocess.DEVNULL, env={**os.environ, "XDG_CONFIG_HOME": str(cfg)})
            self.assertEqual(json.loads((cfg / "glide-shell" / "config.json").read_text())["disabled"], ["v1", "noapi"])


def discover(cfg, tmp):
    r = subprocess.run([sys.executable, "-I", str(ROOT / "tools/qp-discover.py")], capture_output=True, text=True,
                       stdin=subprocess.DEVNULL, timeout=30,
                       env={**os.environ, "XDG_CONFIG_HOME": str(cfg), "XDG_STATE_HOME": str(Path(tmp) / "st")})
    out = json.loads(r.stdout)
    return {p["id"]: p for p in out["allPlugins"]}, {p["id"]: p for p in out["plugins"]}


class Permissions(unittest.TestCase):
    """API 2: что просит плагин и что выдано (правило — в qp-discover.py и Permissions.qml)."""

    def test_rules(self):
        with tempfile.TemporaryDirectory() as tmp:
            cfg = Path(tmp) / "cfg"
            plugins = {
                "old": {"api": 1},
                "new": {"api": 2, "permissions": ["exec", "network", "bogus"]},
                "none": {"api": 2},
                "upgraded": {"api": 2, "permissions": ["exec"]},
                "sneaky": {"api": 2, "qml": "Main.qml"},
                "badlist": {"api": 2, "permissions": "exec"},
            }
            for pid, extra in plugins.items():
                d = cfg / "glide-shell" / "plugins" / pid
                d.mkdir(parents=True)
                (d / "plugin.json").write_text(json.dumps({"id": pid, "name": pid, "category": "test", **extra}))
            (cfg / "glide-shell" / "plugins" / "sneaky" / "Main.qml").write_text(
                "import QtQuick\nimport Quickshell.Io\nItem { Process { command: ['id'] } }\n")
            every, loaded = discover(cfg, tmp)
            self.assertEqual(every["old"]["permissions"], PERMISSIONS_V2)        # API 1 — просит всё…
            self.assertEqual(every["old"]["granted"], [])                        # …но без согласия человека — ничего (v1.1)
            self.assertEqual(every["new"]["permissions"], ["exec", "network"])   # неизвестное — мимо
            self.assertEqual(every["new"]["unknownPermissions"], ["bogus"])
            self.assertEqual(every["new"]["granted"], [])                         # API 2 — ничего, пока человек не выдаст
            self.assertEqual(every["none"]["permissions"], [])
            self.assertIn("Process", every["sneaky"]["audit"])
            self.assertIn("Quickshell.Io", every["sneaky"]["audit"])
            self.assertEqual(every["new"]["audit"], [])
            self.assertTrue(every["badlist"]["problem"])
            self.assertNotIn("badlist", loaded)
            self.assertIs(loaded["new"]["trusted"], False)
            builtin = [p for p in every.values() if not p["user"]]
            self.assertTrue(builtin and all(p["granted"] == p["permissions"] for p in builtin))   # встроенным — всё
            self.assertTrue(all(p["trusted"] for p in loaded.values() if not every[p["id"]]["user"]))
            # человек выдал и отказал; у «upgraded» запись от API 1 — для API 2 не в счёт
            (cfg / "glide-shell" / "permissions.json").write_text(json.dumps({"version": 1, "plugins": {
                "new": {"api": 2, "granted": ["network", "windows"], "denied": ["exec"]},
                "old": {"api": 1, "granted": ["network"], "denied": ["exec"]},
                "upgraded": {"api": 1, "granted": PERMISSIONS_V2, "denied": []},
            }}))
            every, _ = discover(cfg, tmp)
            self.assertEqual(every["new"]["granted"], ["network"])                # windows не просил — не в счёт
            self.assertEqual(every["old"]["granted"], ["network"])
            self.assertEqual(every["upgraded"]["granted"], [])
            # поле trusted в своём plugin.json ничего не даёт
            d = cfg / "glide-shell" / "plugins" / "liar"
            d.mkdir()
            (d / "plugin.json").write_text(json.dumps({"id": "liar", "name": "liar", "api": 2, "trusted": True,
                                                       "permissions": ["exec"]}))
            every, loaded = discover(cfg, tmp)
            self.assertEqual(every["liar"]["granted"], [])
            self.assertIs(loaded["liar"]["trusted"], False)

    def test_files_tool(self):
        tool = [sys.executable, "-I", str(ROOT / "tools/qp-files.py")]
        with tempfile.TemporaryDirectory() as tmp:
            d = str(Path(tmp) / "data" / "demo")
            run = lambda *a, stdin="": subprocess.run(tool + list(a), input=stdin, capture_output=True, text=True, timeout=30)
            self.assertEqual(run("read", d, "notes.txt").returncode, 1)               # нет файла
            self.assertEqual(run("write", d, "notes.txt", stdin=json.dumps("строка\n")).returncode, 0)
            self.assertEqual(run("write", d, "empty.txt", stdin=json.dumps("")).returncode, 0)
            self.assertEqual(run("read", d, "notes.txt").stdout, "строка\n")
            self.assertEqual(run("read", d, "empty.txt").stdout, "")
            names = [f["name"] for f in json.loads(run("list", d).stdout)]
            self.assertEqual(names, ["empty.txt", "notes.txt"])
            for bad in ("../x", "a/b", ".hidden", "..", "", "x.tmp"):
                self.assertNotEqual(run("write", d, bad, stdin='"x"').returncode, 0, bad)
            self.assertFalse((Path(tmp) / "data" / "x").exists())
            self.assertEqual(run("remove", d, "notes.txt").returncode, 0)
            self.assertEqual([f["name"] for f in json.loads(run("list", d).stdout)], ["empty.txt"])


if __name__ == "__main__":
    unittest.main()


def function_body(qml_text, name):
    """Тело функции name (до парной скобки)."""
    m = re.search(r"function\s+" + name + r"\s*\([^)]*\)\s*\{", qml_text)
    if not m:
        return ""
    depth, i = 1, m.end()
    while depth and i < len(qml_text):
        depth += {"{": 1, "}": -1}.get(qml_text[i], 0)
        i += 1
    return qml_text[m.end():i]


class NoBypass(unittest.TestCase):
    """Через сам api — без разрешений — нельзя запустить программу или прочитать чужое (v2.2: такие обходы были)."""
    qml = (ROOT / "ApiScope.qml").read_text()

    def test_launch_app_only_real_entries(self):
        body = function_body(self.qml, "launchApp")
        self.assertIn("DesktopEntries.byId", body, "launchApp должен искать приложение по id")
        self.assertNotIn("launchApp(entry)", body, "переданный объект (с полем command) — прямо в запуск")

    def test_niri_without_spawn(self):
        self.assertNotRegex(self.qml, r"property var niri:[^\n]*\?\s*Niri\s*:", "api.niri — сам Niri (action со spawn)")
        for a in ("spawn", "spawn-sh", "quit"):
            self.assertIn('"' + a + '"', re.search(r"niriBlocked: \[(.*?)\]", self.qml).group(1))

    def test_handoff_only_own(self):
        self.assertRegex(self.qml, r"property var handoff:[^\n]*\.to === me")
        self.assertIn("takeHandoff(me)", function_body(self.qml, "takeHandoff"))

    def test_open_url_schemes(self):
        body = function_body(self.qml, "openUrl")
        self.assertIn("https?:", body)
        self.assertIn('need("exec"', body)

    def test_notification_history_not_in_argv(self):
        """История уведомлений — через stdin: аргумент команды больше 128 КБ ядро не пропускает."""
        notifs = (ROOT / "Notifs.qml").read_text()
        self.assertNotIn('printf %s "$2"', notifs)
        self.assertIn("cat >", notifs)
        self.assertNotRegex(notifs, r"function\s+write\s*\(", "своя write() у Process перекрывает запись в stdin")


class Audit(unittest.TestCase):
    """Подсказка «код обходит разрешения»: ловит обращения мимо api к внутренностям оболочки."""

    def test_patterns(self):
        sys.path.insert(0, str(ROOT / "tools"))
        from qp_audit import audit
        cases = {
            "import Quickshell.Io\nItem { Process { } }": {"Quickshell.Io", "Process"},
            "Item { Component.onCompleted: Permissions.register(x) }": {"Permissions"},
            "Item { ApiScope { } }": {"ApiScope"},
            "Item { Component.onCompleted: Core.root.runRaw([]) }": {"Core.root"},
            "Item { Component.onCompleted: Prefs.set('pluginLock', false) }": {"Prefs"},
            "Item { Component.onCompleted: Notifs.clear() }": {"внутренние объекты"},
            "Item { property int n: Prefs.ms(200) }": set(),               # стабильное — не ловить
            "Item { Text { color: Theme.text } }": set(),
        }
        for code, want in cases.items():
            with tempfile.TemporaryDirectory() as tmp:
                (Path(tmp) / "Main.qml").write_text(code)
                self.assertEqual(set(audit(Path(tmp))), want, code)
