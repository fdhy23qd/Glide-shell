#!/usr/bin/env python3
"""Недавние файлы из ~/.local/share/recently-used.xbel (туда пишут приложения GTK и Qt): JSON-список, новые сверху.

[{path, name, dir, time (с 1970), mime}] — только существующие локальные файлы, не больше 300. Файл — $GLIDE_RECENT_XBEL.
"""
import json
import os
import sys
import xml.etree.ElementTree as ET
from datetime import datetime
from pathlib import Path
from urllib.parse import unquote, urlparse

XBEL = Path(os.environ.get("GLIDE_RECENT_XBEL") or Path(os.environ.get("XDG_DATA_HOME") or Path.home() / ".local/share") / "recently-used.xbel")
MIME = "{http://www.freedesktop.org/standards/shared-mime-info}mime-type"


def when(s):
    try:
        return int(datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp())
    except (ValueError, AttributeError):
        return 0


def recent(xbel=XBEL, limit=300):
    try:
        root = ET.parse(xbel).getroot()
    except (OSError, ET.ParseError):
        return []
    home, seen, out = str(Path.home()), set(), []
    for b in root.iter("bookmark"):
        u = urlparse(b.get("href", ""))
        if u.scheme != "file":
            continue
        path = unquote(u.path)
        if path in seen or not os.path.isfile(path):
            continue
        seen.add(path)
        m = b.find(".//" + MIME)
        parent = os.path.dirname(path)
        out.append({"path": path, "name": os.path.basename(path), "time": max(when(b.get("visited")), when(b.get("modified"))),
                    "dir": "~" + parent[len(home):] if parent.startswith(home) else parent,
                    "mime": m.get("type", "") if m is not None else ""})
    out.sort(key=lambda x: -x["time"])
    return out[:limit]


if __name__ == "__main__":
    print(json.dumps(recent(Path(sys.argv[1]) if len(sys.argv) > 1 else XBEL), ensure_ascii=False))
