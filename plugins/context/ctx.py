#!/usr/bin/env python3
import json, os, shutil, subprocess, sys

def cwd_of_focused():
    home = os.path.expanduser("~")
    try:
        pid = (json.loads(os.environ.get("QP_FOCUSED", "null")) or {}).get("pid")
    except ValueError:
        pid = None
    if not pid:
        return home
    children = {}
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        try:
            with open(f"/proc/{name}/stat") as f:
                ppid = int(f.read().rsplit(")", 1)[1].split()[1])
            children.setdefault(ppid, []).append(int(name))
        except (OSError, ValueError, IndexError):
            pass
    cur = pid
    while children.get(cur):          # эвристика: самый новый потомок ≈ шелл/программа в терминале
        cur = max(children[cur])
    for p in (cur, pid):
        try:
            return os.readlink(f"/proc/{p}/cwd")
        except OSError:
            continue
    return home

def spawn(argv, cwd):
    subprocess.Popen(argv, cwd=cwd, start_new_session=True,
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

cwd = cwd_of_focused()
action = sys.argv[1] if len(sys.argv) > 1 else "terminal"
if action == "terminal":
    term = os.environ.get("TERMINAL") or next(
        (t for t in ("foot", "kitty", "alacritty", "ghostty", "wezterm") if shutil.which(t)), None)
    if term:
        spawn([term], cwd)
elif action == "files":
    spawn(["xdg-open", cwd], cwd)
elif action == "copy":
    subprocess.run(["wl-copy"], input=cwd.encode())
