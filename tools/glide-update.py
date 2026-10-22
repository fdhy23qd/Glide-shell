#!/usr/bin/env python3
"""Обновления Glide Shell и приложений Glide — из git-папки, откуда их поставили (её запоминают install.sh).

    glide-update.py status [--fetch]   — JSON: {shell: {...}, apps: {...}}; --fetch — сначала git fetch
    glide-update.py apply shell|apps   — git pull --ff-only и install.sh в фоне (systemd-run); итог — в update.json
    glide-update.py ack                — итог прочитан (оболочка показала уведомление)

Обновляет только «чистую» папку: без своих правок и своих коммитов (иначе — вручную). install.sh оболочки
перезапускает её сам и возвращает прежнюю версию, если новая не загрузилась.
Для проверок: GLIDE_UPDATE_INSTALL — команда установки вместо «sh install.sh», GLIDE_UPDATE_INLINE=1 — без systemd-run.
"""
import json
import os
import re
import subprocess
import sys
import time
from pathlib import Path

STATE = Path(os.environ.get("XDG_STATE_HOME") or Path.home() / ".local/state") / "glide-shell"
RESULT = STATE / "update.json"
SOURCES = {"shell": STATE / "source", "apps": STATE / "apps-source"}
VERSION = re.compile(r"Glide Shell (v\d+(?:\.\d+)+)")


def git(src, *args, timeout=30):
    r = subprocess.run(["git", "-C", str(src), *args], capture_output=True, text=True, timeout=timeout,
                       stdin=subprocess.DEVNULL, env=dict(os.environ, GIT_TERMINAL_PROMPT="0"))
    return r.returncode, r.stdout.strip(), r.stderr.strip()


def source(name):
    try:
        return Path(SOURCES[name].read_text().strip())
    except OSError:
        return None


def version_at(src, rev):
    code, text, _ = git(src, "show", f"{rev}:shell.qml")
    m = VERSION.search(text) if code == 0 else None
    return m.group(1) if m else ""


def changelog_since(src, rev, current):
    """Записи CHANGELOG.md в rev выше записи текущей версии (первая строка каждой, без разметки)."""
    code, text, _ = git(src, "show", f"{rev}:CHANGELOG.md")
    if code != 0:
        return []
    out = []
    for line in text.splitlines():
        m = re.match(r"- \*\*(v[\d.]+)\*\* — (.*)", line)
        if not m:
            continue
        if m.group(1) == current:
            break
        out.append(f"{m.group(1)} — {m.group(2)}")
    return out


def running(name):
    r = subprocess.run(["systemctl", "--user", "is-active", "--quiet", f"glide-update-{name}"],
                       stdin=subprocess.DEVNULL, capture_output=True)
    return r.returncode == 0


def status(name, fetch):
    src = source(name)
    out = {"source": str(src or ""), "git": False, "running": running(name)}
    if not src or not (src / ".git").exists():
        return out
    out["git"] = True
    if fetch:
        code, _, err = git(src, "fetch", "--quiet", timeout=90)
        if code != 0:
            out["error"] = err.splitlines()[-1] if err else "git fetch"
    code, upstream, _ = git(src, "rev-parse", "--abbrev-ref", "@{u}")
    if code != 0:   # своя папка без удалённого репозитория — проверять негде, это не ошибка
        out.pop("error", None)
        out["local"] = True
        return out
    _, behind, _ = git(src, "rev-list", "--count", "HEAD..@{u}")
    _, ahead, _ = git(src, "rev-list", "--count", "@{u}..HEAD")
    _, dirty, _ = git(src, "status", "--porcelain", "--untracked-files=no")
    out.update(upstream=upstream, behind=int(behind or 0), ahead=int(ahead or 0), dirty=bool(dirty))
    if name == "shell":
        out["current"] = version_at(src, "HEAD")
        out["latest"] = version_at(src, "@{u}")
        out["changes"] = changelog_since(src, "@{u}", out["current"]) if out["behind"] else []
    else:
        _, head, _ = git(src, "rev-parse", "--short", "HEAD")
        _, latest, _ = git(src, "rev-parse", "--short", "@{u}")
        out["current"], out["latest"] = head, latest
        _, log, _ = git(src, "log", "--format=%s", "HEAD..@{u}")
        out["changes"] = [l for l in log.splitlines() if l][:20]
    out["canUpdate"] = out["behind"] > 0 and out["ahead"] == 0 and not out["dirty"] and not out["running"]
    out["checked"] = int(time.time())
    return out


def write_result(data):
    STATE.mkdir(parents=True, exist_ok=True)
    tmp = RESULT.with_suffix(".tmp")
    tmp.write_text(json.dumps(data, ensure_ascii=False))
    os.replace(tmp, RESULT)


def run(name):
    """Сама работа (в своём юните systemd: переживает перезапуск оболочки, которую делает install.sh)."""
    src = source(name)
    before = version_at(src, "HEAD") if name == "shell" else git(src, "rev-parse", "--short", "HEAD")[1]
    log = STATE / f"update-{name}.log"
    res = {"component": name, "from": before, "started": int(time.time()), "ok": False, "shown": False}
    with open(log, "w") as f:
        steps = [["git", "-C", str(src), "pull", "--ff-only"],
                 ["sh", "-c", os.environ.get("GLIDE_UPDATE_INSTALL", "sh install.sh")]]
        for cmd in steps:
            f.write("$ " + " ".join(cmd) + "\n"); f.flush()
            r = subprocess.run(cmd, cwd=src, stdout=f, stderr=subprocess.STDOUT, stdin=subprocess.DEVNULL,
                               env=dict(os.environ, GIT_TERMINAL_PROMPT="0"))
            if r.returncode != 0:
                tail = [l for l in log.read_text(errors="replace").splitlines() if l.strip()][-3:]
                res["error"] = " / ".join(tail) or f"код {r.returncode}"
                break
        else:
            res["ok"] = True
    res["to"] = version_at(src, "HEAD") if name == "shell" else git(src, "rev-parse", "--short", "HEAD")[1]
    res["finished"] = int(time.time())
    write_result(res)
    return res


def apply(name):
    st = status(name, False)
    if not st.get("canUpdate"):
        return {"ok": False, "error": "нечего обновлять или есть свои правки"}
    write_result({"component": name, "started": int(time.time()), "running": True, "shown": True})
    if os.environ.get("GLIDE_UPDATE_INLINE") == "1":
        return run(name)
    unit = f"glide-update-{name}"
    subprocess.run(["systemctl", "--user", "reset-failed", unit], capture_output=True, stdin=subprocess.DEVNULL)
    r = subprocess.run(["systemd-run", "--user", "--collect", "--quiet", f"--unit={unit}",
                        sys.executable, "-I", os.path.abspath(__file__), "_run", name],
                       capture_output=True, text=True, stdin=subprocess.DEVNULL)
    return {"ok": r.returncode == 0, "error": r.stderr.strip()}


def main():
    a = sys.argv[1:]
    if not a or a[0] == "status":
        fetch = "--fetch" in a
        print(json.dumps({n: status(n, fetch) for n in SOURCES}, ensure_ascii=False))
    elif a[0] == "apply" and len(a) == 2 and a[1] in SOURCES:
        print(json.dumps(apply(a[1]), ensure_ascii=False))
    elif a[0] == "_run" and len(a) == 2:
        run(a[1])
    elif a[0] == "ack":
        try:
            d = json.loads(RESULT.read_text()); d["shown"] = True; write_result(d)
        except (OSError, ValueError):
            pass
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
