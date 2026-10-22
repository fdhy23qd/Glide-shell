#!/usr/bin/env python3
"""Тесты помощников Glide Shell (Python) и словаря перевода. Только стандартная библиотека:

    python3 -m unittest discover -s tests -v        (из корня проекта)

Каждый тест — в своих временных XDG_CONFIG_HOME / XDG_STATE_HOME / XDG_CACHE_HOME: настоящие данные не трогаются.
Сеть не нужна: расписание разбирается из сохранённой страницы (tests/fixtures). Живую проверку сайта СыктГУ
(не поменялась ли вёрстка) делает tests/check_schedule_site.py.
"""
import glob
import importlib.util
import json
import os
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TOOLS = ROOT / "tools"


def load_module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


class Sandbox(unittest.TestCase):
    """Временные XDG-папки и PATH с заглушками (notify-send, wl-copy, wl-paste)."""

    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix="glide-test-"))
        self.cfg, self.state, self.cache, self.bin = (self.tmp / d for d in ("config", "state", "cache", "bin"))
        for d in (self.cfg, self.state, self.cache, self.bin):
            d.mkdir()
        self.shim("notify-send", "#!/bin/sh\nexit 0\n")
        self.shim("wl-copy", "#!/bin/sh\ncat >/dev/null 2>&1; exit 0\n")
        self.env = dict(os.environ, XDG_CONFIG_HOME=str(self.cfg), XDG_STATE_HOME=str(self.state),
                        XDG_CACHE_HOME=str(self.cache), PATH=f"{self.bin}:{os.environ['PATH']}")

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def shim(self, name, body):
        p = self.bin / name
        p.write_text(body)
        p.chmod(0o755)

    def run_py(self, script, *args, env=None, input=None, timeout=20):
        # stdin закрыт, если не задан: иначе подпроцесс, читающий stdin, ждал бы унаследованный (install.sh)
        return subprocess.run([sys.executable, "-I", str(script), *args], env={**self.env, **(env or {})},
                              input=input if input is not None else "", capture_output=True, text=True, timeout=timeout)


# ---------------------------------------------------------------- калькулятор
class Calc(Sandbox):
    script = ROOT / "plugins/calc/calc.py"

    def ev(self, expr):
        return self.run_py(self.script, "eval", env={"QP_TEXT": expr})

    def test_arithmetic(self):
        for expr, want in [("2+2*2", "6"), ("2^10", "1024"), ("(1+2)*3", "9"), ("7/2", "3.5"),
                           ("sqrt(16)", "4"), ("10 % 3", "1"), ("2×3÷4", "1.5"), ("-3+1", "-2")]:
            with self.subTest(expr=expr):
                r = self.ev(expr)
                self.assertEqual(r.returncode, 0, r.stderr)
                self.assertEqual(r.stdout.strip(), want)

    def test_rejects_code_and_huge_powers(self):
        for expr in ["__import__('os').system('true')", "open('/etc/passwd')", "2**99999", "x+1", "1/0"]:
            with self.subTest(expr=expr):
                self.assertNotEqual(self.ev(expr).returncode, 0)

    def test_history(self):
        self.ev("1+1"); self.ev("2+2"); self.ev("1+1")
        lines = self.run_py(self.script, "list").stdout.strip().splitlines()
        self.assertEqual([l.split("\t")[0] for l in lines], ["2", "4"])   # повтор — наверх, без дублей


# ---------------------------------------------------------------- история буфера
class Clipboard(Sandbox):
    script = ROOT / "plugins/clipboard/clip.py"

    def offer(self, text, types="text/plain;charset=utf-8"):
        """wl-paste-заглушка: --list-types → types, иначе — text."""
        (self.tmp / "clip.txt").write_text(text)
        self.shim("wl-paste", f"""#!/bin/sh
case "$*" in *--list-types*) printf '%s\\n' {' '.join(repr(t) for t in types.split())};; *) cat "{self.tmp}/clip.txt";; esac
""")
        return self.run_py(self.script, "store", input="")

    def items(self):
        return [l.split("\t")[1] for l in self.run_py(self.script, "list").stdout.splitlines()]

    def test_store_and_order(self):
        self.offer("первое"); self.offer("второе"); self.offer("первое")
        self.assertEqual(self.items(), ["первое", "второе"])   # повтор — наверх, без дубля

    def test_skips_passwords_and_blank(self):
        self.offer("секрет", "text/plain x-kde-passwordManagerHint")
        self.offer("   ")
        self.assertEqual(self.items(), [])

    def test_private_and_clear(self):
        self.offer("заметка")
        f = self.state / "glide-shell" / "clipboard.json"
        self.assertTrue(f.exists())
        self.assertEqual(stat.S_IMODE(f.stat().st_mode) & 0o077, 0, "история буфера должна быть 0600")
        self.run_py(self.script, "clear")
        self.assertEqual(self.items(), [])

    def test_pins_survive_clear(self):
        self.offer("важное"); self.offer("мусор")
        rows = json.loads(self.run_py(self.script, "json").stdout)
        pid = next(r["id"] for r in rows if r.get("text") == "важное")
        self.run_py(self.script, "pin", pid)
        rows = json.loads(self.run_py(self.script, "json").stdout)
        self.assertEqual([(r["text"], r["pinned"]) for r in rows], [("важное", True), ("мусор", False)])
        self.run_py(self.script, "clear")
        rows = json.loads(self.run_py(self.script, "json").stdout)
        self.assertEqual([(r["text"], r["pinned"]) for r in rows], [("важное", True)])   # закреплённое осталось
        pins = self.state / "glide-shell" / "clipboard-pins.json"
        self.assertEqual(stat.S_IMODE(pins.stat().st_mode) & 0o077, 0)
        self.run_py(self.script, "unpin", pid)
        rows = json.loads(self.run_py(self.script, "json").stdout)
        self.assertEqual([(r["text"], r["pinned"]) for r in rows], [("важное", False)])   # вернулось в историю


# ---------------------------------------------------------------- настройки
class Config(Sandbox):
    script = TOOLS / "qp-config.py"

    def conf(self):
        return json.loads((self.cfg / "glide-shell" / "config.json").read_text())

    def test_set_keeps_other_keys(self):
        self.run_py(self.script, "set", "panel.width", "440")
        self.run_py(self.script, "set", "panel.accent", '"#ff8800"')
        self.assertEqual(self.conf()["panel"], {"width": 440, "accent": "#ff8800"})

    def test_toggle_disabled(self):
        self.run_py(self.script, "toggle-disabled", "weather")
        self.assertIn("weather", self.conf().get("disabled", []))
        self.run_py(self.script, "toggle-disabled", "weather")
        self.assertNotIn("weather", self.conf().get("disabled", []))

    def test_reset_panel(self):
        self.run_py(self.script, "set", "panel.width", "500")
        self.run_py(self.script, "reset-panel")
        self.assertFalse(self.conf().get("panel"))

    def test_corrupted_config_is_not_overwritten(self):
        p = self.cfg / "glide-shell" / "config.json"
        p.parent.mkdir(parents=True)
        p.write_text("{битый json")
        r = self.run_py(self.script, "set", "panel.width", "440")
        self.assertNotEqual(r.returncode, 0)
        self.assertEqual(p.read_text(), "{битый json")


# ---------------------------------------------------------------- плагины
class Discover(Sandbox):
    script = TOOLS / "qp-discover.py"

    def test_every_plugin_json_is_valid(self):
        for f in glob.glob(str(ROOT / "plugins/*/plugin.json")):
            with self.subTest(plugin=Path(f).parent.name):
                d = json.loads(Path(f).read_text())
                for key in ("id", "name", "category"):
                    self.assertIn(key, d)
                self.assertEqual(d["id"], Path(f).parent.name)
                if d.get("qml"):
                    self.assertTrue((Path(f).parent / d["qml"]).exists(), f"нет {d['qml']}")

    def test_discover_and_disabled(self):
        (self.cfg / "glide-shell").mkdir(parents=True)
        (self.cfg / "glide-shell" / "config.json").write_text(json.dumps({"disabled": ["weather"], "panel": {"width": 400}}))
        r = self.run_py(self.script)
        self.assertEqual(r.returncode, 0, r.stderr)
        d = json.loads(r.stdout)
        ids = {p["id"] for p in d["plugins"]}
        self.assertIn("calc", ids)
        self.assertNotIn("weather", ids)
        self.assertEqual(d["panel"]["width"], 400)
        self.assertTrue(d["categories"])
        cats = {c["id"] for c in d["categories"]}
        for p in d["plugins"]:   # у каждого плагина — существующая категория
            self.assertTrue(set(p["categories"]) & cats, p["id"])


# ---------------------------------------------------------------- расписание СыктГУ
class Schedule(unittest.TestCase):
    mod = load_module("glide_schedule", TOOLS / "glide-schedule.py")

    def test_parse_saved_page(self):
        page = (ROOT / "tests/fixtures/schedule-group.html").read_text()
        d = self.mod.parse(page)
        self.assertRegex(d["from"], r"^\d\d\.\d\d\.\d{4}$")
        self.assertRegex(d["to"], r"^\d\d\.\d\d\.\d{4}$")
        self.assertTrue(d["curr"], "нет кнопки «след. неделя» (curr)")
        self.assertGreaterEqual(len(d["days"]), 5)
        lessons = [l for day in d["days"] for l in day["lessons"]]
        self.assertGreater(len(lessons), 5)
        for l in lessons:
            with self.subTest(lesson=l.get("title")):
                self.assertTrue(l["title"])
                self.assertIn(l["subgroup"], (0, 1, 2))
                h, m = map(int, l["start"].split(":"))
                eh, em = map(int, l["end"].split(":"))
                self.assertEqual((eh * 60 + em) - (h * 60 + m), 90)   # пара — 90 минут
                self.assertTrue(1 <= l["n"] <= 8)

    def test_empty_page(self):
        d = self.mod.parse("<html>нет такой группы</html>")
        self.assertEqual(d["days"], [])


# ---------------------------------------------------------------- обои и виджеты
class Walls(Sandbox):
    script = TOOLS / "glide-walls.py"

    def test_palette_and_list(self):
        try:
            from PIL import Image
        except ImportError:
            self.skipTest("нет Pillow")
        d = self.tmp / "walls"
        d.mkdir()
        Image.new("RGB", (320, 180), (230, 120, 30)).save(d / "orange.jpg")
        Image.new("RGB", (320, 180), (128, 128, 128)).save(d / "gray.png")
        (d / "notes.txt").write_text("не картинка")
        r = json.loads(self.run_py(self.script, "palette", str(d / "orange.jpg")).stdout)
        h = int(r["accent"][1:3], 16), int(r["accent"][3:5], 16), int(r["accent"][5:7], 16)
        self.assertGreater(h[0], h[2])                          # оранжевый: красного больше синего
        self.assertIsNone(json.loads(self.run_py(self.script, "palette", str(d / "gray.png")).stdout)["accent"])
        items = json.loads(self.run_py(self.script, "list", str(d)).stdout)
        self.assertEqual([i["name"] for i in items], ["gray", "orange"])
        self.assertTrue(all(Path(i["thumb"]).exists() for i in items))


class Widgets(Sandbox):
    script = TOOLS / "glide-widgets.py"

    def test_example_widget(self):
        dst = self.cfg / "glide-shell" / "widgets"
        shutil.copytree(ROOT / "examples/widgets", dst)
        (dst / "broken").mkdir()
        (dst / "broken" / "widget.qml").write_text("Item {}")
        (dst / "broken" / "widget.json").write_text("{не json")
        items = {i["id"]: i for i in json.loads(self.run_py(self.script).stdout)}
        self.assertEqual(items["countdown"]["name"], "Обратный отсчёт")
        self.assertTrue(items["countdown"]["settings"])
        self.assertIn("error", items["broken"])   # битый widget.json — в списке, с ошибкой


# ---------------------------------------------------------------- перевод
class Files(Sandbox):
    """Индекс и поиск файлов: скрытое и node_modules не попадают, все слова — в имени, совпадение с начала — выше."""

    def test_index_and_search(self):
        root = self.tmp / "home"
        for rel in ("Документы/Отчёт за год.pdf", "Документы/отчёт черновик.txt", "Видео/отпуск.mp4",
                    ".secret/отчёт.txt", "proj/node_modules/отчёт.js", "proj/src/main.py"):
            f = root / rel
            f.parent.mkdir(parents=True, exist_ok=True)
            f.write_text("x")
        env = dict(os.environ, GLIDE_FILES_ROOT=str(root), XDG_CACHE_HOME=str(self.cache))
        out = subprocess.run([sys.executable, "-I", str(TOOLS / "glide-files.py"), "search", "отчёт"],
                             env=env, capture_output=True, text=True, stdin=subprocess.DEVNULL, timeout=30)
        items = json.loads(out.stdout)
        names = [i["name"] for i in items]
        self.assertEqual(set(names), {"Отчёт за год.pdf", "отчёт черновик.txt"})   # без .secret и node_modules
        out = subprocess.run([sys.executable, "-I", str(TOOLS / "glide-files.py"), "search", "год", "отч"],
                             env=env, capture_output=True, text=True, stdin=subprocess.DEVNULL, timeout=30)
        self.assertEqual([i["name"] for i in json.loads(out.stdout)], ["Отчёт за год.pdf"])
        idx = self.cache / "glide-shell" / "files.tsv"
        self.assertEqual(stat.S_IMODE(idx.stat().st_mode), 0o600)


class NiriSettings(Sandbox):
    """Перенос input в glide-settings.kdl: флаги выключаются, неизвестное — дословно, config.kdl — с пометкой."""

    def test_migrate_and_edit(self):
        if not shutil.which("niri"):
            self.skipTest("нет niri")
        d = self.tmp / "niri"
        d.mkdir()
        (d / "config.kdl").write_text(
            'input {\n    keyboard {\n        xkb {\n            layout "us,ru"\n        }\n        numlock\n    }\n'
            '    touchpad {\n        tap\n        natural-scroll\n    }\n    warp-mouse-to-focus\n}\n\n'
            'binds {\n    Mod+T hotkey-overlay-title="Терминал" { spawn "alacritty"; }\n    Mod+O hotkey-overlay-title=null { toggle-overview; }\n}\n')
        env = dict(os.environ, GLIDE_NIRI_DIR=str(d))
        run = lambda *a: json.loads(subprocess.run([sys.executable, "-I", str(TOOLS / "glide-niri.py"), *a], env=env,
                                                   capture_output=True, text=True, stdin=subprocess.DEVNULL, timeout=30).stdout)
        r = run("read")
        self.assertFalse(r["managed"])
        self.assertEqual(r["input"]["keyboard"]["layout"], "us,ru")
        self.assertTrue(r["input"]["touchpad"]["tap"])
        self.assertEqual(r["binds"][0]["title"], "Терминал")
        self.assertEqual(r["binds"][1]["title"], "")                 # null — скрыта из подсказки, не строка «null»
        # клавиши: смена сочетания (старое в config.kdl закомментировано), новая, удаление, ошибка — откат
        self.assertTrue(run("bind", json.dumps({"key": "Mod+Return", "argv": ["spawn", "alacritty"], "title": "Терминал", "old": "Mod+T"}))["ok"])
        self.assertIn("// [glide-shell] ", (d / "config.kdl").read_text())
        self.assertTrue(run("bind", json.dumps({"key": "Mod+Shift+F", "argv": ["fullscreen-window"]}))["ok"])
        keys = {b["key"] for b in run("read")["binds"]}
        self.assertTrue({"Mod+Return", "Mod+Shift+F"} <= keys)
        self.assertNotIn("Mod+T", keys)
        self.assertTrue(run("bind", json.dumps({"delete": "Mod+Shift+F"}))["ok"])
        self.assertNotIn("Mod+Shift+F", {b["key"] for b in run("read")["binds"]})
        before = (d / "glide-settings.kdl").read_text()
        self.assertFalse(run("bind", json.dumps({"key": "Mod+Z", "argv": ["нет-такого-действия"]}))["ok"])
        self.assertEqual((d / "glide-settings.kdl").read_text(), before)
        self.assertTrue(run("set-input", json.dumps({"touchpad": {"tap": False}, "keyboard": {"repeat_rate": 40}}))["ok"])
        r = run("read")
        self.assertTrue(r["managed"])
        self.assertFalse(r["input"]["touchpad"]["tap"])
        self.assertTrue(r["input"]["touchpad"]["natural_scroll"])
        self.assertEqual(r["input"]["keyboard"]["repeat_rate"], 40)
        self.assertTrue(r["input"]["warp_mouse_to_focus"])          # неизвестное панели — перенесено
        conf = (d / "config.kdl").read_text()
        self.assertIn('include "glide-settings.kdl"', conf)
        self.assertIn("// [glide-shell] input {", conf)
        self.assertTrue(list(d.glob("config.kdl.before-glide-*")))
        # внешний вид: зазоры, рамка, угол — в glide-settings.kdl, и обратно
        self.assertTrue(run("set-look", json.dumps({"gaps": 10, "ring": {"on": True, "width": 3, "color": "#7b61ff"}, "hotcorner": False}))["ok"])
        lk = run("read")["look"]
        self.assertEqual((lk["gaps"], lk["ring"]["on"], lk["ring"]["width"], lk["hotcorner"]), (10, True, 3, False))
        self.assertTrue(run("set-look", json.dumps({"hotcorner": True, "ring": {"on": False}}))["ok"])
        lk = run("read")["look"]
        self.assertEqual((lk["ring"]["on"], lk["hotcorner"]), (False, True))
        # мониторы: положение, VRR, выключенный — в glide-outputs.kdl, подключённый первым
        self.assertTrue(run("save-outputs", json.dumps([{"name": "eDP-1", "mode": "1366x768@60.000", "scale": 1, "x": 0, "y": 0, "vrr": True},
                                                        {"name": "HDMI-A-1", "off": True}]))["ok"])
        out = (d / "glide-outputs.kdl").read_text()
        self.assertIn("variable-refresh-rate", out)
        self.assertIn("position x=0 y=0", out)
        self.assertRegex(out, r'output "HDMI-A-1" \{\s*off\s*\}')
        self.assertTrue((d / "config.kdl").read_text().startswith("// Glide Shell: мониторы"))
        # ошибка niri → откат обоих файлов
        before = (d / "glide-settings.kdl").read_text()
        self.assertFalse(run("set-input", json.dumps({"keyboard": {"repeat_rate": "много"}}))["ok"])
        self.assertEqual((d / "glide-settings.kdl").read_text(), before)


class Backup(Sandbox):
    """Копия настроек: config.json и свои плагины — да, ключ — нет; восстановление сначала сохраняет текущее."""

    def test_export_import(self):
        home = self.tmp / "home"; home.mkdir()
        sh = self.cfg / "glide-shell"; sh.mkdir(parents=True, exist_ok=True)
        (sh / "config.json").write_text('{"panel": {"accent": "#123456"}}')
        (sh / "anthropic-key").write_text("секрет")
        (sh / "plugins" / "мой").mkdir(parents=True); (sh / "plugins" / "мой" / "plugin.json").write_text("{}")
        env = {"HOME": str(home)}
        path = self.run_py(TOOLS / "glide-backup.py", "export", env=env).stdout.strip()
        import tarfile
        names = tarfile.open(path).getnames()
        self.assertIn("glide-shell/config.json", names)
        self.assertIn("glide-shell/plugins/мой/plugin.json", names)
        self.assertNotIn("glide-shell/anthropic-key", names)
        (sh / "config.json").write_text('{"panel": {"accent": "#ffffff"}}')
        r = json.loads(self.run_py(TOOLS / "glide-backup.py", "import", path, env=env).stdout)
        self.assertTrue(r["ok"])
        self.assertIn("#123456", (sh / "config.json").read_text())
        self.assertTrue(list(home.glob("*-before-import.tar.gz")))


class Autostart(Sandbox):
    """XDG-автозапуск: системное выключается своей копией с Hidden=true, своё — добавляется и удаляется."""

    def test_toggle_add_remove(self):
        sysd = self.tmp / "xdg" / "autostart"; sysd.mkdir(parents=True)
        (sysd / "sys.desktop").write_text("[Desktop Entry]\nType=Application\nName=Системное\nExec=true\n")
        (sysd / "gnome.desktop").write_text("[Desktop Entry]\nType=Application\nName=Только GNOME\nExec=true\nOnlyShowIn=GNOME;\n")
        apps = self.tmp / "data" / "applications"; apps.mkdir(parents=True)
        (apps / "app.desktop").write_text("[Desktop Entry]\nType=Application\nName=Приложение\nExec=app\n")
        env = {"XDG_CONFIG_DIRS": str(self.tmp / "xdg"), "XDG_DATA_DIRS": str(self.tmp / "data"), "XDG_CURRENT_DESKTOP": "niri"}
        ls = lambda: {e["file"]: e for e in json.loads(self.run_py(TOOLS / "glide-autostart.py", "list", env=env).stdout)}
        self.assertEqual(set(ls()), {"sys.desktop"})                    # только для GNOME — не показано
        self.run_py(TOOLS / "glide-autostart.py", "set", "sys.desktop", "off", env=env)
        self.assertFalse(ls()["sys.desktop"]["enabled"])
        self.assertTrue((sysd / "sys.desktop").read_text().count("Hidden") == 0)   # системный файл не тронут
        self.run_py(TOOLS / "glide-autostart.py", "set", "sys.desktop", "on", env=env)
        self.assertTrue(ls()["sys.desktop"]["enabled"])
        self.run_py(TOOLS / "glide-autostart.py", "add", "app.desktop", env=env)
        self.assertTrue(ls()["app.desktop"]["mine"])
        self.run_py(TOOLS / "glide-autostart.py", "remove", "app.desktop", env=env)
        self.assertNotIn("app.desktop", ls())


class Holidays(unittest.TestCase):
    """Разбор строки isdayoff и встроенный список — без сети."""

    def setUp(self):
        self.h = load_module("glide_holidays", TOOLS / "glide-holidays.py")

    def test_parse_marks_only_differences(self):
        import datetime as dt
        year = 2026
        n = (dt.date(year + 1, 1, 1) - dt.date(year, 1, 1)).days
        codes = ["1" if (dt.date(year, 1, 1) + dt.timedelta(i)).weekday() >= 5 else "0" for i in range(n)]
        codes[dt.date(year, 1, 9).timetuple().tm_yday - 1] = "1"     # пятница — перенос
        codes[dt.date(year, 11, 3).timetuple().tm_yday - 1] = "2"    # сокращённый
        codes[dt.date(year, 2, 28).timetuple().tm_yday - 1] = "0"    # рабочая суббота
        days = self.h.parse(year, "".join(codes))
        self.assertEqual(days["01-09"], {"t": "off"})
        self.assertEqual(days["11-03"], {"t": "short"})
        self.assertEqual(days["02-28"], {"t": "work"})
        self.assertEqual(days["11-04"], {"name": "День народного единства"})   # в этой строке рабочий — без "t"
        self.assertNotIn("01-10", days)                                        # обычная суббота

    def test_parse_rejects_garbage(self):
        with self.assertRaises(ValueError):
            self.h.parse(2030, "101")

    def test_builtin(self):
        days = self.h.builtin(2026)
        self.assertEqual(days["11-04"]["t"], "off")         # среда
        self.assertNotIn("t", days["03-08"])                # воскресенье — и так выходной
        self.assertEqual(len(days), 14)


class Translation(unittest.TestCase):
    def test_every_tr_string_has_english(self):
        en = json.loads((ROOT / "i18n/en.json").read_text())
        missing = set()
        for f in glob.glob(str(ROOT / "*.qml")) + glob.glob(str(ROOT / "plugins/*/*.qml")):
            if Path(f).name == "Tr.qml":
                continue
            for m in re.finditer(r'Tr\.t\("((?:[^"\\]|\\.)*)"\)', Path(f).read_text()):
                s = json.loads('"' + m.group(1) + '"')
                if s not in en:
                    missing.add(f"{Path(f).name}: {s}")
        self.assertFalse(missing, "нет перевода в i18n/en.json:\n" + "\n".join(sorted(missing)))

    def test_no_bare_russian_in_qml(self):
        """Видимый русский текст без Tr.t — забыли обернуть (пути, комментарии и логи не в счёт)."""
        bare = []
        for f in glob.glob(str(ROOT / "*.qml")) + glob.glob(str(ROOT / "plugins/*/*.qml")):
            if Path(f).name in ("Tr.qml", "Prefs.qml", "Theme.qml", "Niri.qml", "Wallpaper.qml", "Spring.qml",
                                "Stagger.qml", "OutputProcess.qml"):
                continue
            for n, line in enumerate(Path(f).read_text().splitlines(), 1):
                code = line.split("//")[0] if not line.strip().startswith("//") else ""
                if "console." in code or "без перевода" in line:   # «// без перевода» — так задумано
                    continue
                for m in re.finditer(r'(?<!Tr\.t\()"([^"\\]*[А-Яа-яЁё][^"\\]*)"', code):
                    if not m.group(1).startswith(("~", "/")):
                        bare.append(f"{Path(f).name}:{n}: {m.group(1)}")
        self.assertFalse(bare, "русский текст без Tr.t:\n" + "\n".join(bare[:30]))


if __name__ == "__main__":
    unittest.main()
