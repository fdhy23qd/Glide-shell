"""Сценарии QML (tests/qml/*.qml) на настоящем Quickshell — без экрана и без настоящих данных.

Каждый сценарий — свой shell.qml во временной копии оболочки: QML-файлы ядра копируются, tools/ i18n/ plugins/ —
ссылками. Папки XDG — временные, в PATH — заглушки: niri пишет вызовы в журнал (ничего не делает),
systemd-run / xdg-open / notify-send / wl-copy — молчат. Сценарий печатает строки «QMLTEST|PASS|имя|…»
(помощник tests/qml/QmlCheck.qml), здесь они разбираются. Нет qs — тесты пропускаются.

    python3 -m unittest tests.test_qml -v
"""
import json
import os
import re
import shutil
import stat
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SCEN = ROOT / "tests" / "qml"
LINE = re.compile(r"QMLTEST\|(PASS|FAIL|DONE)\|([^|]*)\|(.*)")

SHIMS = {
    "niri": '#!/bin/sh\necho "$*" >> "$NIRI_LOG"\n[ "$*" = "msg --json event-stream" ] && exec sleep 600\nexit 0\n',
    "systemd-run": '#!/bin/sh\necho "systemd-run $*" >> "$NIRI_LOG"\n',
    "xdg-open": "#!/bin/sh\nexit 0\n",
    "notify-send": "#!/bin/sh\nexit 0\n",
    "wl-copy": "#!/bin/sh\ncat >/dev/null; exit 0\n",
}


@unittest.skipUnless(shutil.which("qs"), "нет Quickshell (qs)")
class Scenarios(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix="glide-qml-"))
        self.shell = self.tmp / "shell"
        self.shell.mkdir()
        for f in ROOT.glob("*.qml"):
            shutil.copy(f, self.shell / f.name)
        for d in ("tools", "i18n", "plugins"):
            (self.shell / d).symlink_to(ROOT / d)
        shutil.copy(SCEN / "QmlCheck.qml", self.shell / "QmlCheck.qml")
        self.cfg, self.state, self.cache, self.data, self.run_dir, self.bin = (
            self.tmp / d for d in ("config", "state", "cache", "data", "run", "bin"))
        for d in (self.cfg / "glide-shell", self.state / "glide-shell", self.cache, self.data / "applications",
                  self.run_dir, self.bin):
            d.mkdir(parents=True)
        self.run_dir.chmod(0o700)
        for name, body in SHIMS.items():
            p = self.bin / name
            p.write_text(body)
            p.chmod(0o755)
        (self.data / "applications" / "glidetest.desktop").write_text(
            "[Desktop Entry]\nType=Application\nName=Glide Test\nExec=true\n")
        self.niri_log = self.tmp / "niri.log"
        self.niri_log.write_text("")

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def permissions(self, plugins, name="permissions.json"):
        (self.cfg / "glide-shell" / name).write_text(json.dumps(
            {"version": 1, "legacy": {"plugins": True, "widgets": True, "messages": True}, "plugins": plugins}))

    def scenario(self, name, timeout=40):
        shutil.copy(SCEN / f"{name}.qml", self.shell / "shell.qml")
        env = dict(os.environ, PATH=f"{self.bin}:{os.environ['PATH']}", NIRI_LOG=str(self.niri_log),
                   XDG_CONFIG_HOME=str(self.cfg), XDG_STATE_HOME=str(self.state), XDG_CACHE_HOME=str(self.cache),
                   XDG_DATA_HOME=str(self.data), XDG_DATA_DIRS=str(self.data), XDG_RUNTIME_DIR=str(self.run_dir),
                   QT_QPA_PLATFORM="offscreen", QS_ICON_THEME="hicolor", **getattr(self, "env_extra", {}))
        env.pop("WAYLAND_DISPLAY", None)
        r = subprocess.run(["qs", "-p", str(self.shell)], env=env, stdin=subprocess.DEVNULL,
                           capture_output=True, text=True, timeout=timeout)
        out = r.stdout + r.stderr
        results = [m.groups() for m in LINE.finditer(out)]
        self.assertTrue(any(k == "DONE" for k, _, _ in results),
                        f"сценарий {name} не дошёл до конца:\n" + "\n".join(out.splitlines()[-30:]))
        for kind, check, detail in results:
            if kind != "DONE":
                with self.subTest(check=check):
                    self.assertEqual(kind, "PASS", f"{check}: {detail}")
        return out

    def test_api(self):
        """API плагинов: права — только по разрешениям, обходов через api нет (launchApp, niri, handoff, exec, files)."""
        self.permissions({"t": {"api": 2, "granted": ["windows"], "denied": []},
                          "e": {"api": 2, "granted": ["exec"], "denied": []}})
        self.scenario("api")
        self.assertFalse(Path("/tmp/glide-qmltest-pwned").exists())
        actions = [l for l in self.niri_log.read_text().splitlines() if l.startswith("msg action")]
        self.assertEqual(actions, ["msg action focus-workspace 2"], "до niri дошло лишнее (spawn/quit?)")
        self.assertNotIn("systemd-run", self.niri_log.read_text(), "launchApp запустил что-то сам")

    def test_core(self):
        """Разрешения из копии, правка в обход, перерегистрация, очередь, история уведомлений."""
        self.permissions({})
        self.permissions({"x": {"api": 2, "granted": ["exec"], "denied": []}}, "permissions.json.import")
        (self.state / "glide-shell" / "notifications.json").write_text(json.dumps(
            [{"key": k, "time": 0, "appName": "старое", "summary": f"старое {k}", "body": "", "urgency": 1, "unread": False}
             for k in (1, 2, 3)]))
        out = self.scenario("core")
        # ровно одно «в обход» — от намеренной правки сценария; второе — ложное от подхвата копии (запоздалая загрузка
        # прежнего файла): сигнал tampered сценарий может и не застать, а журнал — видит
        self.assertEqual(out.count("изменён в обход"), 1, "лишнее предупреждение «правка в обход»")
        self.assertFalse((self.cfg / "glide-shell" / "permissions.json.import").exists(), ".import не убран")
        hist = self.state / "glide-shell" / "notifications.json"
        self.assertGreater(hist.stat().st_size, 128 * 1024, "большая история не записалась")
        self.assertEqual(len(json.loads(hist.read_text())), 50)
        self.assertEqual(stat.S_IMODE(hist.stat().st_mode), 0o600)


    def test_search(self):
        """Провайдеры поиска: по разрешению, устаревшее — прочь, поля проверены; калькулятор, единицы, смайлики."""
        self.permissions({"s": {"api": 2, "granted": ["search"], "denied": []},
                          "n": {"api": 2, "granted": [], "denied": []},
                          "tmp": {"api": 2, "granted": ["search"], "denied": []},
                          "r": {"api": 2, "granted": ["search"], "denied": []}})
        self.scenario("search")

    def test_drives(self):
        """Съёмные диски: о вставленном до запуска — молчим, новое — подключить и сообщить, кнопки уведомления работают."""
        log = self.tmp / "drives.log"
        tool = self.tmp / "fake-drives.py"
        drive = lambda i, **k: dict({"id": i, "label": i, "device": "/dev/" + i, "fs": "vfat", "size": 1 << 30, "mounted": False,
                                     "mountPoint": "", "drive": "", "driveName": "", "ejectable": False, "canPowerOff": True,
                                     "encrypted": False, "image": False}, **k)
        steps = [[drive("A", mounted=True, mountPoint="/run/media/u/A")],
                 [drive("A", mounted=True, mountPoint="/run/media/u/A"), drive("B"), drive("C", fs="crypto_LUKS", encrypted=True)],
                 [drive("A", mounted=True, mountPoint="/run/media/u/A"), drive("B"), drive("C", encrypted=True), drive("D")]]
        tool.write_text(f"""import json, sys, time
log = open({str(log)!r}, "a")
a = sys.argv[1:]
log.write(" ".join(a) + "\\n"); log.flush()
if a[0] == "watch":
    for i, s in enumerate({json.dumps(steps)!r} and {steps!r}):
        print(json.dumps(s), flush=True); time.sleep(2.2)
    sys.stdin.read()
elif a[0] == "mount":
    print(json.dumps({{"ok": True, "mountPoint": "/run/media/u/" + a[1]}}))
elif a[1] == "busy":
    print(json.dumps({{"ok": False, "error": "занято"}}))
else:
    print(json.dumps({{"ok": True}}))
""")
        notify = self.bin / "notify-send"   # «нажимает»: после подключения — «Открыть», без подключения — «Подключить»
        notify.write_text(f'#!/bin/sh\necho "notify $*" >> {log}\ncase "$*" in *mount=*) echo mount ;; *open=*) echo open ;; esac\n')
        self.env_extra = {"GLIDE_DRIVES_TOOL": str(tool)}
        self.scenario("drives")
        lines = log.read_text().splitlines()
        notes = [l for l in lines if l.startswith("notify")]
        self.assertFalse(any(" A " in n or "Подключено: A" in n for n in notes), "о вставленном до запуска не сообщаем")
        self.assertIn("mount B", lines, "новое — подключить само")
        self.assertTrue(any("Подключено: B" in n and "open=" in n and "eject=" in n for n in notes), notes)
        self.assertIn("xdg-open /run/media/u/B", self.niri_log.read_text(), "«Открыть» в уведомлении — открыть папку")
        self.assertNotIn("mount C", lines, "зашифрованное не подключаем")
        self.assertTrue(any("Зашифрованный диск" in n for n in notes))
        self.assertTrue(any("Вставлен диск: D" in n and "mount=" in n for n in notes), "без «подключать сами» — кнопка «Подключить»")
        self.assertIn("mount D", lines, "кнопка «Подключить» в уведомлении — подключить")
        self.assertIn("eject A", lines)

    def test_extras(self):
        """v2.8: «до перезапуска», api.confirm, api.schedule, api.pickFile/saveFile, api.clipboard.listen."""
        self.permissions({"c": {"api": 2, "granted": ["clipboard"], "denied": []}})
        log = self.tmp / "extras.log"
        pick = self.tmp / "fake-pick.py"
        pick.write_text(f"""import json, sys
a = sys.argv[1:]
open({str(log)!r}, "a").write(" ".join(a) + "\\n")
if a[0] == "open":
    print(json.dumps({{"ok": True, "paths": ["/tmp/выбран.txt"], "texts": ["содержимое"]}}))
else:
    open({str(log)!r}, "a").write("TEXT:" + sys.stdin.read() + "\\n")
    print(json.dumps({{"ok": True, "paths": ["/tmp/куда.txt"]}}))
""")
        wl = self.bin / "fake-wl-paste"   # --watch: две смены текста и одна с пометкой пароля
        wl.write_text("#!/bin/sh\n"
                      "if [ \"$1\" = -l ]; then [ -f \"$0.pw\" ] && echo x-kde-passwordManagerHint; exit 0; fi\n"
                      "shift 3; for t in 'привет\nмир' 'пароль' 'второй'; do\n"
                      "  if [ \"$t\" = пароль ]; then touch \"$0.pw\"; else rm -f \"$0.pw\"; fi\n"
                      "  printf \"$t\" | \"$@\"; done; exec sleep 600\n")
        wl.chmod(0o755)
        self.env_extra = {"GLIDE_PICK_TOOL": str(pick), "GLIDE_WLPASTE": str(wl)}
        self.scenario("extras")
        self.assertIn("TEXT:текст для сохранения", log.read_text())
        f = self.state / "glide-shell" / "schedules.json"
        self.assertEqual(stat.S_IMODE(f.stat().st_mode), 0o600)
        self.assertEqual(json.loads(f.read_text()), [], "сработавшие — удалены из файла")

    def test_recent(self):
        """«Недавние»: служба плагина читает историю и отвечает в поиске."""
        files = self.tmp / "files"; files.mkdir()
        (files / "отчёт.pdf").write_text("x"); (files / "b.txt").write_text("y")
        x = self.tmp / "r.xbel"
        x.write_text('<?xml version="1.0"?><xbel>'
                     f'<bookmark href="file://{files}/%D0%BE%D1%82%D1%87%D1%91%D1%82.pdf" modified="2026-10-01T10:00:00Z"/>'
                     f'<bookmark href="file://{files}/b.txt" modified="2026-10-02T10:00:00Z"/></xbel>')
        self.env_extra = {"GLIDE_RECENT_XBEL": str(x)}
        self.scenario("recent")

if __name__ == "__main__":
    unittest.main()
