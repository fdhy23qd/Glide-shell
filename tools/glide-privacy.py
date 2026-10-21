#!/usr/bin/env python3
"""Кто сейчас держит камеру: печатает строку JSON {"camera": ["firefox", ...]} при каждом изменении.

Браузеры и мессенджеры открывают /dev/video* напрямую, мимо PipeWire, поэтому следим за самими
устройствами через inotify (открыли/закрыли — без опроса) и только тогда смотрим в /proc/*/fd, кто их
держит. Если камеру держит pipewire — ею пользуется приложение через PipeWire (имя — «PipeWire»).
wireplumber открывает камеру на долю секунды при запуске (опрос возможностей) — его не считаем.
Только стандартная библиотека: inotify через ctypes.
"""
import ctypes
import glob
import json
import os
import select
import struct
import sys
import time

IN_OPEN, IN_CLOSE_WRITE, IN_CLOSE_NOWRITE = 0x20, 0x08, 0x10
libc = ctypes.CDLL("libc.so.6", use_errno=True)


def holders(devices):
    real = {os.path.realpath(d) for d in devices}
    names = set()
    for pid in os.listdir("/proc"):
        if not pid.isdigit():
            continue
        try:
            for fd in os.listdir(f"/proc/{pid}/fd"):
                try:
                    if os.readlink(f"/proc/{pid}/fd/{fd}") in real:
                        with open(f"/proc/{pid}/comm") as f:
                            names.add(f.read().strip())
                        break
                except OSError:
                    continue
        except OSError:   # чужой процесс или уже завершился
            continue
    names.discard("wireplumber")
    return sorted("PipeWire" if n == "pipewire" else n for n in names)


def main():
    devices = sorted(glob.glob("/dev/video*"))
    if not devices:
        print(json.dumps({"camera": []}), flush=True)
        sys.stdin.read()   # камеры нет — просто ждём завершения оболочки
        return
    fd = libc.inotify_init1(os.O_NONBLOCK | os.O_CLOEXEC)
    for d in devices:
        libc.inotify_add_watch(fd, d.encode(), IN_OPEN | IN_CLOSE_WRITE | IN_CLOSE_NOWRITE)
    last = None
    while True:
        cur = holders(devices)
        if cur != last:
            print(json.dumps({"camera": cur}, ensure_ascii=False), flush=True)
            last = cur
        # ждём событие; закрылся stdin (оболочка завершилась) — выходим
        r, _, _ = select.select([fd, sys.stdin], [], [])
        if sys.stdin in r and not sys.stdin.buffer.read1(1):
            return
        time.sleep(0.3)   # открытия/закрытия идут пачкой — пересчитываем один раз
        try:
            while os.read(fd, 4096):
                pass
        except BlockingIOError:
            pass


if __name__ == "__main__":
    main()
