#!/usr/bin/env python3
"""Текст с экрана для Glide Shell: выделить область (slurp), снять её (grim — не скриншотом niri: тот всегда кладёт
картинку в буфер и присылает уведомление), распознать (tesseract: русский и английский — какие словари стоят).

    glide-ocr.py                — выделить мышью; ответ — строка JSON
    glide-ocr.py --geometry G   — область «x,y wxh» без выделения
    glide-ocr.py --image FILE   — распознать готовую картинку

Ответ: {"ok": true, "text": "…", "langs": "rus+eng"} | {"ok": false, "cancelled": true} (Esc в выделении)
| {"ok": false, "missing": ["grim", …], "install": "sudo pacman -S …"} | {"ok": false, "error": "…"}.
Картинка перед распознаванием — серая, вдвое крупнее, светлый текст на тёмном — обращён: так tesseract
заметно реже ошибается на мелком экранном шрифте.
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile
import textwrap

PACKAGES = {"slurp": "slurp", "grim": "grim", "tesseract": "tesseract tesseract-data-rus tesseract-data-eng"}


def say(obj):
    print(json.dumps(obj, ensure_ascii=False), flush=True)


def langs():
    r = subprocess.run(["tesseract", "--list-langs"], capture_output=True, text=True, stdin=subprocess.DEVNULL)
    have = {l.strip() for l in (r.stdout + r.stderr).splitlines()[1:] if l.strip()}
    use = [l for l in ("rus", "eng") if l in have]
    return "+".join(use)


def prepare(src, dst):
    """Серая, ×2, светлое на тёмном → тёмное на светлом. Без Pillow — как есть."""
    try:
        from PIL import Image, ImageOps, ImageStat
    except ImportError:
        shutil.copy(src, dst)
        return
    im = Image.open(src).convert("L")
    if ImageStat.Stat(im).mean[0] < 128:
        im = ImageOps.invert(im)
    im = im.resize((im.width * 2, im.height * 2), Image.LANCZOS)
    im.save(dst)


def main(a):
    geometry = image = None
    if "--geometry" in a:
        geometry = a[a.index("--geometry") + 1]
    if "--image" in a:
        image = a[a.index("--image") + 1]
    need = ["tesseract"] + ([] if image else ["grim"]) + ([] if image or geometry else ["slurp"])
    missing = [p for p in need if not shutil.which(p)]
    if missing:
        say({"ok": False, "missing": missing, "install": "sudo pacman -S " + " ".join(PACKAGES[p] for p in missing)})
        return
    lang = langs()
    if not lang:
        say({"ok": False, "missing": ["tesseract-data-rus"], "install": "sudo pacman -S tesseract-data-rus tesseract-data-eng"})
        return
    with tempfile.TemporaryDirectory(prefix="glide-ocr-") as tmp:
        shot, ready = os.path.join(tmp, "shot.png"), os.path.join(tmp, "ready.png")
        if image:
            shot = image
        else:
            if not geometry:
                # stdin — /dev/null: иначе slurp ждёт прямоугольники из stdin (CLAUDE.md, «Грабли»)
                r = subprocess.run(["slurp"], capture_output=True, text=True, stdin=subprocess.DEVNULL)
                geometry = r.stdout.strip()
                if r.returncode != 0 or not geometry:
                    say({"ok": False, "cancelled": True})
                    return
            r = subprocess.run(["grim", "-g", geometry, shot], capture_output=True, text=True, stdin=subprocess.DEVNULL)
            if r.returncode != 0:
                say({"ok": False, "error": "grim: " + (r.stderr.strip() or f"код {r.returncode}")})
                return
        try:
            prepare(shot, ready)
        except Exception as e:   # noqa: BLE001 — битая картинка: причину человеку
            say({"ok": False, "error": f"картинка: {e}"})
            return
        r = subprocess.run(["tesseract", ready, "-", "-l", lang, "--psm", "6"], capture_output=True, text=True,
                           stdin=subprocess.DEVNULL)
        if r.returncode != 0:
            say({"ok": False, "error": "tesseract: " + (r.stderr.strip().splitlines() or [f"код {r.returncode}"])[-1]})
            return
        lines = [l.rstrip() for l in r.stdout.replace("\f", "").splitlines()]
        while lines and not lines[-1]:
            lines.pop()
        while lines and not lines[0]:
            lines.pop(0)
        say({"ok": True, "text": textwrap.dedent("\n".join(lines)), "langs": lang})   # общий отступ — прочь


if __name__ == "__main__":
    main(sys.argv[1:])
