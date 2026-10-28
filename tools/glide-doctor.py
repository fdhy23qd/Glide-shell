#!/usr/bin/env python3
"""Проверка Glide Shell на этом компьютере: что сломано, что стоит посмотреть и как исправить. Сам ничего не меняет.

    glide-shell doctor                 — по-человечески: ✓ в порядке, ! посмотреть, ✗ сломано (код выхода 1, если есть ✗)
    glide-shell doctor --json          — то же списком JSON (экран «Поведение» → «Проверка»)
    glide-shell doctor --only ID,ID    — только эти проверки (для тестов)

Проверки (id): deps, optional, service, instances, orphans, install, niri, files, config, journal, disk.
"""
import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

HOME = Path.home()
CFG = Path(os.environ.get("XDG_CONFIG_HOME") or HOME / ".config")
STATE = Path(os.environ.get("XDG_STATE_HOME") or HOME / ".local/state") / "glide-shell"
CACHE = Path(os.environ.get("XDG_CACHE_HOME") or HOME / ".cache") / "glide-shell"
SHELL_CFG = CFG / "glide-shell"
INSTALLED = CFG / "quickshell" / "glide-shell"
NIRI = Path(os.environ.get("GLIDE_NIRI_DIR") or CFG / "niri")
UNIT = "glide-shell.service"

REQUIRED = [("qs", "Quickshell"), ("niri", "niri"), ("python3", "Python"), ("wl-copy", "wl-clipboard"),
            ("wl-paste", "wl-clipboard"), ("notify-send", "libnotify"), ("pactl", "libpulse"), ("setpriv", "util-linux"),
            ("gdbus", "glib2"), ("busctl", "systemd"), ("xdg-open", "xdg-utils")]
OPTIONAL = [("nmcli", "Wi-Fi"), ("bluetoothctl", "Bluetooth"), ("upower", "батарея"), ("powerprofilesctl", "профили питания"),
            ("udisksctl", "флешки"), ("kdeconnect-cli", "телефон"), ("wf-recorder", "запись экрана"), ("slurp", "запись области"), ("grim", "текст с экрана"), ("tesseract", "текст с экрана"),
            ("wlsunset", "ночной свет"), ("ffmpeg", "видео-обои и кадры видео")]
SECRET = [(STATE / "clipboard.json", 0o600), (STATE / "clipboard-pins.json", 0o600), (STATE / "notifications.json", 0o600),
          (STATE / "ai-chat.json", 0o600), (STATE / "clipboard-img", 0o700), (SHELL_CFG / "anthropic-key", 0o600)]


def run(argv, timeout=10):
    """(код, вывод) — без исключений: нет программы — 127."""
    try:
        r = subprocess.run(argv, capture_output=True, text=True, timeout=timeout, stdin=subprocess.DEVNULL)
        return r.returncode, (r.stdout + r.stderr).strip()
    except FileNotFoundError:
        return 127, ""
    except subprocess.TimeoutExpired:
        return 124, ""


def res(status, title, detail="", fix=""):
    return {"status": status, "title": title, "detail": detail, "fix": fix}


def procs():
    """[(pid, ppid, cmdline)] всех процессов пользователя."""
    out, uid = [], os.getuid()
    for p in Path("/proc").iterdir():
        if not p.name.isdigit():
            continue
        try:
            if p.stat().st_uid != uid:
                continue
            cmd = (p / "cmdline").read_bytes().replace(b"\0", b" ").decode(errors="replace").strip()
            ppid = int((p / "stat").read_text().rsplit(")", 1)[1].split()[1])
        except (OSError, ValueError, IndexError):
            continue
        if cmd:
            out.append((int(p.name), ppid, cmd))
    return out


def service_pids():
    code, cg = run(["systemctl", "--user", "show", "-p", "ControlGroup", "--value", UNIT])
    try:
        return {int(x) for x in Path(f"/sys/fs/cgroup{cg}/cgroup.procs").read_text().split()} if code == 0 and cg else set()
    except OSError:
        return set()


def version_of(shell_qml):
    try:
        m = re.search(r"Glide Shell v(\d+(?:\.\d+)+)", Path(shell_qml).read_text())
        return m.group(1) if m else ""
    except OSError:
        return ""


# ---------------------------------------------------------------- проверки
def c_deps():
    miss = [f"{c} ({pkg})" for c, pkg in REQUIRED if not shutil.which(c)]
    fonts = []
    code, out = run(["fc-list"])
    if code == 0:
        fonts = [f for f, key in (("JetBrainsMono Nerd Font", "JetBrainsMono Nerd"), ("Inter", "Inter")) if key not in out]
    if miss or fonts:
        return res("fail", "Зависимости: не хватает", ", ".join(miss + [f"шрифт {f}" for f in fonts]),
                   "sh setup.sh из папки исходников предложит поставить")
    return res("ok", "Зависимости: всё нужное есть")


def c_optional():
    miss = [f"{c} — {what}" for c, what in OPTIONAL if not shutil.which(c)]
    if miss:
        return res("warn", f"По желанию: нет {len(miss)}", "; ".join(miss), "нужно только для этих функций; setup.sh предложит")
    return res("ok", "По желанию: всё есть")


def c_service():
    code, state = run(["systemctl", "--user", "is-active", UNIT])
    if code == 127:
        return res("skip", "Служба: нет systemctl")
    if state != "active":
        return res("fail", "Служба не работает", f"состояние: {state or 'нет'}",
                   "journalctl --user -u glide-shell -n 50 — почему; sh install.sh — поставить заново")
    issues = []
    _, enabled = run(["systemctl", "--user", "is-enabled", UNIT])
    if enabled.strip() not in ("enabled", "static", "linked"):
        issues.append(f"не включена при входе ({enabled.strip()})")
    _, show = run(["systemctl", "--user", "show", "-p", "NRestarts", "-p", "Environment", UNIT])
    v = dict(l.split("=", 1) for l in show.splitlines() if "=" in l)
    restarts = int(v.get("NRestarts") or 0)
    if restarts:
        issues.append(f"перезапускалась после падения: {restarts}")
    if "QS_DISABLE_CRASH_HANDLER=1" not in v.get("Environment", ""):
        issues.append("старый файл службы (нет QS_DISABLE_CRASH_HANDLER)")
    if issues:
        return res("warn", "Служба работает, но", "; ".join(issues), "sh install.sh обновит файл службы; падения — journalctl --user -u glide-shell")
    return res("ok", "Служба работает", "включена при входе, падений не было")


def c_instances():
    ps = procs()
    mine = os.getpid()
    shells = [p for p in ps if re.match(r"^(\S*/)?qs -c glide-shell$", p[2])]
    problems, fix = [], []
    if len(shells) > 1:
        problems.append(f"запущено экземпляров: {len(shells)} (pid {', '.join(str(p[0]) for p in shells)})")
        fix.append("лишний — не служба: systemctl --user restart glide-shell, затем kill PID лишнего")
    dms = [p for p in ps if re.search(r"(^|/)dms run$", p[2]) and p[0] != mine]
    if dms:
        problems.append("работает DMS (аварийный откат?)")
        fix.append("вернуть Glide Shell: sh ~/.config/quickshell/glide-shell/tools/glide-rescue.sh undo")
    try:
        notifs = json.loads((SHELL_CFG / "config.json").read_text()).get("panel", {}).get("notifications") is True
    except (OSError, ValueError, AttributeError):
        notifs = False
    if notifs:
        code, out = run(["busctl", "--user", "status", "org.freedesktop.Notifications"])
        m = re.search(r"^Comm=(\S+)", out, re.M)
        if code == 0 and m and m.group(1) not in ("qs", ".qs-wrapped"):
            problems.append(f"уведомления держит другая программа: {m.group(1)}")
            fix.append(f"останови её (pkill -x {m.group(1)}) и убери из автозапуска; setup.sh делает это сам")
    if problems:
        return res("fail", "Рядом работает лишнее", "; ".join(problems), "; ".join(fix))
    return res("ok", "Один экземпляр, других оболочек рядом нет")


def c_orphans():
    inside = service_pids()
    if not inside:
        return res("skip", "Помощники: служба не запущена — не с чем сравнить")
    me = {os.getpid(), os.getppid()}
    lost = [p for p in procs() if p[0] not in inside and p[0] not in me
            and ("/glide-shell/tools/" in p[2] and "glide-doctor" not in p[2] and "glide-shell.py" not in p[2]
                 or "--who=Glide Shell" in p[2])]
    if lost:
        return res("warn", f"Осиротевшие помощники: {len(lost)}",
                   "; ".join(f"{p[0]}: {p[2][:90]}" for p in lost[:6]),
                   "остались от прежнего запуска оболочки — kill " + " ".join(str(p[0]) for p in lost[:6]))
    return res("ok", "Помощники: все внутри службы, сирот нет")


def c_install():
    if not (INSTALLED / "shell.qml").exists():
        return res("fail", "Не установлена", str(INSTALLED), "sh install.sh в папке исходников")
    have = version_of(INSTALLED / "shell.qml")
    issues, fix = [], []
    try:
        src = Path((STATE / "source").read_text().strip())
    except OSError:
        src = None
    if src and (src / "shell.qml").exists():
        want = version_of(src / "shell.qml")
        if want and want != have:
            issues.append(f"установлена v{have}, в исходниках v{want}")
            fix.append(f"cd {src} && sh install.sh")
    link = HOME / ".local/bin/glide-shell"
    if not link.exists():
        issues.append("нет команды glide-shell (~/.local/bin)")
        fix.append("sh install.sh")
    dbus = Path(os.environ.get("XDG_DATA_HOME") or HOME / ".local/share") / "dbus-1/services/org.glide.Shell.service"
    if not dbus.exists():
        issues.append("нет службы D-Bus org.glide.Shell")
        fix.append("sh install.sh")
    if issues:
        return res("warn", f"Установка v{have}: есть расхождения", "; ".join(issues), "; ".join(dict.fromkeys(fix)))
    return res("ok", f"Установлена v{have}", "совпадает с исходниками" if src else "")


def includes(path, seen=None):
    """Подключаемые файлы niri по порядку (без закомментированных) — с вложенными."""
    seen = seen if seen is not None else []
    try:
        text = path.read_text()
    except OSError:
        return seen
    for m in re.finditer(r'^\s*include\s+"([^"]+)"', text, re.M):
        p = (path.parent / os.path.expanduser(m.group(1))).resolve()
        if p not in seen:
            seen.append(p)
            includes(p, seen)
    return seen


def sections(path):
    """Разделы верхнего уровня файла KDL (input, binds, layout…)."""
    try:
        return set(re.findall(r"^([a-z][a-z-]*)\b", path.read_text(), re.M)) - {"include"}
    except OSError:
        return set()


def c_niri():
    conf = NIRI / "config.kdl"
    if not conf.exists():
        return res("skip", "niri: нет config.kdl", str(conf))
    problems, warns, fix = [], [], []
    code, out = run(["niri", "validate", "-c", str(conf)], 20)
    if code not in (0, 127):
        lines = [l for l in re.sub(r"\x1b\[[0-9;]*m", "", out).splitlines() if l.strip() and "DEBUG" not in l]
        problems.append("niri validate: " + " / ".join(lines[-3:]))
        fix.append("исправь config.kdl (копии до правок Glide — config.kdl.before-glide-*)")
    inc = includes(conf)
    missing = [p.name for p in inc if not p.exists()]
    if missing:
        problems.append("нет подключаемых файлов: " + ", ".join(missing))
        fix.append("создай пустые или убери строки include из config.kdl")
    names = [p.name for p in inc if p.parent == conf.parent.resolve()]
    if "glide-settings.kdl" in names:
        # перекрыть настройки «Устройств» может только файл, подключённый позже, с теми же разделами (input, binds…)
        mine = sections(NIRI / "glide-settings.kdl")
        later = inc[[p.name for p in inc].index("glide-settings.kdl") + 1:]
        clash = [f"{p.name} ({', '.join(sorted(sections(p) & mine))})" for p in later if sections(p) & mine]
        if clash:
            warns.append("после glide-settings.kdl подключено то же самое: " + "; ".join(clash) + " — настройки «Устройств» перекрываются")
    if "glide-outputs.kdl" in names and names[0] != "glide-outputs.kdl":
        warns.append("glide-outputs.kdl подключён не первым — у мониторов побеждает первое")
    texts = ""
    for p in [conf] + inc:
        try:
            texts += p.read_text()
        except OSError:
            pass
    if "glide-rescue.sh" not in texts:
        warns.append("нет клавиши аварийного отката (glide-rescue.sh)")
        fix.append("setup.sh добавит её в glide-shell.kdl (Mod+Shift+Escape)")
    if problems:
        return res("fail", "niri: конфиг с ошибкой", "; ".join(problems + warns), "; ".join(fix))
    if warns:
        return res("warn", "niri: стоит посмотреть", "; ".join(warns), "; ".join(fix) or "порядок include в config.kdl")
    return res("ok", "niri: конфиг в порядке", f"подключено файлов: {len(inc)}")


def c_files():
    bad, fix = [], []
    for p, want in SECRET:
        try:
            mode = p.stat().st_mode & 0o777
        except OSError:
            continue
        if mode & 0o077:
            bad.append(f"{p.name} ({oct(mode)[2:]})")
            fix.append(f"chmod {oct(want)[2:]} {p}")
        if p.is_dir():
            loose = [f for f in p.iterdir() if f.is_file() and f.stat().st_mode & 0o077]
            if loose:
                bad.append(f"{p.name}/: открытых для других — {len(loose)}")
                fix.append(f"chmod 600 {p}/*")
    if bad:
        return res("warn", "Личное доступно другим пользователям", "; ".join(bad), "; ".join(fix))
    return res("ok", "Права файлов: личное — только для тебя")


def c_config():
    bad = []
    for name in ("config.json", "permissions.json"):
        p = SHELL_CFG / name
        if not p.exists():
            continue
        try:
            if not isinstance(json.loads(p.read_text()), dict):
                raise ValueError
        except (OSError, ValueError):
            bad.append(name)
    if bad:
        return res("fail", "Настройки не читаются", ", ".join(bad),
                   "вернуть из копии: «Поведение» → «Резервная копия» или glide-backup.py import ФАЙЛ")
    return res("ok", "Настройки читаются")


def c_journal():
    # только нынешний процесс службы: прошлые (до обновления, до перезапуска) уже не про то, что работает сейчас
    _, pid = run(["systemctl", "--user", "show", "-p", "MainPID", "--value", UNIT])
    pid = pid.strip() if pid.strip().isdigit() and pid.strip() != "0" else ""
    code, out = run(["journalctl", "--user", "-b", "-u", UNIT, "-o", "cat", "--no-pager"] + ([f"_PID={pid}"] if pid else []), 20)
    if code == 127:
        return res("skip", "Журнал: нет journalctl")
    out = re.sub(r"\x1b\[[0-9;]*m", "", out)
    since = "с запуска службы" if pid else "с начала сеанса"
    js = [l for l in out.splitlines() if re.search(r"TypeError|ReferenceError|is not a function|is not defined", l)]
    freezes = [l for l in out.splitlines() if "не отвечал" in l]
    crashes = out.count("Main process exited") + out.count("code=dumped")
    if not (js or freezes or crashes):
        return res("ok", f"Журнал {since}: ошибок нет")
    detail = []
    if js:
        detail.append(f"ошибок JS: {len(js)} (последняя: {js[-1].strip()[-140:]})")
    if freezes:
        detail.append(f"зависаний интерфейса: {len(freezes)}")
    if crashes:
        detail.append(f"падений: {crashes}")
    return res("warn", f"Журнал {since}: есть ошибки", "; ".join(detail), "journalctl --user -b -u glide-shell | grep -E 'TypeError|не отвечал'")


def size(p):
    total = 0
    for root, _, files in os.walk(p):
        for f in files:
            try:
                total += os.lstat(os.path.join(root, f)).st_size
            except OSError:
                pass
    return total


def c_disk():
    c, s = size(CACHE), size(STATE)
    mb = lambda b: f"{b / 1048576:.1f} МБ" if b < 10 << 20 else f"{b / 1048576:.0f} МБ"
    if c + s > 1 << 30:
        return res("warn", "Занято много места", f"кэш {mb(c)}, данные {mb(s)}", f"кэш можно удалить: rm -r {CACHE}")
    return res("ok", "Место", f"кэш {mb(c)}, данные {mb(s)}")


CHECKS = {"deps": c_deps, "optional": c_optional, "service": c_service, "instances": c_instances, "orphans": c_orphans,
          "install": c_install, "niri": c_niri, "files": c_files, "config": c_config, "journal": c_journal, "disk": c_disk}


def main(a):
    only = None
    if "--only" in a:
        only = a[a.index("--only") + 1].split(",")
    out = []
    for cid, fn in CHECKS.items():
        if only and cid not in only:
            continue
        try:
            r = fn()
        except Exception as e:   # noqa: BLE001 — сама проверка сломалась: скажем, а остальные пройдут
            r = res("warn", f"Проверка «{cid}» не выполнилась", f"{type(e).__name__}: {e}")
        out.append(dict(r, id=cid))
    if "--json" in a:
        print(json.dumps(out, ensure_ascii=False))
    else:
        mark = {"ok": "\033[32m✓\033[0m", "warn": "\033[33m!\033[0m", "fail": "\033[31m✗\033[0m", "skip": "\033[90m—\033[0m"}
        if not sys.stdout.isatty():
            mark = {"ok": "✓", "warn": "!", "fail": "✗", "skip": "—"}
        for r in out:
            print(f"{mark[r['status']]} {r['title']}" + (f" — {r['detail']}" if r["detail"] else ""))
            if r["fix"] and r["status"] in ("warn", "fail"):
                print(f"    → {r['fix']}")
        n = {k: sum(1 for r in out if r["status"] == k) for k in ("fail", "warn")}
        print(f"\nсломано: {n['fail']}, посмотреть: {n['warn']}" if n["fail"] or n["warn"] else "\nвсё в порядке")
    sys.exit(1 if any(r["status"] == "fail" for r in out) else 0)


if __name__ == "__main__":
    main(sys.argv[1:])
