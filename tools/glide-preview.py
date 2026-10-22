#!/usr/bin/env python3
"""Быстрый просмотр файла для поиска панели (Shift+Пробел).

    glide-preview.py ПУТЬ   — JSON: {kind, name, size, modified, image?, text?, items?, info?}

kind: image (картинка — сама, крупные — уменьшенной копией), pdf (первая страница — pdftoppm), video (кадр — ffmpeg),
text (первые ~40 строк), dir (что внутри), other. Готовые картинки — в ~/.cache/glide-shell/preview (по пути и
времени изменения): повторный просмотр мгновенный. Внешние программы — с ограничением по времени.
"""
import hashlib
import json
import os
import subprocess
import sys
from pathlib import Path

CACHE = Path(os.environ.get("XDG_CACHE_HOME") or Path.home() / ".cache") / "glide-shell" / "preview"
IMAGE = {"png", "jpg", "jpeg", "webp", "gif", "bmp", "svg", "avif", "heic", "jxl", "tif", "tiff", "ico"}
VIDEO = {"mp4", "mkv", "webm", "mov", "avi", "m4v", "wmv", "flv", "mpg", "mpeg", "ts"}
TEXT = {"txt", "md", "py", "js", "ts", "qml", "json", "c", "cpp", "h", "hpp", "rs", "go", "java", "kt", "sh", "fish",
        "toml", "yaml", "yml", "ini", "conf", "cfg", "kdl", "css", "html", "xml", "csv", "log", "sql", "lua", "rb"}


def cached(path, st, ext):
    key = hashlib.sha1(f"{path}:{st.st_mtime_ns}:{st.st_size}".encode()).hexdigest()
    CACHE.mkdir(parents=True, exist_ok=True)
    return CACHE / f"{key}.{ext}"


def run(cmd, timeout=8):
    try:
        return subprocess.run(cmd, capture_output=True, timeout=timeout, stdin=subprocess.DEVNULL).returncode == 0
    except (OSError, subprocess.TimeoutExpired):
        return False


def is_text(path):
    try:
        chunk = open(path, "rb").read(4096)
    except OSError:
        return False
    if b"\0" in chunk:
        return False
    try:
        chunk.decode("utf-8")
        return True
    except UnicodeDecodeError as e:
        return e.start > len(chunk) - 4   # оборвалась многобайтная буква на краю куска


def preview(path):
    p = Path(os.path.abspath(path))
    st = p.stat()
    out = {"name": p.name, "size": st.st_size, "modified": int(st.st_mtime), "kind": "other"}
    ext = p.suffix.lower().lstrip(".")
    if p.is_dir():
        out["kind"] = "dir"
        try:
            names = sorted(os.listdir(p), key=str.lower)
        except OSError:
            names = []
        visible = [n for n in names if not n.startswith(".")]
        out["count"] = len(visible)
        out["items"] = [n + ("/" if (p / n).is_dir() else "") for n in visible[:12]]
        return out
    if ext in IMAGE:
        out["kind"] = "image"
        out["image"] = str(p)
        return out
    if ext == "pdf":
        out["kind"] = "pdf"
        img = cached(p, st, "png")
        if img.exists() or run(["pdftoppm", "-png", "-r", "60", "-f", "1", "-l", "1", "-singlefile", str(p), str(img)[:-4]]):
            out["image"] = str(img)
        return out
    if ext in VIDEO:
        out["kind"] = "video"
        img = cached(p, st, "jpg")
        if img.exists() or run(["ffmpeg", "-v", "error", "-y", "-ss", "3", "-i", str(p), "-frames:v", "1",
                                "-vf", "scale=640:-2", str(img)]) or run(["ffmpeg", "-v", "error", "-y", "-i", str(p),
                                "-frames:v", "1", "-vf", "scale=640:-2", str(img)]):
            if img.exists():
                out["image"] = str(img)
        return out
    if ext in TEXT or (st.st_size < 2_000_000 and is_text(p)):
        out["kind"] = "text"
        try:
            with open(p, encoding="utf-8", errors="replace") as f:
                lines = [next(f, None) for _ in range(40)]
            out["text"] = "".join(l for l in lines if l is not None)[:4000]
        except OSError:
            pass
    return out


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    try:
        print(json.dumps(preview(sys.argv[1]), ensure_ascii=False))
    except OSError as e:
        print(json.dumps({"kind": "error", "error": e.strerror or str(e)}, ensure_ascii=False))


if __name__ == "__main__":
    main()
