#!/usr/bin/env python3
"""Файлы плагина для api.files (docs/API.md, раздел 3): только своя папка, без подпапок.

    qp-files.py read DIR NAME      → содержимое файла в stdout (код 1 — нет файла)
    qp-files.py write DIR NAME     ← строка JSON в stdin (так пустой текст тоже передаётся); запись атомарная
    qp-files.py list DIR           → [{"name", "size", "mtime"}] JSON
    qp-files.py remove DIR NAME

DIR — ~/.local/share/glide-shell/plugin-data/<id> (создаётся при первой записи). NAME — латиница, цифры, «_», «.»
и «-», не с точки и не на «.tmp», до 128 знаков: «..», «/» и скрытые файлы не проходят.
"""
import json
import os
import re
import sys
from pathlib import Path

NAME = re.compile(r"[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}")
LIMIT = 16 * 1024 * 1024   # больше — не хранилище, а склад: пусть плагин пишет куда-нибудь сам


def target(d, name):
    if not NAME.fullmatch(name) or name.endswith(".tmp"):
        sys.exit(f"qp-files: плохое имя файла: {name!r}")
    return Path(d) / name


def main(a):
    if len(a) < 2 or a[0] not in ("read", "write", "list", "remove") or (a[0] != "list" and len(a) < 3):
        sys.exit(__doc__)
    op, d = a[0], Path(a[1])
    if op == "list":
        out = []
        if d.is_dir():
            for f in sorted(d.iterdir()):
                if f.is_file() and NAME.fullmatch(f.name) and not f.name.endswith(".tmp"):
                    st = f.stat()
                    out.append({"name": f.name, "size": st.st_size, "mtime": int(st.st_mtime * 1000)})
        print(json.dumps(out, ensure_ascii=False))
        return
    f = target(d, a[2])
    if op == "read":
        try:
            sys.stdout.write(f.read_text(errors="replace"))
        except OSError as e:
            sys.exit(f"qp-files: {e.strerror or e}")
    elif op == "write":
        text = json.loads(sys.stdin.read() or '""')
        if not isinstance(text, str):
            sys.exit("qp-files: ждал строку")
        if len(text.encode()) > LIMIT:
            sys.exit("qp-files: больше 16 МБ")
        d.mkdir(parents=True, exist_ok=True)
        tmp = f.with_name(f.name + ".tmp")
        tmp.write_text(text)
        os.replace(tmp, f)
    else:
        try:
            f.unlink()
        except FileNotFoundError:
            pass


if __name__ == "__main__":
    main(sys.argv[1:])
