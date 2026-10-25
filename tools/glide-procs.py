#!/usr/bin/env python3
"""Что запущено оболочкой: процессы службы glide-shell (её cgroup) с нагрузкой и памятью — для «Настройки» → «Процессы».

    glide-procs.py          — JSON: {main: {...}, procs: [...], total: {cpu, pss}}
    glide-procs.py kill PID — завершить процесс службы (только из её cgroup и не саму оболочку)
    glide-procs.py errors   — JSON: предупреждения и ошибки QML нынешнего запуска оболочки по плагинам и виджетам
                              {id: {count, last: [{time, text}]}} (по пути файла или «glide-shell: id: …»)

ЦП — доля одного ядра за полсекунды замера, память — PSS (общие библиотеки поделены между процессами; RSS раздут
шрифтами). «Сирота» — процесс в группе службы, который не происходит от нынешней оболочки: остался от прежнего
экземпляра (KillMode=process) и никому не нужен. Свой процесс замера в списке не показывается.
"""
import json
import os
import re
import subprocess
import sys
import time

UNIT = "glide-shell.service"
TICK = os.sysconf("SC_CLK_TCK")
HOME = os.path.expanduser("~")

# понятные имена помощников: (шаблон командной строки, имя)
NAMES = [
    (r"^/usr/bin/qs -c glide-shell|^qs -c glide-shell", "Оболочка"),
    (r"niri msg --json event-stream", "События niri (окна, столы)"),
    (r"/proc/stat", "ЦП и память для бара"),
    (r"capslock", "Caps Lock"),
    (r"wl-paste --watch", "История буфера обмена"),
    (r"gdbus monitor --system --dest org.freedesktop.login1", "logind: сон и блокировка"),
    (r"glide-kdeconnect\.py", "KDE Connect"),
    (r"LauncherEntry", "Значки и прогресс в доке"),
    (r"glide-privacy\.py", "Камера (кто её использует)"),
    (r"glide-bt-agent\.py", "Агент Bluetooth"),
    (r"glide-files\.py", "Поиск файлов"),
    (r"wallpaper-player", "Видео-обои"),
    (r"(^|/)wlsunset", "Ночной свет"),
    (r"(^|/)wf-recorder", "Запись экрана"),
    (r"systemd-inhibit", "«Не засыпать» / блокировка перед сном"),
    (r"ip monitor", "VPN"),
    (r"pw-dump|pw-mon", "PipeWire"),
]
PLUGIN = re.compile(r"/plugins/([\w.-]+)/")
WIDGET = re.compile(r"/widgets/([\w.-]+)/")


def read(path):
    try:
        with open(path, "rb") as f:
            return f.read()
    except OSError:
        return b""


def cgroup_procs():
    cg = subprocess.run(["systemctl", "--user", "show", "-p", "ControlGroup", "--value", UNIT],
                        capture_output=True, text=True, stdin=subprocess.DEVNULL).stdout.strip()
    if not cg:
        return []
    raw = read(f"/sys/fs/cgroup{cg}/cgroup.procs").decode()
    return [int(x) for x in raw.split()]


def main_pid():
    out = subprocess.run(["systemctl", "--user", "show", "-p", "MainPID", "-p", "ActiveEnterTimestampMonotonic", UNIT],
                         capture_output=True, text=True, stdin=subprocess.DEVNULL).stdout
    v = dict(l.split("=", 1) for l in out.splitlines() if "=" in l)
    return int(v.get("MainPID") or 0), int(v.get("ActiveEnterTimestampMonotonic") or 0) / 1e6


def stat(pid):
    """(ppid, utime+stime в тиках, время старта в секундах от загрузки) или None"""
    s = read(f"/proc/{pid}/stat").decode(errors="replace")
    if not s:
        return None
    f = s[s.rfind(")") + 2:].split()      # после имени (в нём бывают пробелы и скобки)
    return int(f[1]), int(f[11]) + int(f[12]), int(f[19]) / TICK


def pss(pid):
    m = re.search(rb"^Pss:\s+(\d+)", read(f"/proc/{pid}/smaps_rollup"), re.M)
    return int(m.group(1)) if m else 0     # КБ


def cmdline(pid):
    return read(f"/proc/{pid}/cmdline").replace(b"\0", b" ").decode(errors="replace").strip()


def name_of(cmd):
    for pat, name in NAMES:              # известные — первыми (история буфера живёт в папке плагина clipboard)
        if re.search(pat, cmd):
            return name, ""
    m = PLUGIN.search(cmd)
    if m:
        return "Плагин " + m.group(1), m.group(1)
    m = WIDGET.search(cmd)
    if m:
        return "Виджет " + m.group(1), "widget-" + m.group(1)
    return os.path.basename(cmd.split(" ", 1)[0]) or "?", ""


def collect(interval=0.5):
    me = os.getpid()
    main, started = main_pid()
    pids = [p for p in cgroup_procs() if p != me]
    first = {p: stat(p) for p in pids}
    time.sleep(interval)
    uptime = float(read("/proc/uptime").split()[0] or 0)
    procs, parent = [], {p: s[0] for p, s in first.items() if s}

    def ours(p):   # потомок нынешней оболочки?
        seen = 0
        while p and seen < 64:
            if p == main:
                return True
            p = parent.get(p) or (stat(p) or (0,))[0]
            seen += 1
        return False

    for p in pids:
        a, b = first.get(p), stat(p)
        if not a or not b:
            continue
        cmd = cmdline(p)
        if not cmd or re.match(r"^(/usr/bin/)?sleep ", cmd) or "glide-procs.py" in cmd:
            continue                        # «sleep» внутри петель — часть своего родителя
        name, owner = name_of(cmd)
        procs.append({"pid": p, "ppid": b[0], "name": name, "owner": owner, "cmd": cmd[:300],
                      "cpu": round((b[1] - a[1]) / TICK / interval * 100, 1), "pss": pss(p),
                      "age": round(uptime - b[2]), "main": p == main, "orphan": p != main and not ours(p)})
    procs.sort(key=lambda x: (not x["main"], not x["orphan"], -x["pss"]))
    total = {"cpu": round(sum(x["cpu"] for x in procs), 1), "pss": sum(x["pss"] for x in procs)}
    mono = time.clock_gettime(time.CLOCK_MONOTONIC)
    return {"main": main, "uptime": round(mono - started) if started else 0, "procs": procs, "total": total}


ANSI = re.compile(r"\x1b\[[0-9;]*m")
FILE_OWNER = re.compile(r"/(plugins|widgets)/([\w.-]+)/")
LOG_OWNER = re.compile(r"glide-shell: ([a-z0-9][a-z0-9_.-]*): ")


def errors(limit=3000):
    main, _ = main_pid()
    if not main:
        return {}
    r = subprocess.run(["journalctl", "--user", f"_PID={main}", "-n", str(limit), "-o", "json", "--no-pager",
                        "--output-fields=MESSAGE,__REALTIME_TIMESTAMP"], capture_output=True, text=True, stdin=subprocess.DEVNULL)
    out = {}
    for line in r.stdout.splitlines():
        try:
            e = json.loads(line)
        except ValueError:
            continue
        msg = e.get("MESSAGE")
        if isinstance(msg, list):          # с цветовыми кодами journald отдаёт сообщение массивом байтов
            msg = bytes(msg).decode(errors="replace")
        if not isinstance(msg, str):
            continue
        msg = ANSI.sub("", msg).strip()
        if not re.match(r"(WARN|ERROR|CRIT)", msg):
            continue
        m = FILE_OWNER.search(msg)
        owner = ("widget-" if m.group(1) == "widgets" else "") + m.group(2) if m else None
        if not owner:
            m = LOG_OWNER.search(msg)
            owner = m.group(1) if m else None
        if not owner or owner.startswith("api."):   # «glide-shell: api.exec: …» — ошибка внутри обратного вызова, без имени
            continue
        text = re.sub(r"^(WARN|ERROR|CRIT)\s+(scene|qml)?:?\s*", "", msg)
        text = re.sub(r"file://\S*?/((?:plugins|widgets)/[^?\s]+)(\?v=\d+)?", r"\1", text)[:300]
        o = out.setdefault(owner, {"count": 0, "last": []})
        o["count"] += 1
        o["last"] = (o["last"] + [{"time": int(e.get("__REALTIME_TIMESTAMP", 0)) // 1000, "text": text}])[-5:]
    return out


def kill(pid):
    main, _ = main_pid()
    if pid == main or pid not in cgroup_procs():
        return {"ok": False, "error": "не процесс службы"}
    try:
        os.kill(pid, 15)
        return {"ok": True}
    except OSError as e:
        return {"ok": False, "error": str(e)}


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "errors":
        print(json.dumps(errors(), ensure_ascii=False))
    elif len(sys.argv) > 2 and sys.argv[1] == "kill":
        print(json.dumps(kill(int(sys.argv[2])), ensure_ascii=False))
    else:
        print(json.dumps(collect(), ensure_ascii=False))
