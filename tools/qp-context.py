#!/usr/bin/env python3
"""Снимок контекста в момент вызова панели: активное окно (niri), выделение, буфер обмена."""
import json, subprocess, time

LIMIT = 20000
TIMEOUT = 0.6

CMDS = {
    "window": ["niri", "msg", "-j", "focused-window"],
    "selection": ["wl-paste", "--primary", "--no-newline", "--type", "text"],
    "clipboard": ["wl-paste", "--no-newline", "--type", "text"],
}

# Запускаем всё сразу: панель ждёт этот скрипт перед показом, последовательно было бы до 3×TIMEOUT.
procs = {}
for k, argv in CMDS.items():
    try:
        procs[k] = subprocess.Popen(argv, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    except OSError:
        pass

deadline = time.monotonic() + TIMEOUT
out = {}
for k, p in procs.items():
    try:
        data, _ = p.communicate(timeout=max(0.01, deadline - time.monotonic()))
        out[k] = data if p.returncode == 0 else b""
    except subprocess.TimeoutExpired:
        p.kill()
        out[k] = b""

win = None
try:
    raw = out.get("window", b"")
    win = json.loads(raw) if raw.strip() else None
except ValueError:
    pass

def text(k):
    return out.get(k, b"").decode("utf-8", "replace")[:LIMIT]

print(json.dumps({"window": win, "selection": text("selection"), "clipboard": text("clipboard")},
                 ensure_ascii=False))
