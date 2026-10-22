#!/usr/bin/env python3
"""Приложения при входе (стандартный XDG-автозапуск, как в GNOME/KDE) — для «Устройств» в Glide Shell.

    glide-autostart.py list               — JSON: [{file, name, icon, exec, enabled, mine, system}]
    glide-autostart.py set FILE on|off     — включить/выключить (системные — своей копией с Hidden=true)
    glide-autostart.py add DESKTOP_ID      — добавить приложение (копия его .desktop в ~/.config/autostart)
    glide-autostart.py remove FILE         — убрать своё (системное — только выключить)

Читает /etc/xdg/autostart и ~/.config/autostart (своё перекрывает системное с тем же именем); показывает только то,
что запускается в этом сеансе (OnlyShowIn/NotShowIn по $XDG_CURRENT_DESKTOP). Запуск делает systemd
(systemd-xdg-autostart-generator) — после правки изменения действуют со следующего входа.
"""
import configparser
import json
import os
import sys
from pathlib import Path

HOME = Path.home()
USER = Path(os.environ.get("XDG_CONFIG_HOME") or HOME / ".config") / "autostart"
SYSTEM = [Path(d) / "autostart" for d in (os.environ.get("XDG_CONFIG_DIRS") or "/etc/xdg").split(":")]
APPS = [Path(os.environ.get("XDG_DATA_HOME") or HOME / ".local/share") / "applications"] + \
       [Path(d) / "applications" for d in (os.environ.get("XDG_DATA_DIRS") or "/usr/local/share:/usr/share").split(":")]
DESKTOPS = [d.lower() for d in (os.environ.get("XDG_CURRENT_DESKTOP") or "").split(":") if d]


def read(path):
    cp = configparser.RawConfigParser(strict=False, interpolation=None)
    cp.optionxform = str
    try:
        cp.read(path, encoding="utf-8")
        return dict(cp["Desktop Entry"]) if cp.has_section("Desktop Entry") else {}
    except (configparser.Error, OSError, UnicodeDecodeError):
        return {}


def name_of(e):
    lang = (os.environ.get("LANG") or "").split(".")[0]
    return e.get(f"Name[{lang}]") or e.get(f"Name[{lang.split('_')[0]}]") or e.get("Name") or ""


def applies(e):
    only = [x.lower() for x in e.get("OnlyShowIn", "").split(";") if x]
    never = [x.lower() for x in e.get("NotShowIn", "").split(";") if x]
    if only and not any(d in only for d in DESKTOPS):
        return False
    return not any(d in never for d in DESKTOPS)


def enabled(e):
    return e.get("Hidden", "false").lower() != "true" and e.get("X-GNOME-Autostart-enabled", "true").lower() != "false"


def entries():
    found = {}
    for d in SYSTEM:
        if d.is_dir():
            for p in sorted(d.glob("*.desktop")):
                found.setdefault(p.name, {"system": p, "user": None})
    if USER.is_dir():
        for p in sorted(USER.glob("*.desktop")):
            found.setdefault(p.name, {"system": None, "user": None})["user"] = p
    out = []
    for name, f in sorted(found.items()):
        e = read(f["user"] or f["system"])
        if not e or not applies(e) or e.get("Type", "Application") != "Application":
            continue
        out.append({"file": name, "name": name_of(e) or name[:-8], "icon": e.get("Icon", ""), "exec": e.get("Exec", ""),
                    "enabled": enabled(e), "mine": f["user"] is not None and f["system"] is None, "system": f["system"] is not None})
    out.sort(key=lambda x: (not x["mine"], x["name"].lower()))
    return out


def write(path, entry_lines):
    USER.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(".tmp")
    tmp.write_text("\n".join(entry_lines) + "\n")
    os.replace(tmp, path)


def set_enabled(file, on):
    user, system = USER / file, next((d / file for d in SYSTEM if (d / file).exists()), None)
    src = user if user.exists() else system
    if src is None:
        sys.exit("нет такого: " + file)
    lines = [l for l in src.read_text(errors="replace").splitlines()
             if not l.startswith("Hidden=") and not l.startswith("X-GNOME-Autostart-enabled=")]
    if not on:
        i = next((k for k, l in enumerate(lines) if l.strip() == "[Desktop Entry]"), 0)
        lines.insert(i + 1, "Hidden=true")
    write(user, lines)


def add(desktop_id):
    for d in APPS:
        p = d / desktop_id
        if p.exists():
            write(USER / desktop_id, [l for l in p.read_text(errors="replace").splitlines() if not l.startswith("Hidden=")])
            return
    sys.exit("приложение не найдено: " + desktop_id)


def remove(file):
    p = USER / file
    if any((d / file).exists() for d in SYSTEM):
        set_enabled(file, False)            # системное не удалить — только выключить
    elif p.exists():
        p.unlink()


def main():
    a = sys.argv[1:]
    if not a or a[0] == "list":
        print(json.dumps(entries(), ensure_ascii=False))
    elif a[0] == "set" and len(a) == 3:
        set_enabled(a[1], a[2] == "on")
    elif a[0] == "add" and len(a) == 2:
        add(a[1])
    elif a[0] == "remove" and len(a) == 2:
        remove(a[1])
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
