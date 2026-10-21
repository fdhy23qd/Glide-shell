#!/usr/bin/env python3
"""Свои виджеты рабочего стола: ~/.config/glide-shell/widgets/<id>/{widget.json, widget.qml}.

    glide-widgets.py list   → [{"id", "dir", "name", "icon", "description", "settings", "mtime", "error"}]

widget.json: {"name": "…", "icon": "F0954" (код значка MDI, необязательно), "description": "…",
              "settings": [{"key", "type": "text|toggle|choice", "label", "default", "options": [{"label","value"}]}],
              "stats": true — нужны api.cpu и api.mem (опрос /proc раз в 2 с, только пока такой виджет есть)}
mtime — для перезагрузки после правки файла; error — что не так с widget.json (виджет всё равно в списке).
"""
import json
import os
from pathlib import Path

root = Path(os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config") / "glide-shell" / "widgets"
out = []
if root.is_dir():
    for d in sorted(p for p in root.iterdir() if p.is_dir()):
        qml = d / "widget.qml"
        if not qml.is_file():
            continue
        item = {"id": d.name, "dir": str(d), "name": d.name, "icon": "", "description": "", "settings": [],
                "mtime": int(max(qml.stat().st_mtime, (d / "widget.json").stat().st_mtime if (d / "widget.json").exists() else 0))}
        try:
            meta = json.loads((d / "widget.json").read_text()) if (d / "widget.json").exists() else {}
            item["name"] = str(meta.get("name") or d.name)
            item["icon"] = str(meta.get("icon") or "")
            item["description"] = str(meta.get("description") or "")
            item["settings"] = [s for s in meta.get("settings") or [] if isinstance(s, dict) and s.get("key")]
            item["stats"] = bool(meta.get("stats"))
        except Exception as e:
            item["error"] = f"widget.json: {e}"
        out.append(item)
print(json.dumps(out, ensure_ascii=False))
