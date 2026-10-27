#!/usr/bin/env python3
"""История буфера: текст и картинки. Подкоманды: store, list, json, copy (id в $QP_TEXT), pin/unpin/del ID, clear.

Закреплённые — clipboard-pins.json (так же 0600): лимиты истории их не вытесняют, «очистить» не трогает.

store зовёт `wl-paste --watch` при каждой смене буфера; что в нём лежит, узнаём сами
(`wl-paste --list-types`): текст — в clipboard.json, картинка — файлом в clipboard-img/ (0600),
а в историю — запись {"img": имя, "type": mime, "w", "h"}. Пароли из менеджеров не сохраняются.
"""
import hashlib, json, os, struct, subprocess, sys, time
from pathlib import Path

MAX_ITEMS, MAX_BYTES, MAX_IMAGE, MAX_IMAGES = 100, 100_000, 15_000_000, 20
state = Path(os.environ.get("XDG_STATE_HOME") or Path.home() / ".local/state") / "glide-shell"
store = state / "clipboard.json"
pins_file = state / "clipboard-pins.json"
imgdir = state / "clipboard-img"
IMAGE_TYPES = ("image/png", "image/jpeg", "image/webp", "image/gif", "image/bmp")
# разовая метка «не запоминать» (sha256 текста): её оставляет генератор паролей (plugins/devtools), живёт 30 с
SKIP = Path(os.environ.get("XDG_RUNTIME_DIR") or "/nonexistent") / "glide-shell-clip-skip"


def load():
    try:
        return [x for x in json.loads(store.read_text()) if isinstance(x, (str, dict))]
    except (OSError, ValueError):
        return []


def load_pins():
    try:
        return [x for x in json.loads(pins_file.read_text()) if isinstance(x, (str, dict))]
    except (OSError, ValueError):
        return []


def save_pins(pins):
    state.mkdir(parents=True, exist_ok=True)
    tmp = pins_file.with_suffix(".tmp")
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as f:
        json.dump(pins, f, ensure_ascii=False)
    os.replace(tmp, pins_file)


def key(item):   # стабильный id записи: индекс сдвигается, если буфер изменился после показа списка
    return item["img"].split(".")[0][:16] if isinstance(item, dict) else hashlib.sha1(item.encode()).hexdigest()[:16]


def wl(*args, binary=False):
    try:
        r = subprocess.run(["wl-paste", *args], capture_output=True, timeout=3)
    except (OSError, subprocess.TimeoutExpired):
        return None
    return r.stdout if r.returncode == 0 else None


def save(items):
    state.mkdir(parents=True, exist_ok=True)
    tmp = store.with_suffix(".tmp")
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as f:
        json.dump(items, f, ensure_ascii=False)
    os.replace(tmp, store)
    # файлы картинок, которых больше нет в истории, — удаляем
    keep = {x["img"] for x in items + load_pins() if isinstance(x, dict)}   # картинки закреплённых — не трогать
    if imgdir.is_dir():
        for p in imgdir.iterdir():
            if p.name not in keep:
                p.unlink(missing_ok=True)


def size(data, mime):
    if mime == "image/png" and data[:8] == b"\x89PNG\r\n\x1a\n" and len(data) >= 24:
        return struct.unpack(">II", data[16:24])
    return (0, 0)


def remember(item, items):
    items = [x for x in items if key(x) != key(item)]
    items.insert(0, item)
    imgs = [x for x in items if isinstance(x, dict)]
    if len(imgs) > MAX_IMAGES:   # картинок держим меньше — они тяжёлые
        drop = {key(x) for x in imgs[MAX_IMAGES:]}
        items = [x for x in items if key(x) not in drop]
    save(items[:MAX_ITEMS])


cmd = sys.argv[1] if len(sys.argv) > 1 else ""
if cmd == "store":
    sys.stdin.buffer.read()   # то, что дал --watch, не нужно: тип выбираем сами
    types = (wl("--list-types") or b"").decode(errors="replace").split()
    if "x-kde-passwordManagerHint" in types:   # менеджеры паролей (KeePassXC и др.) помечают пароли
        sys.exit(0)
    text_types = [t for t in types if t.startswith("text/plain") or t in ("UTF8_STRING", "STRING", "TEXT")]
    image = next((t for t in IMAGE_TYPES if t in types), None)
    if image and not text_types:
        data = wl("--type", image, binary=True)
        if not data or len(data) > MAX_IMAGE:
            sys.exit(0)
        digest = hashlib.sha1(data).hexdigest()
        name = digest + "." + image.split("/")[1]
        imgdir.mkdir(parents=True, exist_ok=True, mode=0o700)
        path = imgdir / name
        if not path.exists():
            fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
            with os.fdopen(fd, "wb") as f:
                f.write(data)
        w, h = size(data, image)
        remember({"img": name, "type": image, "w": w, "h": h}, load())
    elif text_types:
        data = wl("--no-newline", "--type", "text")   # без -n wl-paste добавил бы перевод строки — дубли
        if not data or len(data) > MAX_BYTES:
            sys.exit(0)
        text = data.decode("utf-8", "replace")
        try:
            fresh = time.time() - SKIP.stat().st_mtime < 30
            if SKIP.read_text().strip() == hashlib.sha256(data).hexdigest() or not fresh:
                SKIP.unlink(missing_ok=True)
                if fresh:
                    sys.exit(0)
        except OSError:
            pass
        if text.strip():
            remember(text, load())
elif cmd == "list":
    for it in load():
        if isinstance(it, dict):
            if not (imgdir / it["img"]).exists():   # файл картинки пропал — запись не показываем
                continue
            dims = f" {it['w']}×{it['h']}" if it.get("w") else ""
            print(f"{key(it)}\tКартинка{dims}\t{imgdir / it['img']}")
        else:
            one = " ⏎ ".join(l.strip() for l in it.splitlines() if l.strip()).replace("\t", " ")
            print(f"{key(it)}\t{one[:120]}")
elif cmd == "json":   # для экрана буфера: закреплённые и история, у картинок — путь
    def row(it, pinned):
        if isinstance(it, dict):
            path = imgdir / it["img"]
            if not path.exists():
                return None
            return {"id": key(it), "img": str(path), "w": it.get("w", 0), "h": it.get("h", 0), "pinned": pinned}
        return {"id": key(it), "text": it[:4000], "pinned": pinned}
    pins = load_pins()
    pk = {key(x) for x in pins}
    out = [r for r in (row(x, True) for x in pins) if r] + [r for r in (row(x, False) for x in load() if key(x) not in pk) if r]
    print(json.dumps(out, ensure_ascii=False))
elif cmd in ("pin", "unpin", "del"):
    want = sys.argv[2] if len(sys.argv) > 2 else ""
    items, pins = load(), load_pins()
    if cmd == "pin":
        it = next((x for x in items if key(x) == want), None)
        if it is not None and not any(key(x) == want for x in pins):
            save_pins([it] + pins)
    elif cmd == "unpin":
        it = next((x for x in pins if key(x) == want), None)
        save_pins([x for x in pins if key(x) != want])
        if it is not None and not any(key(x) == want for x in items):
            items.insert(0, it)            # открепили — обратно в историю (сверху)
        save(items)                        # и лишние файлы картинок — прочь
    else:
        save_pins([x for x in pins if key(x) != want])
        save([x for x in items if key(x) != want])
elif cmd == "copy":
    want = os.environ.get("QP_TEXT", "") or (sys.argv[2] if len(sys.argv) > 2 else "")
    it = next((x for x in load_pins() + load() if key(x) == want), None)
    if it is None:
        sys.exit(1)
    if isinstance(it, dict):
        with open(imgdir / it["img"], "rb") as f:
            subprocess.run(["wl-copy", "--type", it["type"]], stdin=f, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    else:
        subprocess.run(["wl-copy"], input=it.encode(), stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
elif cmd == "clear":
    save([])
