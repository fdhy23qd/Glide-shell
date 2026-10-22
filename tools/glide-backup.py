#!/usr/bin/env python3
"""Резервная копия настроек Glide Shell — одним архивом (для переноса на другой компьютер).

    glide-backup.py export [ПАПКА]   — ~/glide-shell-settings-ГГГГММДД-ЧЧММ.tar.gz (или в ПАПКУ); печатает путь
    glide-backup.py import ФАЙЛ      — восстановить; текущие настройки сначала сохраняются рядом (…-before-import)
    glide-backup.py list             — найденные копии в домашней папке (JSON)

В архиве: ~/.config/glide-shell (config.json, свои плагины и виджеты) и настройки niri из «Устройств»
(glide-settings.kdl, glide-outputs.kdl). Не входят — личное: история буфера, уведомления, чат ИИ, ключи.
"""
import json
import os
import sys
import tarfile
import time
from pathlib import Path

HOME = Path.home()
CFG = Path(os.environ.get("XDG_CONFIG_HOME") or HOME / ".config")
SHELL = CFG / "glide-shell"
NIRI = CFG / "niri"
SKIP = {"anthropic-key"}          # ключи — никогда


def members():
    out = []
    if SHELL.is_dir():
        for p in sorted(SHELL.rglob("*")):
            if p.is_file() and p.name not in SKIP and "__pycache__" not in p.parts:
                out.append((p, "glide-shell/" + str(p.relative_to(SHELL))))
    for name in ("glide-settings.kdl", "glide-outputs.kdl"):
        if (NIRI / name).is_file():
            out.append((NIRI / name, "niri/" + name))
    return out


def export(folder=None, suffix=""):
    dest = Path(folder) if folder else HOME
    dest.mkdir(parents=True, exist_ok=True)
    path = dest / time.strftime("glide-shell-settings-%Y%m%d-%H%M" + ("%S" + suffix if suffix else "") + ".tar.gz")
    with tarfile.open(path, "w:gz") as t:
        for src, arc in members():
            t.add(src, arcname=arc)
    os.chmod(path, 0o600)
    return str(path)


def safe(name):
    return not (name.startswith("/") or ".." in Path(name).parts) and name.split("/")[0] in ("glide-shell", "niri")


def restore(file):
    with tarfile.open(file, "r:gz") as t:          # сначала прочитать: копия «до» не должна задеть этот файл
        t.getmembers()
    export(HOME, "-before-import")                 # откат: текущие настройки — рядом, своим именем (с секундами)
    with tarfile.open(file, "r:gz") as t:
        items = [m for m in t.getmembers() if m.isfile() and safe(m.name)]
        if not items:
            raise SystemExit("в архиве нет настроек Glide Shell")
        for m in items:
            top, rest = m.name.split("/", 1)
            target = (SHELL if top == "glide-shell" else NIRI) / rest
            target.parent.mkdir(parents=True, exist_ok=True)
            data = t.extractfile(m).read()
            tmp = target.with_suffix(target.suffix + ".tmp")
            tmp.write_bytes(data)
            os.chmod(tmp, 0o600 if target.name == "config.json" else 0o644)
            os.replace(tmp, target)
    return len(items)


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else ""
    if cmd == "export":
        print(export(sys.argv[2] if len(sys.argv) > 2 else None))
    elif cmd == "import" and len(sys.argv) > 2:
        print(json.dumps({"ok": True, "files": restore(sys.argv[2])}))
    elif cmd == "list":
        found = sorted(HOME.glob("glide-shell-settings-*.tar.gz"), reverse=True)
        print(json.dumps([{"path": str(p), "name": p.name, "size": p.stat().st_size} for p in found[:10]], ensure_ascii=False))
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
