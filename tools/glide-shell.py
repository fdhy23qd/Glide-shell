#!/usr/bin/env python3
"""glide-shell — Glide Shell для других программ: служба D-Bus org.glide.Shell и команда для скриптов.

Команда (ставится как ~/.local/bin/glide-shell):
    glide-shell flash ТЕКСТ [--icon ЗНАЧОК]
    glide-shell activity start|update ID [--title …] [--subtitle …] [--progress 0…1] [--icon …] [--color #hex]
    glide-shell activity end ID
    glide-shell open [КАТЕГОРИЯ] | close | search ТЕКСТ
    glide-shell dnd [on|off]
    glide-shell theme                       — тема JSON (акцент, светлая ли, цвета, скругления)
    glide-shell plugins                     — плагины JSON: id, имя, включён, версия API, разрешения (что выдано)
    glide-shell settings [РАЗДЕЛ]           — открыть настройки (plugins, look, bar…)
    glide-shell install-plugin АРХИВ        — карточка установки плагина в «Настройки» → «Плагины» (ставит человек)
    glide-shell version | api               — версия оболочки | версия API плагинов
    glide-shell watch                       — печатать события (тема, щелчки по активностям) строками JSON
    glide-shell doctor [--json]             — проверить установку: зависимости, служба, niri, права файлов, журнал

Служба (`--daemon`) запускается шиной сама при первом обращении (~/.local/share/dbus-1/services/org.glide.Shell.service):
интерфейс org.glide.Shell1 на /org/glide/Shell — описание в docs/API.md. В оболочку передаёт через
`qs -c glide-shell ipc call panel dbus <base64 JSON>` (qs ipc режет аргументы по запятым — поэтому base64).
"""
import base64
import json
import os
import re
import subprocess
import sys
import time
from pathlib import Path

NAME, PATH, IFACE = "org.glide.Shell", "/org/glide/Shell", "org.glide.Shell1"
RUNTIME = Path(os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}")
THEME = RUNTIME / "glide-shell-theme.json"
STATE = Path(os.environ.get("XDG_STATE_HOME") or Path.home() / ".local/state") / "glide-shell"
SHELL_QML = Path(os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config") / "quickshell/glide-shell/shell.qml"

XML = f"""<node><interface name="{IFACE}">
  <method name="Flash"><arg type="s" name="icon" direction="in"/><arg type="s" name="text" direction="in"/></method>
  <method name="StartActivity"><arg type="s" name="id" direction="in"/><arg type="a{{sv}}" name="props" direction="in"/></method>
  <method name="UpdateActivity"><arg type="s" name="id" direction="in"/><arg type="a{{sv}}" name="props" direction="in"/></method>
  <method name="EndActivity"><arg type="s" name="id" direction="in"/></method>
  <method name="OpenPanel"><arg type="s" name="category" direction="in"/></method>
  <method name="ClosePanel"/>
  <method name="Search"><arg type="s" name="text" direction="in"/></method>
  <method name="SetDnd"><arg type="b" name="on" direction="in"/></method>
  <method name="GetDnd"><arg type="b" name="on" direction="out"/></method>
  <method name="GetTheme"><arg type="a{{sv}}" name="theme" direction="out"/></method>
  <method name="GetVersion"><arg type="s" name="version" direction="out"/></method>
  <method name="GetApiVersion"><arg type="u" name="version" direction="out"/></method>
  <method name="ListPlugins"><arg type="aa{{sv}}" name="plugins" direction="out"/></method>
  <method name="OpenSettings"><arg type="s" name="page" direction="in"/></method>
  <method name="ActivityEvent"><arg type="s" name="id" direction="in"/><arg type="s" name="event" direction="in"/></method>
  <signal name="ThemeChanged"><arg type="a{{sv}}" name="theme"/></signal>
  <signal name="ActivityClicked"><arg type="s" name="id"/></signal>
  <signal name="ActivityAction"><arg type="s" name="id"/></signal>
  <signal name="ActivityClosed"><arg type="s" name="id"/></signal>
</interface></node>"""


def to_shell(payload):
    """Передать оболочке: base64 от JSON (без запятых, которые qs ipc режет)."""
    b = base64.b64encode(json.dumps(payload, ensure_ascii=False).encode()).decode()
    cmd = os.environ.get("GLIDE_SHELL_IPC", "qs -c glide-shell ipc call panel dbus").split() + [b]
    try:
        subprocess.run(cmd, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=10)
    except (OSError, subprocess.TimeoutExpired):
        pass


def read_theme():
    try:
        return json.loads(THEME.read_text())
    except (OSError, ValueError):
        return {}


def read_dnd():
    try:
        return (STATE / "dnd").read_text().strip() in ("1", "on", "true")
    except OSError:
        return False


API_VERSION = 2   # версия API плагинов (docs/API.md); у D-Bus своя — в имени интерфейса (Shell1)


def plugins():
    """Плагины из qp-discover: только чтение. Разрешения так не выдать — их меняет только человек в настройках."""
    tool = Path(__file__).resolve().parent / "qp-discover.py"
    try:
        r = subprocess.run([sys.executable, "-I", str(tool)], stdin=subprocess.DEVNULL, capture_output=True, text=True,
                           timeout=30)
        every = json.loads(r.stdout).get("allPlugins") or []
    except (OSError, ValueError, subprocess.TimeoutExpired):
        return []
    keep = ("id", "name", "icon", "disabled", "user", "api", "permissions", "granted", "problem")
    return [{k: p.get(k) for k in keep if p.get(k) is not None} for p in every]


def version():
    try:
        m = re.search(r"Glide Shell (v[\d.]+)", SHELL_QML.read_text())
        return m.group(1) if m else ""
    except OSError:
        return ""


# ---------------------------------------------------------------- служба
def daemon():
    import gi
    gi.require_version("Gio", "2.0")
    from gi.repository import Gio, GLib

    node = Gio.DBusNodeInfo.new_for_xml(XML)
    conn = Gio.bus_get_sync(Gio.BusType.SESSION)
    owners = {}           # id активности → уникальное имя отправителя (уйдёт с шины — активность убрать)
    pending = {}          # id → последние props (обновления не чаще 4 раз в секунду)
    last_sent = {}

    def props_ok(p):
        keep = {"title", "subtitle", "icon", "progress", "color", "actionLabel"}
        return {k: v for k, v in p.items() if k in keep}

    def flush_updates():
        now = time.monotonic()
        for aid in list(pending):
            if now - last_sent.get(aid, 0) >= 0.25:
                to_shell({"op": "update", "id": aid, "props": pending.pop(aid)})
                last_sent[aid] = now
        return True

    def emit(signal, args):
        conn.emit_signal(None, PATH, IFACE, signal, args)

    def on_call(_conn, sender, _path, _iface, method, params, inv):
        try:
            handle(sender, method, params, inv)
        except Exception as e:   # вызов без ответа повис бы у приложения до таймаута — отвечаем ошибкой
            inv.return_dbus_error("org.glide.Shell1.Error", str(e))

    def handle(sender, method, params, inv):
        a = params.unpack()
        if method == "Flash":
            to_shell({"op": "flash", "icon": a[0], "text": a[1]})
        elif method in ("StartActivity", "UpdateActivity"):
            aid, raw = a[0], dict(a[1])   # a{sv} Gio уже разобрал в обычный словарь
            p = props_ok(raw)
            if not raw.get("persist") and not aid.startswith("cli/"):   # от команды и «persist» — не привязаны к процессу
                owners[aid] = sender
            if method == "StartActivity":
                pending.pop(aid, None)
                to_shell({"op": "start", "id": aid, "props": p})
                last_sent[aid] = time.monotonic()
            else:
                pending[aid] = {**pending.get(aid, {}), **p}
        elif method == "EndActivity":
            pending.pop(a[0], None); owners.pop(a[0], None)
            to_shell({"op": "end", "id": a[0]})
        elif method == "OpenPanel":
            to_shell({"op": "open", "category": a[0]})
        elif method == "ClosePanel":
            to_shell({"op": "close"})
        elif method == "Search":
            to_shell({"op": "search", "text": a[0]})
        elif method == "SetDnd":
            to_shell({"op": "dnd", "on": bool(a[0])})
        elif method == "GetDnd":
            return inv.return_value(GLib.Variant("(b)", (read_dnd(),)))
        elif method == "GetTheme":
            return inv.return_value(GLib.Variant("(a{sv})", (variants(read_theme()),)))
        elif method == "GetVersion":
            return inv.return_value(GLib.Variant("(s)", (version(),)))
        elif method == "GetApiVersion":
            return inv.return_value(GLib.Variant("(u)", (API_VERSION,)))
        elif method == "ListPlugins":
            return inv.return_value(GLib.Variant("(aa{sv})", ([variants(p) for p in plugins()],)))
        elif method == "OpenSettings":
            to_shell({"op": "settings", "page": a[0]})
        elif method == "ActivityEvent":   # от оболочки: щелчок, кнопка, закрыли «×»
            sig = {"clicked": "ActivityClicked", "action": "ActivityAction", "closed": "ActivityClosed"}.get(a[1])
            if sig:
                emit(sig, GLib.Variant("(s)", (a[0],)))
            if a[1] == "closed":
                owners.pop(a[0], None)
        inv.return_value(None)

    def variants(d):
        out = {}
        for k, v in d.items():
            if isinstance(v, bool): out[k] = GLib.Variant("b", v)
            elif isinstance(v, int): out[k] = GLib.Variant("i", v)
            elif isinstance(v, float): out[k] = GLib.Variant("d", v)
            elif isinstance(v, list): out[k] = GLib.Variant("as", [str(x) for x in v])
            else: out[k] = GLib.Variant("s", str(v))
        return out

    def name_gone(_c, _s, _p, _i, _sig, params):   # приложение закрылось — его активности тоже
        name, _old, new = params.unpack()
        if new:
            return
        for aid in [k for k, v in owners.items() if v == name]:
            owners.pop(aid); pending.pop(aid, None)
            to_shell({"op": "end", "id": aid})

    conn.register_object(PATH, node.interfaces[0], on_call, None, None)
    conn.signal_subscribe("org.freedesktop.DBus", "org.freedesktop.DBus", "NameOwnerChanged", "/org/freedesktop/DBus",
                          None, Gio.DBusSignalFlags.NONE, name_gone)
    THEME.parent.mkdir(parents=True, exist_ok=True)
    monitor = Gio.File.new_for_path(str(THEME)).monitor_file(Gio.FileMonitorFlags.NONE, None)
    monitor.connect("changed", lambda *_: GLib.timeout_add(100, lambda: (emit("ThemeChanged",
                    GLib.Variant("(a{sv})", (variants(read_theme()),))), False)[1]))
    GLib.timeout_add(100, flush_updates)
    loop = GLib.MainLoop()
    Gio.bus_own_name_on_connection(conn, NAME, Gio.BusNameOwnerFlags.NONE, None, lambda *_: loop.quit())
    loop.run()


# ---------------------------------------------------------------- команда
def call(method, signature=None, args=None, reply=False):
    import gi
    gi.require_version("Gio", "2.0")
    from gi.repository import Gio, GLib
    bus = Gio.bus_get_sync(Gio.BusType.SESSION)
    r = bus.call_sync(NAME, PATH, IFACE, method, GLib.Variant(signature, args) if signature else None,
                      None, Gio.DBusCallFlags.NONE, 15000, None)
    return r.unpack() if reply and r else None


def opt(args, name, default=None):
    if name in args:
        i = args.index(name)
        if i + 1 < len(args):
            return args[i + 1]
    return default


def cli(a):
    if a[:1] == ["doctor"]:   # без D-Bus и gi: должен работать и тогда, когда сломано всё остальное
        tool = os.path.join(os.path.dirname(os.path.realpath(__file__)), "glide-doctor.py")
        os.execv(sys.executable, [sys.executable, "-I", tool] + a[1:])
    from gi.repository import GLib
    if not a:
        sys.exit(__doc__)
    cmd = a[0]
    if cmd == "flash" and len(a) > 1:
        call("Flash", "(ss)", (opt(a, "--icon", ""), a[1]))
    elif cmd == "activity" and len(a) > 2:
        act, aid = a[1], "cli/" + a[2]
        if act == "end":
            call("EndActivity", "(s)", (aid,))
        else:
            p = {}
            for key in ("title", "subtitle", "icon", "color"):
                if opt(a, "--" + key) is not None:
                    p[key] = GLib.Variant("s", opt(a, "--" + key))
            if opt(a, "--progress") is not None:
                p["progress"] = GLib.Variant("d", float(opt(a, "--progress")))
            call("StartActivity" if act == "start" else "UpdateActivity", "(sa{sv})", (aid, p))
    elif cmd == "open":
        call("OpenPanel", "(s)", (a[1] if len(a) > 1 else "",))
    elif cmd == "close":
        call("ClosePanel")
    elif cmd == "search" and len(a) > 1:
        call("Search", "(s)", (" ".join(a[1:]),))
    elif cmd == "dnd":
        if len(a) > 1:
            call("SetDnd", "(b)", (a[1] == "on",))
        else:
            print("on" if call("GetDnd", reply=True)[0] else "off")
    elif cmd == "theme":
        print(json.dumps(call("GetTheme", reply=True)[0], ensure_ascii=False))
    elif cmd == "version":
        print(call("GetVersion", reply=True)[0])
    elif cmd == "api":
        print(call("GetApiVersion", reply=True)[0])
    elif cmd == "plugins":
        print(json.dumps(call("ListPlugins", reply=True)[0], ensure_ascii=False, indent=1))
    elif cmd == "install-plugin" and len(a) > 1:   # прямо через IPC оболочки: qs ipc режет аргументы по запятым
        path = os.path.abspath(os.path.expanduser(a[1]))
        if not os.path.isfile(path):
            sys.exit(f"нет файла: {path}")
        if "," in path:
            sys.exit("в пути есть запятая — qs ipc разрежет его; переименуй файл")
        subprocess.run(["qs", "-c", "glide-shell", "ipc", "call", "panel", "pluginInstall", path], stdin=subprocess.DEVNULL)
    elif cmd == "settings":
        call("OpenSettings", "(s)", (a[1] if len(a) > 1 else "",))
    elif cmd == "watch":
        import gi
        from gi.repository import Gio
        bus = Gio.bus_get_sync(Gio.BusType.SESSION)
        call("GetVersion", reply=True)   # разбудить службу
        bus.signal_subscribe(NAME, IFACE, None, PATH, None, Gio.DBusSignalFlags.NONE,
                             lambda _c, _s, _p, _i, sig, params: print(json.dumps({"signal": sig, "args": params.unpack()},
                                                                                   ensure_ascii=False), flush=True))
        GLib.MainLoop().run()
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    if sys.argv[1:2] == ["--daemon"]:
        daemon()
    else:
        cli(sys.argv[1:])
