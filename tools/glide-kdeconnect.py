#!/usr/bin/env python3
"""KDE Connect для Glide Shell (D-Bus демона kdeconnectd, PyGObject).

    glide-kdeconnect.py watch                  — строка JSON со списком сопряжённых устройств при каждом изменении
                                                 (сигналы D-Bus, без опроса); stdin закрыт — выход
    glide-kdeconnect.py act ID|auto ДЕЙСТВИЕ   — ping | ring | clipboard | text | files | browse | sms
                                                 (auto — первое устройство на связи; текст — из $QP_TEXT или аргумента)
"""
import json
import os
import subprocess
import sys

import gi

gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib  # noqa: E402

NAME, ROOT = "org.kde.kdeconnect", "/modules/kdeconnect"
bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)


def call(path, iface, method, args=None, sig=None, timeout=5000):
    try:
        r = bus.call_sync(NAME, path, iface, method, args, GLib.VariantType(sig) if sig else None, 0, timeout, None)
        return r.unpack() if r else None
    except GLib.Error as e:
        print(f"glide-kdeconnect: {method}: {e.message}", file=sys.stderr)
        return None


def prop(path, iface, name):
    r = call(path, "org.freedesktop.DBus.Properties", "Get", GLib.Variant("(ss)", (iface, name)))
    return r[0] if r else None


def devices():
    ids = call(ROOT, NAME + ".daemon", "devices", GLib.Variant("(bb)", (False, True)))
    out = []
    for dev in (ids[0] if ids else []):
        p = f"{ROOT}/devices/{dev}"
        plugins = prop(p, NAME + ".device", "supportedPlugins") or []
        d = {"id": dev, "name": prop(p, NAME + ".device", "name") or dev,
             "type": prop(p, NAME + ".device", "type") or "phone",
             "reachable": bool(prop(p, NAME + ".device", "isReachable")),
             "plugins": [x.replace("kdeconnect_", "") for x in plugins]}
        if d["reachable"] and "battery" in d["plugins"] and prop(p + "/battery", NAME + ".device.battery", "hasBattery"):
            d["battery"] = prop(p + "/battery", NAME + ".device.battery", "charge")
            d["charging"] = bool(prop(p + "/battery", NAME + ".device.battery", "isCharging"))
        if d["reachable"] and "connectivity_report" in d["plugins"]:
            d["network"] = prop(p + "/connectivity_report", NAME + ".device.connectivity_report", "cellularNetworkType") or ""
            d["signal"] = prop(p + "/connectivity_report", NAME + ".device.connectivity_report", "cellularNetworkStrength")
        out.append(d)
    return out


def watch():
    last = [None]

    def emit(*_):
        cur = json.dumps(devices(), ensure_ascii=False)
        if cur != last[0]:
            print(cur, flush=True)
            last[0] = cur
        return False

    pending = [0]

    def later(*_):   # сигналы идут пачками — пересчитываем раз в 300 мс
        if not pending[0]:
            pending[0] = GLib.timeout_add(300, lambda: (pending.__setitem__(0, 0), emit())[1])

    bus.signal_subscribe(NAME, None, None, None, None, Gio.DBusSignalFlags.NONE, later)
    # демон перезапустился — список с нуля
    bus.signal_subscribe("org.freedesktop.DBus", "org.freedesktop.DBus", "NameOwnerChanged", "/org/freedesktop/DBus",
                         NAME, Gio.DBusSignalFlags.NONE, later)
    emit()
    loop = GLib.MainLoop()
    ch = GLib.IOChannel.unix_new(sys.stdin.fileno())
    GLib.io_add_watch(ch, GLib.PRIORITY_DEFAULT, GLib.IO_IN | GLib.IO_HUP | GLib.IO_ERR,
                      lambda c, cond: (loop.quit(), False)[1] if (cond & (GLib.IO_HUP | GLib.IO_ERR)) or not c.read() else True)
    loop.run()


def tell(text):   # действия запускаются в фоне — об итоге сообщаем уведомлением
    subprocess.run(["notify-send", "-a", "KDE Connect", "-i", "kdeconnect", "Телефон", text], check=False)


def act(dev, action, arg):
    if dev == "auto":
        on = [d for d in devices() if d["reachable"]]
        if not on:
            tell("Телефон не на связи")
            sys.exit(1)
        dev = on[0]["id"]
    p = f"{ROOT}/devices/{dev}"
    if action == "ping":
        call(p + "/ping", NAME + ".device.ping", "sendPing")
    elif action == "ring":
        call(p + "/findmyphone", NAME + ".device.findmyphone", "ring")
    elif action == "clipboard":
        call(p + "/clipboard", NAME + ".device.clipboard", "sendClipboard")
    elif action == "text":
        text = arg or os.environ.get("QP_TEXT", "")
        if not text.strip():
            sys.exit(1)
        if text.strip().startswith(("http://", "https://")) and "\n" not in text.strip():
            call(p + "/share", NAME + ".device.share", "shareUrl", GLib.Variant("(s)", (text.strip(),)))
        else:
            call(p + "/share", NAME + ".device.share", "shareText", GLib.Variant("(s)", (text,)))
        print("Отправлено на телефон")
    elif action == "files":
        r = subprocess.run(["zenity", "--file-selection", "--multiple", "--separator=\n",
                            "--title=Отправить на телефон"], capture_output=True, text=True)
        urls = ["file://" + f for f in r.stdout.splitlines() if f]
        if urls:
            call(p + "/share", NAME + ".device.share", "shareUrls", GLib.Variant("(as)", (urls,)))
    elif action == "browse":
        ok = call(p + "/sftp", NAME + ".device.sftp", "mountAndWait", timeout=30000)
        mount = call(p + "/sftp", NAME + ".device.sftp", "mountPoint")
        if ok and ok[0] and mount:
            subprocess.Popen(["xdg-open", mount[0]], start_new_session=True)
        else:
            err = call(p + "/sftp", NAME + ".device.sftp", "getMountError")
            tell("Не удалось открыть файлы телефона" + (f": {err[0]}" if err and err[0] else ""))
            sys.exit(1)
    elif action == "sms":
        subprocess.Popen(["kdeconnect-sms", "--device", dev], start_new_session=True)
    else:
        print(f"неизвестное действие: {action}", file=sys.stderr)
        sys.exit(2)


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "watch":
        watch()
    elif len(sys.argv) > 3 and sys.argv[1] == "act":
        act(sys.argv[2], sys.argv[3], " ".join(sys.argv[4:]))
    else:
        print(__doc__)
        sys.exit(2)
