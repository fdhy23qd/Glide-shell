#!/usr/bin/env python3
"""Обновления Arch Linux для бара Glide Shell.

    glide-archupdates.py check     — проверить; JSON печатается и пишется в ~/.local/state/glide-shell/archupdates.json
    glide-archupdates.py upgrade   — терминал с обновлением (yay/paru -Syu или sudo pacman -Syu), потом снова check

Проверка ничего в системе не меняет: как checkupdates (pacman-contrib) — свежие базы скачиваются в свою папку
(~/.cache/glide-shell/pacman-db, fakeroot), локальная база — ссылкой. Есть checkupdates — берётся он.
AUR — через yay -Qua / paru -Qua, если они стоят.
"""
import json
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path

STATE = Path(os.environ.get("XDG_STATE_HOME") or Path.home() / ".local/state") / "glide-shell"
RESULT = STATE / "archupdates.json"
DB = Path(os.environ.get("XDG_CACHE_HOME") or Path.home() / ".cache") / "glide-shell" / "pacman-db"
PACMAN_DB = Path(os.environ.get("GLIDE_PACMAN_DB", "/var/lib/pacman"))
TERMINALS = [("alacritty", ["-e"]), ("foot", []), ("kitty", []), ("ghostty", ["-e"]), ("wezterm", ["start", "--"]),
             ("konsole", ["-e"]), ("gnome-terminal", ["--"]), ("xterm", ["-e"])]


def run(cmd, timeout=180):
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout, stdin=subprocess.DEVNULL,
                           env=dict(os.environ, LC_ALL="C"))
        return r.returncode, r.stdout, r.stderr
    except (OSError, subprocess.TimeoutExpired) as e:
        return -1, "", str(e)


def parse(text):
    """«имя 1.0-1 -> 1.1-1» → [{name, from, to}]"""
    out = []
    for line in text.splitlines():
        p = line.split()
        if len(p) >= 4 and p[2] == "->":
            out.append({"name": p[0], "from": p[1], "to": p[3]})
    return out


def helper():
    return next((h for h in ("paru", "yay") if shutil.which(h)), "")


def repo_updates():
    if shutil.which("checkupdates"):
        code, out, err = run(["checkupdates"])
        if code in (0, 2):              # 2 — обновлений нет
            return parse(out), ""
        return [], (err.strip().splitlines() or ["checkupdates"])[-1]
    if not shutil.which("fakeroot"):
        return [], "нужен pacman-contrib (checkupdates) или fakeroot"
    DB.mkdir(parents=True, exist_ok=True)
    local = DB / "local"
    if not local.is_symlink():
        if local.exists():
            shutil.rmtree(local)
        local.symlink_to(PACMAN_DB / "local")
    # pacman 7 качает от пользователя alpm — под fakeroot переключиться нельзя, песочницу загрузчика выключаем
    sandbox = ["--disable-sandbox"] if "--disable-sandbox" in run(["pacman", "-S", "--help"], 10)[1] else []
    code, _, err = run(["fakeroot", "--", "pacman", "-Sy", *sandbox, "--dbpath", str(DB), "--logfile", "/dev/null"])
    if code != 0 and not any((DB / "sync").glob("*.db")):   # отдельные зеркала не ответили — не беда, если базы есть
        return [], (err.strip().splitlines() or ["pacman -Sy"])[-1]
    code, out, _ = run(["pacman", "-Qu", "--dbpath", str(DB)])
    return parse(out), ""


def check():
    if not shutil.which("pacman"):
        res = {"supported": False}
    else:
        repo, err = repo_updates()
        aur = []
        h = helper()
        if h:
            code, out, _ = run([h, "-Qua"], timeout=120)
            aur = parse(out)
        res = {"supported": True, "repo": repo, "aur": aur, "count": len(repo) + len(aur), "helper": h,
               "error": err, "checked": int(time.time())}
    STATE.mkdir(parents=True, exist_ok=True)
    tmp = RESULT.with_suffix(".tmp")
    tmp.write_text(json.dumps(res, ensure_ascii=False))
    os.replace(tmp, RESULT)
    return res


def upgrade():
    h = helper()
    cmd = f"{h} -Syu" if h else "sudo pacman -Syu"
    script = (f'echo "Glide Shell: {cmd}"; echo; {cmd}; echo; '
              'printf "Готово. Enter — закрыть окно "; read -r _')
    term = os.environ.get("TERMINAL", "")
    found = [(t, a) for t, a in TERMINALS if t == term] + [(t, a) for t, a in TERMINALS if shutil.which(t)]
    if not found:
        sys.exit("не найден терминал (alacritty, foot, kitty…)")
    t, args = found[0]
    subprocess.run([t, *args, "sh", "-c", script], stdin=subprocess.DEVNULL)
    check()


def main():
    a = sys.argv[1] if len(sys.argv) > 1 else "check"
    if a == "check":
        print(json.dumps(check(), ensure_ascii=False))
    elif a == "upgrade":
        upgrade()
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
