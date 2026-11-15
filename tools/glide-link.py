#!/usr/bin/env python3
"""Glide Link для Glide Shell: устройства и действия через управляющий сокет демона glide-link
($XDG_RUNTIME_DIR/glide-link.sock). Только стандартная библиотека.

    glide-link.py watch                  — строка JSON {devices, pairing, discovered, me} при каждом изменении
                                           (демон сам присылает изменения — без опроса); stdin закрыт — выход;
                                           демона нет — код 1 (Phones.qml перезапустит позже)
    glide-link.py act ID|auto ДЕЙСТВИЕ   — ping | ring | clipboard | text | files | screen | screen-stop | audio |
                                           audio-stop | screen-share | audio-share | pair | accept | reject | unpair |
                                           upload ПАПКА_ТЕЛЕФОНА (выбор файлов — zenity, в эту папку телефона)
                                           (auto — первое устройство на связи; его нет — KDE Connect;
                                           текст — из $QP_TEXT или аргумента)
    glide-link.py connect IP[:ПОРТ]      — подключиться по адресу (сеть режет broadcast)
    glide-link.py call 'JSON'            — любая команда демона (glide_link/daemon.py), ответ — строка JSON
                                           (для панели: SMS, файлы телефона, команды)

Формат устройства — как у glide-kdeconnect.py (id, name, type, reachable, plugins, battery, charging, network)
плюс backend: "glidelink", streams: {screen_in, screen_out, audio_in, audio_out}, players, sms_rev, files_rev.
"""
import json
import os
import selectors
import socket
import subprocess
import sys
from pathlib import Path

SOCK = Path(os.environ.get("XDG_RUNTIME_DIR") or f"/tmp/glide-link-{os.getuid()}") / "glide-link.sock"
HERE = Path(__file__).resolve().parent


def connect() -> socket.socket:
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.connect(str(SOCK))
    return s


def lines(sock: socket.socket):
    buf = b""
    while True:
        chunk = sock.recv(65536)
        if not chunk:
            return
        buf += chunk
        while b"\n" in buf:
            line, buf = buf.split(b"\n", 1)
            if line.strip():
                yield json.loads(line)


def request(req: dict, timeout: float = 30) -> dict:
    """Одна команда демону; ответ — последняя строка с done. Демона нет — {"ok": False, ...}."""
    try:
        s = connect()
    except OSError:
        return {"ok": False, "error": "Glide Link не запущен"}
    s.settimeout(timeout)
    with s:
        s.sendall((json.dumps(req, ensure_ascii=False) + "\n").encode())
        try:
            for msg in lines(s):
                if msg.get("done"):
                    return msg
        except (OSError, ValueError):
            pass
    return {"ok": False, "error": "демон закрыл соединение"}


def bars(signal: int) -> str:
    """Уровень 0–4 кружками: блочные ▁▂▄▆ в Inter рисуются тонкими чёрточками."""
    n = max(0, min(4, int(signal)))
    return "●" * n + "○" * (4 - n)


def network(d: dict) -> str:
    """«LTE ●●●○ · через интернет»: мобильная сеть телефона (отчёт о связи) и путь связи с ПК."""
    b = d.get("battery") or {}
    parts = []
    if b.get("network"):
        sig = b.get("signal")
        parts.append(b["network"] + (" " + bars(sig) if isinstance(sig, int) else ""))
    if d.get("via") == "relay":
        parts.append("через интернет")
    return " · ".join(parts)


def device(d: dict) -> dict:
    """Устройство демона → формат панели (как у KDE Connect)."""
    st = d.get("state")
    out = {
        "id": d["id"], "name": d.get("name") or d["id"], "type": "phone", "backend": "glidelink",
        "reachable": st in ("connected", "degraded"),
        "plugins": [c for c in d.get("capabilities", []) if not c.startswith("core.")],
        "network": network(d),
        "streams": d.get("streams") or {},
        "players": d.get("players") or [],
        "sms_rev": d.get("sms_rev", 0),          # меняется, когда пришли новые SMS — открытый диалог перечитать
        "notifications": d.get("notifications", 0),
    }
    b = d.get("battery")
    if out["reachable"] and b:
        out["battery"] = int(b.get("level", 0))
        out["charging"] = bool(b.get("charging"))
    return out


def devices(status: dict) -> list:
    return [device(d) for d in status.get("devices", []) if d.get("trusted")]


def state(status: dict) -> dict:
    """Всё, что нужно панели: сопряжённые, запросы сопряжения, найденные в сети, это устройство."""
    return {
        "devices": devices(status),
        "pairing": [{"id": r["id"], "name": r.get("name") or r["id"], "code": r.get("code", ""),
                     "keyChanged": bool(r.get("key_changed"))} for r in status.get("pairing", [])],
        "discovered": [{"id": d["id"], "name": d.get("name") or d["id"], "address": d.get("address") or ""}
                       for d in status.get("devices", []) if not d.get("trusted") and d.get("address")],
        "me": status.get("me") or {},
    }


def watch() -> int:
    try:
        s = connect()
    except OSError:
        return 1
    s.sendall(b'{"cmd": "watch"}\n')
    sel = selectors.DefaultSelector()
    sel.register(s, selectors.EVENT_READ, "sock")
    sel.register(sys.stdin, selectors.EVENT_READ, "stdin")
    buf, last = b"", None
    while True:
        for key, _ in sel.select():
            if key.data == "stdin":
                if not sys.stdin.buffer.read1(4096):   # оболочка закрыла stdin — пора выходить
                    return 0
                continue
            chunk = s.recv(65536)
            if not chunk:
                return 1   # демон остановился — перезапустят позже
            buf += chunk
            while b"\n" in buf:
                line, buf = buf.split(b"\n", 1)
                try:
                    cur = json.dumps(state(json.loads(line)), ensure_ascii=False)
                except (ValueError, KeyError):
                    continue
                if cur != last:
                    print(cur, flush=True)
                    last = cur


def tell(text: str) -> None:   # действия идут в фоне — итог сообщаем уведомлением
    subprocess.run(["notify-send", "-a", "Glide Link", "-i", "phone", "Телефон", text], check=False)


def act(dev: str, action: str, arg: str) -> int:
    if dev == "auto":
        st = request({"cmd": "status"}, timeout=5)
        on = [d for d in devices(st) if d["reachable"]] if st.get("ok") else []
        if not on:
            # нет телефона по Glide Link — пусть отправит KDE Connect (его помощник сам скажет, если и там пусто)
            kc = HERE / "glide-kdeconnect.py"
            if kc.exists():
                os.execv(sys.executable, [sys.executable, "-I", str(kc), "act", "auto", action] + ([arg] if arg else []))
            tell("Телефон не на связи")
            return 1
        dev = on[0]["id"]

    def run(req: dict, ok_text: str | None = None) -> int:
        r = request(dict(req, device=dev), timeout=600)
        if not r.get("ok"):
            tell(r.get("error") or "Не получилось")
            return 1
        if ok_text:
            print(ok_text)
        return 0

    if action in ("ping", "ring", "clipboard"):
        return run({"cmd": action})
    # сопряжение: устройство может быть ещё не на связи — без проверки «подключено»
    if action == "pair":
        r = request({"cmd": "connect", "target": dev}, timeout=15)
        return 0 if r.get("ok") else (tell(r.get("error") or "Не получилось"), 1)[1]
    if action in ("accept", "reject", "unpair"):
        r = request({"cmd": action, "device": dev}, timeout=15)
        return 0 if r.get("ok") else (tell(r.get("error") or "Не получилось"), 1)[1]
    if action == "text":
        text = arg or os.environ.get("QP_TEXT", "")
        if not text.strip():
            return 1
        t = text.strip()
        if t.startswith(("http://", "https://")) and "\n" not in t and " " not in t:
            return run({"cmd": "share-url", "url": t}, "Отправлено на телефон")
        return run({"cmd": "share-text", "text": text}, "Отправлено на телефон")
    if action in ("files", "upload"):
        r = subprocess.run(["zenity", "--file-selection", "--multiple", "--separator=\n", "--title=Отправить на телефон"],
                           capture_output=True, text=True)
        paths = [f for f in r.stdout.splitlines() if f]
        if not paths:
            return 0
        res = request({"cmd": "files-put", "device": dev, "paths": paths, "dir": arg} if action == "upload"
                      else {"cmd": "send-files", "device": dev, "paths": paths}, timeout=3600)
        if not res.get("ok"):
            tell(res.get("error") or "Не получилось")
            return 1
        bad = [x for x in res.get("results", []) if x.get("state") != "done"]
        tell(f"Отправлено файлов: {len(paths) - len(bad)}" + (f", ошибок: {len(bad)}" if bad else ""))
        return 1 if bad else 0
    simple = {"screen": {"cmd": "screen"}, "audio": {"cmd": "audio"},
              "screen-share": {"cmd": "screen-share"}, "audio-share": {"cmd": "audio-share"},
              "screen-stop": {"cmd": "stop-streams", "kind": "screen"},
              "audio-stop": {"cmd": "stop-streams", "kind": "audio"}}
    if action in simple:
        return run(simple[action])
    print(f"неизвестное действие: {action}", file=sys.stderr)
    return 2


def call(raw: str) -> int:
    try:
        req = json.loads(raw)
    except ValueError:
        print(json.dumps({"ok": False, "error": "не JSON"}))
        return 2
    r = request(req, timeout=float(req.pop("timeout", 30)) if isinstance(req, dict) else 30)
    r.pop("done", None)
    print(json.dumps(r, ensure_ascii=False))
    return 0 if r.get("ok") else 1


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "watch":
        sys.exit(watch())
    elif len(sys.argv) > 2 and sys.argv[1] == "call":
        sys.exit(call(sys.argv[2]))
    elif len(sys.argv) > 2 and sys.argv[1] == "connect":
        r = request({"cmd": "connect", "target": sys.argv[2]}, timeout=15)
        if not r.get("ok"):
            tell(r.get("error") or "Не удалось подключиться")
        sys.exit(0 if r.get("ok") else 1)
    elif len(sys.argv) > 3 and sys.argv[1] == "act":
        sys.exit(act(sys.argv[2], sys.argv[3], " ".join(sys.argv[4:])))
    else:
        print(__doc__)
        sys.exit(2)
