#!/usr/bin/env python3
"""Быстрые переключатели: list — состояние, toggle — переключить ($QP_TEXT: wifi | bt | awake)."""
import os, shutil, subprocess, sys
from pathlib import Path

# «не засыпать» ведёт ядро Glide Shell; здесь — только чтение состояния и команда ядру
AWAKE = Path(os.environ.get("XDG_STATE_HOME") or Path.home() / ".local/state") / "glide-shell" / "awake"


def out(argv):
    try:
        return subprocess.run(argv, capture_output=True, text=True, timeout=3).stdout
    except (OSError, subprocess.TimeoutExpired):
        return ""


def wifi():
    return out(["nmcli", "radio", "wifi"]).strip() == "enabled"


def bt():
    return "Powered: yes" in out(["bluetoothctl", "show"])


def awake():
    try:
        return AWAKE.read_text().strip() == "1"
    except OSError:
        return False


def row(key, on, name):
    print(f"{key}\t{'◉' if on else '○'}  {name}: {'вкл' if on else 'выкл'}")


cmd = sys.argv[1] if len(sys.argv) > 1 else "list"
if cmd == "list":
    if shutil.which("nmcli"):
        row("wifi", wifi(), "Wi-Fi")
    if shutil.which("bluetoothctl"):
        row("bt", bt(), "Bluetooth")
    row("awake", awake(), "Не засыпать")
elif cmd == "toggle":
    what = os.environ.get("QP_TEXT", "")
    if what == "wifi":
        subprocess.run(["nmcli", "radio", "wifi", "off" if wifi() else "on"])
    elif what == "bt":
        subprocess.run(["bluetoothctl", "power", "off" if bt() else "on"], capture_output=True)
    elif what == "awake":
        subprocess.run(["qs", "-c", "glide-shell", "ipc", "call", "panel", "awake", "toggle"], capture_output=True)
