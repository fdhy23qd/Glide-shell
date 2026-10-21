#!/usr/bin/env python3
"""Имитатор greetd для проверки экрана входа без настоящего входа (в greetd 0.10 нет fakegreet).

    python3 fake-greetd.py СОКЕТ [ЖУРНАЛ]       — затем: GREETD_SOCK=СОКЕТ GLIDE_GREETER_TEST=1 qs -p greeter/

Протокол greetd: длина сообщения (u32, порядок байт машины) + JSON.
Пароль «glide» — верный; «2fa» — после него спросит код (верный — 123456); остальное — ошибка.
В ЖУРНАЛ пишет по строке JSON на каждый запрос (пароли — звёздочками): сценарий проверки читает его.
"""
import json
import os
import socket
import struct
import sys

path = sys.argv[1]
log = open(sys.argv[2], "a", buffering=1) if len(sys.argv) > 2 else None


def note(event, **kw):
    if log:
        log.write(json.dumps({"event": event, **kw}, ensure_ascii=False) + "\n")


def send(conn, obj):
    data = json.dumps(obj).encode()
    conn.sendall(struct.pack("=I", len(data)) + data)


def recv(conn):
    head = conn.recv(4, socket.MSG_WAITALL)
    if len(head) < 4:
        return None
    (n,) = struct.unpack("=I", head)
    return json.loads(conn.recv(n, socket.MSG_WAITALL))


try:
    os.unlink(path)
except FileNotFoundError:
    pass
srv = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
srv.bind(path)
srv.listen(4)
note("listening")
while True:
    conn, _ = srv.accept()
    stage = None   # None | password | otp | ready
    while True:
        req = recv(conn)
        if req is None:
            break
        kind = req.get("type")
        if kind == "create_session":
            note("create_session", username=req.get("username"))
            stage = "password"
            send(conn, {"type": "auth_message", "auth_message_type": "secret", "auth_message": "Password: "})
        elif kind == "post_auth_message_response":
            resp = req.get("response") or ""
            note("response", stage=stage, response="*" * len(resp))
            if stage == "password" and resp == "glide":
                stage = "ready"
                send(conn, {"type": "success"})
            elif stage == "password" and resp == "2fa":
                stage = "otp"
                send(conn, {"type": "auth_message", "auth_message_type": "visible", "auth_message": "Код из приложения"})
            elif stage == "otp" and resp == "123456":
                stage = "ready"
                send(conn, {"type": "success"})
            else:
                stage = None
                send(conn, {"type": "error", "error_type": "auth_error", "description": "authentication failed"})
        elif kind == "start_session":
            note("start_session", cmd=req.get("cmd"), env=req.get("env"))
            send(conn, {"type": "success"} if stage == "ready" else
                 {"type": "error", "error_type": "error", "description": "session not ready"})
        elif kind == "cancel_session":
            note("cancel_session")
            stage = None
            send(conn, {"type": "success"})
        else:
            send(conn, {"type": "error", "error_type": "error", "description": "unknown request"})
    conn.close()
