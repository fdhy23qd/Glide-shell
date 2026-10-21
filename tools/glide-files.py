#!/usr/bin/env python3
"""Поиск файлов для панели Glide Shell — без plocate и root: свой индекс домашней папки.

    glide-files.py serve          — держать индекс в памяти: на каждую строку stdin (запрос) — строка JSON
                                    {"q": запрос, "items": [{"path", "name", "dir", "isdir"}]}
    glide-files.py search ЗАПРОС  — один поиск (для проверки и тестов)
    glide-files.py index          — пересобрать индекс

Индекс — ~/.cache/glide-shell/files.tsv (путь<TAB>mtime<TAB>d|f, права 0600), пересобирается в фоне, если старше
30 минут (обход домашней папки на HDD — секунды, поэтому редко и с низким приоритетом). Скрытые файлы и папки,
node_modules, venv, сборки и кэши не индексируются. Найти — все слова запроса в имени; выше — имя начинается
с первого слова, папки и недавние файлы.
"""
import json
import os
import sys
import threading
import time
from pathlib import Path

HOME = Path(os.environ.get("GLIDE_FILES_ROOT") or Path.home())
CACHE = Path(os.environ.get("XDG_CACHE_HOME") or Path.home() / ".cache") / "glide-shell"
INDEX = CACHE / "files.tsv"
FRESH = 30 * 60
LIMIT = 300_000
SKIP = {"node_modules", "__pycache__", "venv", "env", "build", "dist", "target", "CMakeFiles",
        "site-packages", "steamapps", "Steam", "snap", "go", "cargo"}


def build():
    """Обойти домашнюю папку; записать индекс атомарно (tmp → rename)."""
    rows, stack = [], [str(HOME)]
    while stack and len(rows) < LIMIT:
        d = stack.pop()
        try:
            it = os.scandir(d)
        except OSError:
            continue
        with it:
            for e in it:
                if e.name.startswith("."):
                    continue
                try:
                    isdir = e.is_dir(follow_symlinks=False)
                    mt = int(e.stat(follow_symlinks=False).st_mtime)
                except OSError:
                    continue
                rows.append(f"{e.path}\t{mt}\t{'d' if isdir else 'f'}")
                if isdir and e.name not in SKIP:
                    stack.append(e.path)
    CACHE.mkdir(parents=True, exist_ok=True)
    tmp = INDEX.with_suffix(".tmp")
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as f:
        f.write("\n".join(rows))
    os.replace(tmp, INDEX)
    return len(rows)


def load():
    out = []
    try:
        for line in INDEX.read_text(errors="replace").splitlines():
            p, _, rest = line.partition("\t")
            mt, _, kind = rest.partition("\t")
            name = p.rsplit("/", 1)[-1]
            out.append((name.lower(), p, int(mt or 0), kind == "d"))
    except OSError:
        pass
    return out


def search(entries, q, n=8):
    words = q.lower().split()
    if not words or len(q.strip()) < 2:
        return []
    now = time.time()
    scored = []
    for low, p, mt, isdir in entries:
        if not all(w in low for w in words):
            continue
        s = 0
        if low.startswith(words[0]):
            s += 100
        if low == q.lower().strip() or low.rsplit(".", 1)[0] == q.lower().strip():
            s += 60
        if isdir:
            s += 15
        age = now - mt
        if age < 7 * 86400:
            s += 30
        elif age < 60 * 86400:
            s += 10
        s -= p.count("/")          # чем глубже, тем ниже
        scored.append((s, p, isdir))
    scored.sort(key=lambda x: -x[0])
    home = str(Path.home())
    items = []
    for _, p, isdir in scored[:n]:
        parent = p.rsplit("/", 1)[0]
        items.append({"path": p, "name": p.rsplit("/", 1)[-1], "isdir": isdir,
                      "dir": "~" + parent[len(home):] if parent.startswith(home) else parent})
    return items


def stale():
    try:
        return time.time() - INDEX.stat().st_mtime > FRESH
    except OSError:
        return True


def serve():
    state = {"entries": load()}

    def refresh():
        while True:
            if stale():
                try:
                    build()
                    state["entries"] = load()
                except Exception as e:   # индекс не обязателен — поиск просто пустой
                    print(json.dumps({"error": str(e)}), file=sys.stderr, flush=True)
            time.sleep(300)

    threading.Thread(target=refresh, daemon=True).start()
    for line in sys.stdin:
        q = line.rstrip("\n")
        print(json.dumps({"q": q, "items": search(state["entries"], q)}, ensure_ascii=False), flush=True)


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else "serve"
    if cmd == "index":
        print(build())
    elif cmd == "search":
        if stale():
            build()
        print(json.dumps(search(load(), " ".join(sys.argv[2:])), ensure_ascii=False, indent=1))
    else:
        serve()


if __name__ == "__main__":
    main()
