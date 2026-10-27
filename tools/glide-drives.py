#!/usr/bin/env python3
"""Съёмные диски для Glide Shell (udisks2 по D-Bus, без root: монтирование своей флешки разрешает polkit).

    glide-drives.py watch          — строка JSON со списком при старте и при каждом изменении (stdin закрыт — выход)
    glide-drives.py list           — список один раз
    glide-drives.py mount ID       — смонтировать раздел → {"ok", "mountPoint"} или {"ok": false, "error"}
    glide-drives.py unmount ID     — отмонтировать
    glide-drives.py eject ID       — отмонтировать все разделы этого устройства и извлечь (или выключить питание)

ID — путь объекта udisks (/org/freedesktop/UDisks2/block_devices/sdb1). В списке — разделы с файловой системой,
которые не системные (HintSystem — так udisks отличает внутренние диски) и не скрытые (HintIgnore):
{id, label, device, fs, size, mounted, mountPoint, drive, driveName, ejectable, canPowerOff, encrypted, image}.
У образа (image) «извлечь» — отмонтировать и отключить loop (Loop.Delete).
"""
import json
import os
import sys

UD = "org.freedesktop.UDisks2"
ROOT = "/org/freedesktop/UDisks2"


def text(v):
    """ay из udisks (байты, с нулём в конце) → строка."""
    if isinstance(v, (bytes, bytearray)):
        return bytes(v).rstrip(b"\0").decode(errors="replace")
    if isinstance(v, (list, tuple)):
        return bytes(v).rstrip(b"\0").decode(errors="replace")
    return str(v or "")


def drives(objects, uid=None):
    """{путь: {интерфейс: {свойство: значение}}} (как GetManagedObjects) → список съёмных разделов.
    Образ (loop), подключённый самим пользователем (SetupByUID — его uid), тоже свой — как в gvfs."""
    uid = os.getuid() if uid is None else uid
    out = []
    for path, ifaces in sorted(objects.items()):
        blk = ifaces.get(UD + ".Block")
        loop = ifaces.get(UD + ".Loop")
        mine = loop is not None and loop.get("SetupByUID") == uid
        if not blk or blk.get("HintIgnore") or (blk.get("HintSystem") and not mine):
            continue
        fs, enc = ifaces.get(UD + ".Filesystem"), ifaces.get(UD + ".Encrypted")
        if fs is None and enc is None:
            continue
        drv_path = blk.get("Drive", "/")
        drv = objects.get(drv_path, {}).get(UD + ".Drive", {})
        mps = [text(m) for m in (fs or {}).get("MountPoints", [])]
        name = " ".join(x for x in (drv.get("Vendor", "").strip(), drv.get("Model", "").strip()) if x)
        out.append({
            "id": path,
            "label": blk.get("IdLabel") or blk.get("HintName") or "",
            "device": text(blk.get("PreferredDevice") or blk.get("Device")),
            "fs": blk.get("IdType", ""),
            "size": int(blk.get("Size", 0)),
            "mounted": bool(mps),
            "mountPoint": mps[0] if mps else "",
            "drive": drv_path if drv_path != "/" else "",
            "driveName": name,
            "ejectable": bool(drv.get("Ejectable")),
            "canPowerOff": bool(drv.get("CanPowerOff")),
            "encrypted": enc is not None and fs is None,
            "image": mine,
        })
    return out


def main(a):
    import gi
    gi.require_version("Gio", "2.0")
    from gi.repository import Gio, GLib

    bus = Gio.bus_get_sync(Gio.BusType.SYSTEM)

    def call(path, iface, method, args=None, sig=None, timeout=60000):
        return bus.call_sync(UD, path, iface, method, args, GLib.VariantType(sig) if sig else None,
                             Gio.DBusCallFlags.NONE, timeout, None)

    def objects():
        return call(ROOT, "org.freedesktop.DBus.ObjectManager", "GetManagedObjects", None, "(a{oa{sa{sv}}})").unpack()[0]

    def say(obj):
        print(json.dumps(obj, ensure_ascii=False), flush=True)

    def err(e):
        msg = e.message if hasattr(e, "message") else str(e)
        return {"ok": False, "error": msg.split(":", 2)[-1].strip() if "GDBus.Error" in msg else msg}

    cmd = a[0] if a else "list"
    if cmd == "list":
        say(drives(objects()))
        return
    if cmd in ("mount", "unmount", "eject") and len(a) > 1:
        path = a[1]
        opts = GLib.Variant("(a{sv})", ({},))
        try:
            if cmd == "mount":
                mp = call(path, UD + ".Filesystem", "Mount", opts, "(s)").unpack()[0]
                say({"ok": True, "mountPoint": mp})
            elif cmd == "unmount":
                call(path, UD + ".Filesystem", "Unmount", opts)
                say({"ok": True})
            else:
                objs = objects()
                me = next((d for d in drives(objs) if d["id"] == path), None)
                if not me:
                    raise RuntimeError("нет такого диска")
                for d in drives(objs):   # все разделы того же устройства (или только этот, если он сам по себе)
                    if d["mounted"] and (d["id"] == path or (me["drive"] and d["drive"] == me["drive"])):
                        call(d["id"], UD + ".Filesystem", "Unmount", opts)
                if me["image"]:
                    call(path, UD + ".Loop", "Delete", opts)
                elif me["drive"] and me["ejectable"]:
                    call(me["drive"], UD + ".Drive", "Eject", opts)
                elif me["drive"] and me["canPowerOff"]:
                    call(me["drive"], UD + ".Drive", "PowerOff", opts)
                say({"ok": True})
        except Exception as e:   # noqa: BLE001 — причину (занято, нет прав) показываем человеку
            say(err(e))
            sys.exit(1)
        return
    if cmd != "watch":
        sys.exit(__doc__)

    last = [None]
    pending = [0]

    def emit():
        pending[0] = 0
        try:
            cur = json.dumps(drives(objects()), ensure_ascii=False)
        except GLib.Error as e:
            print(f"glide-drives: {e.message}", file=sys.stderr, flush=True)
            return False
        if cur != last[0]:
            print(cur, flush=True)
            last[0] = cur
        return False

    def changed(*_):   # события пачками (вставили флешку — десяток) — список раз в 300 мс
        if not pending[0]:
            pending[0] = GLib.timeout_add(300, emit)

    bus.signal_subscribe(UD, None, None, None, None, Gio.DBusSignalFlags.NONE, changed)
    emit()
    loop = GLib.MainLoop()
    ch = GLib.IOChannel.unix_new(sys.stdin.fileno())
    GLib.io_add_watch(ch, GLib.PRIORITY_DEFAULT, GLib.IO_IN | GLib.IO_HUP | GLib.IO_ERR,
                      lambda c, cond: (loop.quit(), False)[1] if (cond & (GLib.IO_HUP | GLib.IO_ERR)) or not c.read() else True)
    loop.run()


if __name__ == "__main__":
    main(sys.argv[1:])
