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
                   QT_QPA_PLATFORM="offscreen", QS_ICON_THEME="hicolor")
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


if __name__ == "__main__":
    unittest.main()
