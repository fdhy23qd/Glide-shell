#!/usr/bin/env python3
"""Выбор файла для api.pickFile / api.saveFile: окно выбора через портал (org.freedesktop.portal.FileChooser),
без портала — zenity. Человек выбирает сам — это и есть согласие: плагину не нужно разрешение «exec».

    glide-pick.py open '{"title", "multiple", "directory", "filters": [{"name", "patterns": ["*.txt"]}], "read"}'
    glide-pick.py save '{"title", "name"}'   ← текст в stdin; пишется в выбранный файл

Ответ — JSON: {"ok": true, "paths": [...], "texts": [...]} (texts — только при read: до 16 МБ на файл, UTF-8)
или {"ok": false, "cancelled": true} / {"ok": false, "error": "…"}. Окно — $GLIDE_PICK_ZENITY=1: сразу zenity.
"""
import json
import os
import shutil
import subprocess
import sys
from urllib.parse import unquote, urlparse

LIMIT = 16 * 1024 * 1024


def portal(mode, opt):
    import gi
    gi.require_version("Gio", "2.0")
    from gi.repository import Gio, GLib
    bus = Gio.bus_get_sync(Gio.BusType.SESSION)
    token = f"glide{os.getpid()}"
    sender = bus.get_unique_name()[1:].replace(".", "_")
    handle = f"/org/freedesktop/portal/desktop/request/{sender}/{token}"
    o = {"handle_token": GLib.Variant("s", token), "modal": GLib.Variant("b", True)}
    if mode == "open":
        o["multiple"] = GLib.Variant("b", bool(opt.get("multiple")))
        o["directory"] = GLib.Variant("b", bool(opt.get("directory")))
        flt = [(str(f.get("name", "")), [(0, str(p)) for p in f.get("patterns", [])]) for f in opt.get("filters") or []]
        if flt:
            o["filters"] = GLib.Variant("a(sa(us))", flt)
    else:
        if opt.get("name"):
            o["current_name"] = GLib.Variant("s", str(opt["name"]))
    result, loop = {}, GLib.MainLoop()

    def got(_c, _s, _p, _i, _sig, params):
        code, res = params.unpack()
        result["code"], result["uris"] = code, res.get("uris", [])
        loop.quit()

    bus.signal_subscribe("org.freedesktop.portal.Desktop", "org.freedesktop.portal.Request", "Response", handle, None,
                         Gio.DBusSignalFlags.NONE, got)
    title = str(opt.get("title") or ("Выбери файл" if mode == "open" else "Сохранить как"))
    bus.call_sync("org.freedesktop.portal.Desktop", "/org/freedesktop/portal/desktop", "org.freedesktop.portal.FileChooser",
                  "OpenFile" if mode == "open" else "SaveFile", GLib.Variant("(ssa{sv})", ("", title, o)),
                  None, Gio.DBusCallFlags.NONE, 10000, None)
    loop.run()
    if result.get("code") != 0:
        return None
    return [unquote(urlparse(u).path) for u in result["uris"] if u.startswith("file://")]


def zenity(mode, opt):
    if not shutil.which("zenity"):
        raise RuntimeError("нет окна выбора: ни портала FileChooser, ни zenity")
    a = ["zenity", "--file-selection", "--title", str(opt.get("title") or ("Выбери файл" if mode == "open" else "Сохранить как"))]
    if mode == "save":
        a += ["--save", "--confirm-overwrite"] + (["--filename", str(opt["name"])] if opt.get("name") else [])
    else:
        a += (["--multiple", "--separator", "\n"] if opt.get("multiple") else []) + (["--directory"] if opt.get("directory") else [])
        for f in opt.get("filters") or []:
            a += ["--file-filter", f"{f.get('name', '')} | {' '.join(f.get('patterns', []))}"]
    r = subprocess.run(a, capture_output=True, text=True, stdin=subprocess.DEVNULL)
    return [p for p in r.stdout.splitlines() if p] if r.returncode == 0 else None


def main(a):
    if len(a) < 1 or a[0] not in ("open", "save"):
        sys.exit(__doc__)
    mode, opt = a[0], json.loads(a[1]) if len(a) > 1 else {}
    text = sys.stdin.read() if mode == "save" and opt.get("hasText") else ""   # пустой текст stdin не открывают
    try:
        paths = None
        if not os.environ.get("GLIDE_PICK_ZENITY"):
            try:
                paths = portal(mode, opt)
            except Exception:   # noqa: BLE001 — нет портала: окно zenity
                paths = zenity(mode, opt)
        else:
            paths = zenity(mode, opt)
        if not paths:
            print(json.dumps({"ok": False, "cancelled": True}))
            return
        out = {"ok": True, "paths": paths}
        if mode == "save":
            with open(paths[0], "w", encoding="utf-8") as f:
                f.write(text)
        elif opt.get("read") and not opt.get("directory"):
            texts = []
            for p in paths:
                with open(p, "rb") as f:
                    texts.append(f.read(LIMIT).decode("utf-8", "replace"))
            out["texts"] = texts
        print(json.dumps(out, ensure_ascii=False))
    except Exception as e:   # noqa: BLE001
        print(json.dumps({"ok": False, "error": str(e)}, ensure_ascii=False))


if __name__ == "__main__":
    main(sys.argv[1:])
