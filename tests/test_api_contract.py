"""Контракт API версии 1 (docs/API.md): всё, что обещано плагинам, виджетам и другим программам, должно оставаться.

Добавлять новое можно; убрать или переименовать что-то из списков ниже — несовместимое изменение (нужна версия 2,
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
STORAGE_V1 = {"get", "set", "remove", "all"}
ACTIVITY_V1 = {"start", "update", "end"}
THEME_V1 = {"background", "surface", "surfaceLow", "surfaceHigh", "surfaceHigher", "surfacePressed", "outline",
            "outlineHover", "divider", "text", "textVariant", "textSecondary", "textMuted", "textFaint", "accent",
            "accentSoft", "accentHover", "accentLight", "accentPressed", "accentText", "error", "errorContainer",
            "errorHover", "errorText", "success", "warning", "isLight", "r", "fs", "radiusSm", "radiusMd", "radiusLg",
            "radiusXl", "disabledOpacity"}
DBUS_METHODS_V1 = {"Flash", "StartActivity", "UpdateActivity", "EndActivity", "OpenPanel", "ClosePanel", "Search",
                   "SetDnd", "GetDnd", "GetTheme", "GetVersion"}
DBUS_SIGNALS_V1 = {"ThemeChanged", "ActivityClicked", "ActivityAction", "ActivityClosed"}
MANIFEST_V1 = {"id", "api", "name", "icon", "category", "priority", "keywords", "qml", "bar", "service", "settings",
               "items", "contextActions", "daemon", "wide", "handoff", "output", "confirm", "close"}


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
        missing = API_V1 - members(qml)
        self.assertFalse(missing, f"из api пропало: {sorted(missing)}")
        self.assertFalse(STORAGE_V1 - members(block(qml, "storage")), "api.storage неполный")
        self.assertFalse(ACTIVITY_V1 - members(block(qml, "activity")), "api.activity неполный")
        self.assertIn("readonly property int version: 1", qml)

    def test_theme_tokens(self):
        missing = THEME_V1 - members((ROOT / "Theme.qml").read_text())
        self.assertFalse(missing, f"из Theme пропало: {sorted(missing)}")

    def test_dbus_interface(self):
        src = (ROOT / "tools/glide-shell.py").read_text()
        self.assertIn('"org.glide.Shell1"', src)   # имя интерфейса с версией: несовместимое — только в Shell2
        self.assertFalse(DBUS_METHODS_V1 - set(re.findall(r'<method name="(\w+)"', src)), "пропал метод D-Bus")
        self.assertFalse(DBUS_SIGNALS_V1 - set(re.findall(r'<signal name="(\w+)"', src)), "пропал сигнал D-Bus")

    def test_manifest_fields_documented(self):
        for doc in ("docs/API.md", "docs/API.ru.md"):
            text = (ROOT / doc).read_text()
            for field in MANIFEST_V1:
                self.assertIn(f"`{field}`", text, f"{doc}: нет поля {field}")
            signals = {"opened", "closed", "themeUpdated", "notification"}   # описаны обработчиками: onOpened…
            for name in API_V1 - {"k", "tint", "sub", "cpu", "mem", "now", "notifs", "handoff"}:
                shown = ("on" + name[0].upper() + name[1:]) if name in signals else name
                self.assertTrue(shown in text, f"{doc}: не описано api.{shown}")

    def test_manifest_api_version(self):
        """Нет поля api — версия 1; новее, чем знает оболочка, или не число — плагин не грузится, причина — в списке."""
        with tempfile.TemporaryDirectory() as tmp:
            cfg = Path(tmp) / "cfg"
            for pid, api in (("noapi", None), ("v1", 1), ("v2", 2), ("bad", "1")):
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
            self.assertTrue({"noapi", "v1"} <= loaded)
            self.assertFalse({"v2", "bad"} & loaded)
            problems = {p["id"]: p.get("problem", "") for p in out["allPlugins"]}
            self.assertIn("API 2", problems["v2"])
            self.assertTrue(problems["bad"])


if __name__ == "__main__":
    unittest.main()
