#!/usr/bin/env python3
"""Агент BlueZ для Glide Shell: подтверждение кодов при сопряжении Bluetooth.

Регистрируется в bluetoothd как агент по умолчанию (KeyboardDisplay). Вопросы печатает в stdout
строками JSON, ответы читает из stdin строками «<id> yes|no [значение]»:

  {"id": 3, "kind": "confirm", "device": "Pixel 9a", "code": "123456"}   → «3 yes» / «3 no»
  {"id": 4, "kind": "pin", "device": "Клавиатура"}                         → «4 yes 0000»
  {"id": 5, "kind": "passkey", "device": "…"}                              → «5 yes 123456»
  {"id": 6, "kind": "authorize", "device": "…"}                            → «6 yes» / «6 no»
  {"kind": "display", "device": "…", "code": "123456"}   — показать код, который нужно набрать на устройстве
  {"kind": "cancel"}                                      — bluetoothd отменил запрос

Закрылся stdin (оболочка завершилась) — агент снимает регистрацию и выходит.
GLIDE_BT_AGENT_TEST=1 — проверка протокола: объект на сессионной шине, без регистрации в BlueZ
(на системной шине вызывать агента может только bluetoothd).
"""
import json
import os
import sys

import gi

gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib  # noqa: E402

PATH = "/org/glide/btagent"
XML = """
<node>
  <interface name="org.bluez.Agent1">
    <method name="Release"/>
    <method name="RequestPinCode"><arg type="o" direction="in"/><arg type="s" direction="out"/></method>
    <method name="DisplayPinCode"><arg type="o" direction="in"/><arg type="s" direction="in"/></method>
    <method name="RequestPasskey"><arg type="o" direction="in"/><arg type="u" direction="out"/></method>
    <method name="DisplayPasskey"><arg type="o" direction="in"/><arg type="u" direction="in"/><arg type="q" direction="in"/></method>
    <method name="RequestConfirmation"><arg type="o" direction="in"/><arg type="u" direction="in"/></method>
    <method name="RequestAuthorization"><arg type="o" direction="in"/></method>
    <method name="AuthorizeService"><arg type="o" direction="in"/><arg type="s" direction="in"/></method>
    <method name="Cancel"/>
  </interface>
</node>
"""

TEST = os.environ.get("GLIDE_BT_AGENT_TEST") == "1"
bus = Gio.bus_get_sync(Gio.BusType.SESSION if TEST else Gio.BusType.SYSTEM, None)
pending = {}   # id → (invocation, kind)
seq = 0


def emit(obj):
    print(json.dumps(obj, ensure_ascii=False), flush=True)


def device_name(path):
    try:
        props = bus.call_sync("org.bluez", path, "org.freedesktop.DBus.Properties", "GetAll",
                              GLib.Variant("(s)", ("org.bluez.Device1",)), None, 0, 2000, None).unpack()[0]
        return props.get("Alias") or props.get("Name") or props.get("Address") or path
    except GLib.Error:
        return path.rsplit("/", 1)[-1].replace("dev_", "").replace("_", ":")


def device_paired(path):
    try:
        return bus.call_sync("org.bluez", path, "org.freedesktop.DBus.Properties", "Get",
                             GLib.Variant("(ss)", ("org.bluez.Device1", "Paired")), None, 0, 2000, None).unpack()[0]
    except GLib.Error:
        return False


def reject(inv, msg="Отклонено"):
    inv.return_dbus_error("org.bluez.Error.Rejected", msg)


def ask(inv, kind, device, code=None):
    global seq
    seq += 1
    pending[seq] = (inv, kind)
    msg = {"id": seq, "kind": kind, "device": device_name(device)}
    if code is not None:
        msg["code"] = code
    emit(msg)


def on_call(conn, sender, path, iface, method, params, inv):
    args = params.unpack()
    if method == "RequestConfirmation":
        ask(inv, "confirm", args[0], f"{args[1]:06d}")
    elif method == "RequestPinCode":
        ask(inv, "pin", args[0])
    elif method == "RequestPasskey":
        ask(inv, "passkey", args[0])
    elif method == "RequestAuthorization":
        ask(inv, "authorize", args[0])
    elif method == "AuthorizeService":
        # службы уже сопряжённого устройства (звук, ввод) пускаем без вопросов, чужое — спрашиваем
        if device_paired(args[0]):
            inv.return_value(None)
        else:
            ask(inv, "authorize", args[0])
    elif method == "DisplayPinCode":
        emit({"kind": "display", "device": device_name(args[0]), "code": args[1]})
        inv.return_value(None)
    elif method == "DisplayPasskey":
        emit({"kind": "display", "device": device_name(args[0]), "code": f"{args[1]:06d}"})
        inv.return_value(None)
    elif method == "Cancel":
        for i, (p, _) in list(pending.items()):
            reject(p, "Отменено")
            del pending[i]
        emit({"kind": "cancel"})
        inv.return_value(None)
    else:   # Release
        inv.return_value(None)


def on_stdin(channel, cond):
    if cond & (GLib.IO_HUP | GLib.IO_ERR):
        loop.quit()
        return False
    line = channel.readline()
    if not line:
        loop.quit()
        return False
    parts = line.strip().split(maxsplit=2)
    if len(parts) < 2 or not parts[0].isdigit():
        return True
    entry = pending.pop(int(parts[0]), None)
    if not entry:
        return True
    inv, kind = entry
    if parts[1] != "yes":
        reject(inv)
    elif kind == "pin":
        inv.return_value(GLib.Variant("(s)", (parts[2] if len(parts) > 2 else "0000",)))
    elif kind == "passkey":
        try:
            inv.return_value(GLib.Variant("(u)", (int(parts[2]),)))
        except (IndexError, ValueError):
            reject(inv, "Неверный код")
    else:
        inv.return_value(None)
    return True


node = Gio.DBusNodeInfo.new_for_xml(XML)
reg = bus.register_object(PATH, node.interfaces[0], on_call, None, None)
manager = ("org.bluez", "/org/bluez", "org.bluez.AgentManager1")
try:
    if not TEST:
        bus.call_sync(*manager, "RegisterAgent", GLib.Variant("(os)", (PATH, "KeyboardDisplay")), None, 0, 5000, None)
        bus.call_sync(*manager, "RequestDefaultAgent", GLib.Variant("(o)", (PATH,)), None, 0, 5000, None)
except GLib.Error as e:
    print(f"glide-bt-agent: не удалось зарегистрироваться: {e.message}", file=sys.stderr)
    sys.exit(1)
emit({"kind": "ready", "bus": bus.get_unique_name()})

loop = GLib.MainLoop()
ch = GLib.IOChannel.unix_new(sys.stdin.fileno())
GLib.io_add_watch(ch, GLib.PRIORITY_DEFAULT, GLib.IO_IN | GLib.IO_HUP | GLib.IO_ERR, on_stdin)
try:
    loop.run()
except KeyboardInterrupt:
    pass
if not TEST:
    try:
        bus.call_sync(*manager, "UnregisterAgent", GLib.Variant("(o)", (PATH,)), None, 0, 2000, None)
    except GLib.Error:
        pass
