#!/usr/bin/env python3
"""Тесты помощников Glide Shell (Python) и словаря перевода. Только стандартная библиотека:

    python3 -m unittest discover -s tests -v        (из корня проекта)

Каждый тест — в своих временных XDG_CONFIG_HOME / XDG_STATE_HOME / XDG_CACHE_HOME: настоящие данные не трогаются.
Сеть не нужна.
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
import zipfile
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


class PluginArchive(Sandbox):
    """Установка плагина из архива (tools/glide-plugin.py): ничего не пишет мимо своей папки, не ставит чужое."""
    TOOL = TOOLS / "glide-plugin.py"
    GOOD = {"water/plugin.json": json.dumps({"id": "water2", "name": "Вода", "api": 2, "permissions": ["network"], "qml": "Main.qml"}),
            "water/Main.qml": "import QtQuick\nItem {}\n"}

    def zip(self, files, links=()):
        p = self.tmp / "p.zip"
        with zipfile.ZipFile(p, "w") as z:
            for n, t in files.items():
                z.writestr(n, t)
            for n, target in links:                     # символическая ссылка внутри zip
                i = zipfile.ZipInfo(n)
                i.external_attr = (0o120777 << 16)
                z.writestr(i, target)
        return p

    def call(self, *args):
        r = self.run_py(self.TOOL, *map(str, args))
        return json.loads(r.stdout)

    def test_install_and_replace(self):
        r = self.call("install", self.zip(self.GOOD))
        self.assertTrue(r["ok"], r)
        self.assertEqual(r["permissions"], ["network"])
        self.assertTrue((self.cfg / "glide-shell/plugins/water2/Main.qml").is_file())
        self.assertFalse(self.call("install", self.zip(self.GOOD))["ok"])            # уже есть — только с --replace
        self.assertTrue(self.call("install", self.zip(self.GOOD), "--replace")["ok"])
        self.assertEqual(len(list((self.state / "glide-shell/plugin-backups").iterdir())), 1)

    def test_rejects_bad(self):
        cases = {
            "путь наружу": self.zip(dict(self.GOOD, **{"../evil.txt": "x"})),
            "ссылка": self.zip(self.GOOD, links=[("water/link", "/etc/passwd")]),
            "встроенный id": self.zip({"plugin.json": json.dumps({"id": "clipboard", "name": "x"})}),
            "нет plugin.json": self.zip({"a/Main.qml": "x"}),
            "плохой id": self.zip({"plugin.json": json.dumps({"id": "../x", "name": "x"})}),
        }
        for why, path in cases.items():
            with self.subTest(why):
                self.assertFalse(self.call("install", path)["ok"])
        self.assertFalse((self.tmp / "evil.txt").exists())
        left = list((self.cfg / "glide-shell/plugins").iterdir()) if (self.cfg / "glide-shell/plugins").exists() else []
        self.assertEqual(left, [])                       # ни плагина, ни временной папки

    def test_pack_roundtrip(self):
        src = self.tmp / "src"
        src.mkdir()
        (src / "plugin.json").write_text(self.GOOD["water/plugin.json"])
        (src / "Main.qml").write_text("Item {}")
        (src / ".git").mkdir()
        (src / ".git/config").write_text("secret")
        r = self.run_py(self.TOOL, "pack", str(src), str(self.tmp / "w.glideplugin"))
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        names = zipfile.ZipFile(self.tmp / "w.glideplugin").namelist()
        self.assertIn("water2/Main.qml", names)
        self.assertFalse([n for n in names if ".git" in n])   # скрытое не упаковывается
        self.assertTrue(self.call("inspect", self.tmp / "w.glideplugin")["ok"])


class WinCast(unittest.TestCase):
    """Запись окна (tools/glide-wincast.py --check): отвечает JSON-ом и называет, чего не хватает (без записи)."""

    def test_check(self):
        r = subprocess.run([sys.executable, "-I", str(TOOLS / "glide-wincast.py"), "--check"], capture_output=True,
                           text=True, stdin=subprocess.DEVNULL, timeout=60)
        d = json.loads(r.stdout)
        self.assertEqual(set(d), {"ok", "video", "audio", "missing"})
        self.assertEqual(d["ok"], not d["missing"])


class Procs(unittest.TestCase):
    """«Процессы» (tools/glide-procs.py): понятные имена помощников и отказ завершать чужое."""

    def setUp(self):
        self.m = load_module("glide_procs", TOOLS / "glide-procs.py")

    def test_names(self):
        n = self.m.name_of
        self.assertEqual(n("wl-paste --watch python3 /x/plugins/clipboard/clip.py store")[0], "История буфера обмена")
        self.assertEqual(n("python3 /home/u/.config/glide-shell/plugins/devhub/d.py"), ("Плагин devhub", "devhub"))
        self.assertEqual(n("/usr/bin/qs -c glide-shell")[0], "Оболочка")
        self.assertEqual(n("/usr/bin/something --flag")[0], "something")

    def test_kill_refuses_foreign(self):
        self.m.cgroup_procs = lambda: [111, 222]
        self.m.main_pid = lambda: (111, 0)
        self.assertFalse(self.m.kill(111)["ok"])          # саму оболочку — нет
        self.assertFalse(self.m.kill(os.getpid())["ok"])  # не из группы службы — нет


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

    def test_odd_names_do_not_break_index(self):
        """Имя с табуляцией или переводом строки ломало TSV-индекс — поиск падал целиком (v2.3)."""
        root = self.tmp / "home"; (root / "d").mkdir(parents=True)
        for n in ("отчёт.txt", "с\tтабом.txt", "плохое\nимя.txt"):
            (root / "d" / n).write_text("x")
        env = dict(os.environ, GLIDE_FILES_ROOT=str(root), XDG_CACHE_HOME=str(self.cache))
        run = lambda *a: subprocess.run([sys.executable, "-I", str(TOOLS / "glide-files.py"), *a], env=env,
                                        capture_output=True, text=True, stdin=subprocess.DEVNULL, timeout=30)
        out = run("search", "отчёт")
        self.assertEqual(out.returncode, 0, out.stderr)
        self.assertEqual([i["name"] for i in json.loads(out.stdout)], ["отчёт.txt"])
        idx = self.cache / "glide-shell" / "files.tsv"   # индекс от прежней версии с битой строкой — тоже не падать
        idx.write_text(idx.read_text() + "\n/x/с\tтабом.txt\t1\tf")
        self.assertEqual(run("search", "отчёт").returncode, 0)


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
                                                        {"name": "HDMI-A-1", "off": True, "mode": "1920x1080@60.000", "x": -1920, "y": 0}]))["ok"])
        out = (d / "glide-outputs.kdl").read_text()
        self.assertIn("variable-refresh-rate", out)
        self.assertIn("position x=0 y=0", out)
        self.assertRegex(out, r'output "HDMI-A-1" \{\s*off\s*mode "1920x1080@60.000"\s*position x=-1920 y=0\s*\}')   # выключен — но помнит место
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

    def test_permissions_restored_for_next_start(self):
        """Разрешения из копии — в permissions.json.import: работающая оболочка вернула бы permissions.json как «правку в обход»."""
        home = self.tmp / "home"; home.mkdir()
        sh = self.cfg / "glide-shell"; sh.mkdir(parents=True, exist_ok=True)
        (sh / "permissions.json").write_text('{"plugins": {"x": {"api": 2, "granted": ["exec"]}}}')
        env = {"HOME": str(home)}
        path = self.run_py(TOOLS / "glide-backup.py", "export", env=env).stdout.strip()
        (sh / "permissions.json").write_text('{"plugins": {}}')
        self.assertTrue(json.loads(self.run_py(TOOLS / "glide-backup.py", "import", path, env=env).stdout)["ok"])
        self.assertEqual((sh / "permissions.json").read_text(), '{"plugins": {}}')   # сам файл не тронут
        imp = sh / "permissions.json.import"
        self.assertIn('"exec"', imp.read_text())
        self.assertEqual(stat.S_IMODE(imp.stat().st_mode), 0o600)
        import tarfile   # и в следующую копию недоеденный .import не попадает
        again = self.run_py(TOOLS / "glide-backup.py", "export", str(self.tmp / "b2"), env=env).stdout.strip()
        self.assertNotIn("glide-shell/permissions.json.import", tarfile.open(again).getnames())

    def test_powertimer_rejects_zero(self):
        """«set 0» выключил бы компьютер сразу — отказ до любых действий."""
        self.shim("systemctl", "#!/bin/sh\necho CALLED >> \"$0.log\"\n")
        self.shim("systemd-run", "#!/bin/sh\necho CALLED >> \"$0.log\"\n")
        r = subprocess.run(["sh", str(TOOLS / "glide-powertimer.sh"), "set", "0", "poweroff"], env=self.env,
                           capture_output=True, text=True, stdin=subprocess.DEVNULL, timeout=10)
        self.assertEqual(r.returncode, 2)
        self.assertFalse((self.bin / "systemd-run.log").exists() or (self.bin / "systemctl.log").exists())


class Drives(unittest.TestCase):
    """Съёмные диски (glide-drives.py): из объектов udisks — только свои съёмные разделы."""

    def test_filter(self):
        m = load_module("glide_drives", TOOLS / "glide-drives.py")
        UD = "org.freedesktop.UDisks2"
        dev = lambda s: list(s.encode()) + [0]
        objs = {
            "/b/sda1": {UD + ".Block": {"HintSystem": True, "IdType": "ext4", "Device": dev("/dev/sda1")}, UD + ".Filesystem": {"MountPoints": [dev("/")]}},
            "/b/sdb1": {UD + ".Block": {"HintSystem": False, "IdLabel": "ФЛЕШКА", "IdType": "vfat", "Size": 8 << 30,
                                        "Device": dev("/dev/sdb1"), "Drive": "/d/usb"},
                        UD + ".Filesystem": {"MountPoints": [dev("/run/media/u/ФЛЕШКА")]}},
            "/d/usb": {UD + ".Drive": {"Vendor": "Kingston ", "Model": "DataTraveler", "Ejectable": False, "CanPowerOff": True}},
            "/b/sdc1": {UD + ".Block": {"HintSystem": False, "IdType": "crypto_LUKS", "Device": dev("/dev/sdc1")}, UD + ".Encrypted": {}},
            "/b/sdd1": {UD + ".Block": {"HintSystem": False, "HintIgnore": True, "IdType": "vfat"}, UD + ".Filesystem": {"MountPoints": []}},
            "/b/loop0": {UD + ".Block": {"HintSystem": True, "IdLabel": "образ", "IdType": "ext4"}, UD + ".Filesystem": {"MountPoints": []},
                         UD + ".Loop": {"SetupByUID": 1000}},
            "/b/loop1": {UD + ".Block": {"HintSystem": True, "IdType": "squashfs"}, UD + ".Filesystem": {"MountPoints": []},
                         UD + ".Loop": {"SetupByUID": 0}},
            "/b/sde": {UD + ".Block": {"HintSystem": False, "IdType": ""}},   # без файловой системы (вся флешка) — не раздел
        }
        out = {d["id"]: d for d in m.drives(objs, uid=1000)}
        self.assertEqual(set(out), {"/b/sdb1", "/b/sdc1", "/b/loop0"})   # без системного, скрытого, чужого образа
        usb = out["/b/sdb1"]
        self.assertEqual((usb["label"], usb["device"], usb["mounted"], usb["mountPoint"]), ("ФЛЕШКА", "/dev/sdb1", True, "/run/media/u/ФЛЕШКА"))
        self.assertEqual((usb["driveName"], usb["canPowerOff"], usb["size"]), ("Kingston DataTraveler", True, 8 << 30))
        self.assertTrue(out["/b/sdc1"]["encrypted"])
        self.assertTrue(out["/b/loop0"]["image"] and not out["/b/sdb1"]["image"])

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


class DocsToc(unittest.TestCase):
    """Оглавление документации свежее, и каждая ссылка-якорь ведёт на существующий заголовок (tools/docs-toc.py)."""

    def test_toc(self):
        r = subprocess.run([sys.executable, "-I", str(TOOLS / "docs-toc.py"), "--check"], capture_output=True, text=True,
                           stdin=subprocess.DEVNULL, timeout=30)
        self.assertEqual(r.returncode, 0, r.stderr)


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


class Update(Sandbox):
    """Обновление из git: видит новую версию и её записи CHANGELOG, не трогает папку со своими правками."""

    def git(self, cwd, *a):
        subprocess.run(["git", "-C", str(cwd), *a], check=True, capture_output=True, stdin=subprocess.DEVNULL,
                       env=dict(self.env, GIT_AUTHOR_NAME="t", GIT_AUTHOR_EMAIL="t@t", GIT_COMMITTER_NAME="t",
                                GIT_COMMITTER_EMAIL="t@t"))

    def commit(self, repo, ver, entries):
        (repo / "shell.qml").write_text(f'console.log("Glide Shell {ver} (x)")\n')
        (repo / "CHANGELOG.md").write_text("# что нового\n\n" + "".join(f"- **{v}** — {t}\n" for v, t in entries))
        self.git(repo, "add", "-A"); self.git(repo, "commit", "-qm", ver)

    def test_status_and_apply(self):
        if not shutil.which("git"):
            self.skipTest("нет git")
        # настоящий systemctl внутри юнита обновления ответил бы «идёт» — и обновлять было бы нельзя
        self.shim("systemctl", "#!/bin/sh\nexit 3\n")
        up, work, src = self.tmp / "up.git", self.tmp / "work", self.tmp / "src"
        self.git(self.tmp, "init", "-q", "--bare", "-b", "main", str(up))
        self.git(self.tmp, "clone", "-q", str(up), str(work))
        self.commit(work, "v0.1", [("v0.1", "первая")])
        self.git(work, "push", "-q", "origin", "HEAD:main")
        self.git(self.tmp, "clone", "-q", str(up), str(src))
        (self.state / "glide-shell").mkdir()
        (self.state / "glide-shell" / "source").write_text(str(src) + "\n")
        self.commit(work, "v0.2", [("v0.2", "светлая тема"), ("v0.1", "первая")])
        self.git(work, "push", "-q", "origin", "HEAD:main")
        env = {"GLIDE_UPDATE_INLINE": "1", "GLIDE_UPDATE_INSTALL": "echo ok > installed"}
        st = json.loads(self.run_py(TOOLS / "glide-update.py", "status", "--fetch", env=env).stdout)
        sh = st["shell"]
        self.assertEqual((sh["current"], sh["latest"], sh["behind"]), ("v0.1", "v0.2", 1))
        self.assertEqual(sh["changes"], ["v0.2 — светлая тема"])
        self.assertTrue(sh["canUpdate"])
        self.assertFalse(st["apps"]["git"])                          # приложения не поставлены — не из git
        (src / "shell.qml").write_text("своя правка\n")             # свои правки — не обновлять
        self.assertFalse(json.loads(self.run_py(TOOLS / "glide-update.py", "apply", "shell", env=env).stdout)["ok"])
        self.git(src, "checkout", "--", "shell.qml")
        r = json.loads(self.run_py(TOOLS / "glide-update.py", "apply", "shell", env=env, timeout=60).stdout)
        self.assertTrue(r["ok"], r)
        self.assertEqual((r["from"], r["to"]), ("v0.1", "v0.2"))
        self.assertTrue((src / "installed").exists())
        res = json.loads((self.state / "glide-shell" / "update.json").read_text())
        self.assertFalse(res["shown"])
        self.run_py(TOOLS / "glide-update.py", "ack", env=env)
        self.assertTrue(json.loads((self.state / "glide-shell" / "update.json").read_text())["shown"])


class Preview(Sandbox):
    """Быстрый просмотр: текст — начало, папка — содержимое, PDF и видео — картинка в кэше."""

    def look(self, path):
        return json.loads(self.run_py(TOOLS / "glide-preview.py", str(path), timeout=60).stdout)

    def test_kinds(self):
        (self.tmp / "заметка.md").write_text("# Заголовок\nстрока\n")
        r = self.look(self.tmp / "заметка.md")
        self.assertEqual(r["kind"], "text")
        self.assertIn("Заголовок", r["text"])
        d = self.tmp / "папка"; d.mkdir(); (d / "a.txt").write_text("1"); (d / "sub").mkdir(); (d / ".скрытый").write_text("")
        r = self.look(d)
        self.assertEqual((r["kind"], r["count"]), ("dir", 2))
        self.assertIn("sub/", r["items"])
        self.assertEqual(self.look(self.tmp / "нет-такого")["kind"], "error")
        if shutil.which("ffmpeg"):
            v = self.tmp / "клип.mp4"
            subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "lavfi", "-i", "testsrc2=size=320x240:duration=4", str(v)],
                           check=True, stdin=subprocess.DEVNULL)
            r = self.look(v)
            self.assertEqual(r["kind"], "video")
            self.assertTrue(Path(r["image"]).exists())
            self.assertTrue(str(self.cache) in r["image"])

    def test_huge_single_line(self):
        """Файл из одной огромной строки не читается целиком — только начало."""
        f = self.tmp / "big.json"
        f.write_text("[" + "1," * 30_000_000 + "1]")   # ~60 МБ без переводов строк
        r = self.look(f)
        self.assertEqual(r["kind"], "text")
        self.assertLessEqual(len(r["text"]), 4000)


class ArchUpdates(Sandbox):
    """Обновления Arch: разбор «имя старая -> новая», без pacman — «не поддерживается», итог — в state."""

    def test_check(self):
        self.shim("pacman", "#!/bin/sh\nexit 0\n")
        self.shim("checkupdates", "#!/bin/sh\necho 'linux 6.1-1 -> 6.2-1'\necho 'мусор'\necho 'mesa 1:24-1 -> 1:25-1'\n")
        self.shim("yay", "#!/bin/sh\necho 'blockbench 5.2.0-1 -> 5.2.1-1'\n")
        self.shim("paru", "#!/bin/sh\nexit 1\n")   # paru «есть», но первым берётся он — отвечает пусто
        r = json.loads(self.run_py(TOOLS / "glide-archupdates.py", "check").stdout)
        self.assertEqual([x["name"] for x in r["repo"]], ["linux", "mesa"])
        self.assertEqual(r["repo"][1]["to"], "1:25-1")
        self.assertEqual(r["count"], 2 + len(r["aur"]))
        self.assertTrue((self.state / "glide-shell" / "archupdates.json").exists())
        r = json.loads(self.run_py(TOOLS / "glide-archupdates.py", "check", env={"PATH": str(self.bin) + ":/usr/bin"}).stdout)
        self.assertTrue(r["supported"])


class PluginScaffold(Sandbox):
    """Заготовка плагина и виджета: файлы на месте, манифест — валидный JSON с api 2, permissions, bar и settings."""

    def test_new(self):
        out = self.run_py(TOOLS / "glide-plugin.py", "new", "demo", "Демо")
        self.assertEqual(out.returncode, 0, out.stderr)
        d = self.cfg / "glide-shell" / "plugins" / "demo"
        m = json.loads((d / "plugin.json").read_text())
        self.assertEqual((m["id"], m["api"], m["bar"], m["qml"]), ("demo", 2, "Bar.qml", "Main.qml"))
        self.assertEqual(m["permissions"], ["notifications"])
        self.assertTrue((d / "Main.qml").exists() and (d / "Bar.qml").exists())
        self.assertNotEqual(self.run_py(TOOLS / "glide-plugin.py", "new", "demo").returncode, 0)   # уже есть
        self.assertNotEqual(self.run_py(TOOLS / "glide-plugin.py", "new", "Плохой id").returncode, 0)
        self.assertEqual(self.run_py(TOOLS / "glide-plugin.py", "widget", "w1").returncode, 0)
        self.assertTrue((self.cfg / "glide-shell" / "widgets" / "w1" / "widget.qml").exists())


class ShellBus(Sandbox):
    """Служба org.glide.Shell на своей шине: команда → служба → оболочка (заглушка IPC пишет в файл);
    тема — из файла; приложение ушло с шины — его активность снимается."""

    def test_bus(self):
        if not shutil.which("dbus-run-session"):
            self.skipTest("нет dbus-run-session")
        try:
            import gi  # noqa: F401
        except ImportError:
            self.skipTest("нет python-gobject")
        rt = self.tmp / "run"; rt.mkdir()
        (rt / "glide-shell-theme.json").write_text('{"accent": "#7b61ff", "isLight": false}')
        log = self.tmp / "ipc.log"
        self.shim("fake-ipc", f"#!/bin/sh\necho \"$1\" >> {log}\n")
        tool = TOOLS / "glide-shell.py"
        app = ("import gi,time\ngi.require_version('Gio','2.0')\nfrom gi.repository import Gio,GLib\n"
               "b=Gio.bus_get_sync(Gio.BusType.SESSION)\n"
               "b.call_sync('org.glide.Shell','/org/glide/Shell','org.glide.Shell1','StartActivity',"
               "GLib.Variant('(sa{sv})',('app1',{'title':GLib.Variant('s','Синхронизация')})),None,0,5000,None)\n")
        script = (f"{sys.executable} -I {tool} --daemon & D=$!; sleep 1; "
                  f"{sys.executable} -I {tool} flash 'Готово, всё'; "
                  f"{sys.executable} -I {tool} activity start dl --title 'Загрузка' --progress 0.5; "
                  f"{sys.executable} -I {tool} theme; "
                  f"{sys.executable} -I -c \"{app}\"; sleep 1; kill $D")
        r = subprocess.run(["dbus-run-session", "--", "sh", "-c", script], capture_output=True, text=True, timeout=60,
                           stdin=subprocess.DEVNULL, env={**self.env, "XDG_RUNTIME_DIR": str(rt),
                                                         "GLIDE_SHELL_IPC": str(self.bin / "fake-ipc")})
        self.assertIn('"accent": "#7b61ff"', r.stdout, r.stderr)
        import base64
        msgs = [json.loads(base64.b64decode(l)) for l in log.read_text().split()]
        ops = [(m["op"], m.get("id")) for m in msgs]
        self.assertIn(("flash", None), ops)
        self.assertEqual(next(m for m in msgs if m["op"] == "flash")["text"], "Готово, всё")   # запятая — цела
        self.assertIn(("start", "cli/dl"), ops)
        self.assertIn(("start", "app1"), ops)
        self.assertIn(("end", "app1"), ops)            # приложение закрылось — активность снята
        self.assertNotIn(("end", "cli/dl"), ops)       # из команды — живёт, пока не снимут
