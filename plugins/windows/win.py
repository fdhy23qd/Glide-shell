#!/usr/bin/env python3
"""Окна niri: list — все окна (текущее помечено), focus — перейти к окну с id из $QP_TEXT."""
import json, os, subprocess, sys

cmd = sys.argv[1] if len(sys.argv) > 1 else "list"
if cmd == "list":
    try:
        out = subprocess.run(["niri", "msg", "-j", "windows"], capture_output=True, text=True, timeout=2).stdout
        wins = json.loads(out)
    except (OSError, ValueError, subprocess.TimeoutExpired):
        wins = []
    # окно, из которого вызвали панель, — в конец: к нему и так вернёмся по Esc
    wins.sort(key=lambda w: (w.get("is_focused", False), w.get("workspace_id") or 0))
    for w in wins:
        title = (w.get("title") or "").replace("\t", " ")
        app = w.get("app_id") or "?"
        mark = "● " if w.get("is_focused") else ""
        print(f"{w['id']}\t{mark}{title or app}  ·  {app}")
elif cmd == "focus":
    subprocess.run(["niri", "msg", "action", "focus-window", "--id", os.environ.get("QP_TEXT", "")])
