#!/usr/bin/env python3
"""Диспетчер задач: каждые N секунд печатает строку JSON с загрузкой системы и всеми процессами.

Читает /proc напрямую (без psutil). Панель держит процесс запущенным, только пока она открыта.
Формат: {"cpu": %, "mem": [всего_КиБ, занято_КиБ], "swap": [всего, занято], "ncpu": N,
         "procs": [[pid, имя, %ЦП от всех ядер, память_МиБ, свой?], ...]}
"""
import json
import os
import sys
import time

HZ = os.sysconf("SC_CLK_TCK")
PAGE = os.sysconf("SC_PAGE_SIZE")
NCPU = os.cpu_count() or 1
UID = os.getuid()


def cpu_total():
    with open("/proc/stat") as f:
        v = [int(x) for x in f.readline().split()[1:]]
    return sum(v), v[3] + v[4]   # всё время и простой (idle + iowait)


def meminfo():
    m = {}
    with open("/proc/meminfo") as f:
        for line in f:
            k, v = line.split(":", 1)
            m[k] = int(v.split()[0])
    total, swap = m["MemTotal"], m.get("SwapTotal", 0)
    return [total, total - m["MemAvailable"]], [swap, swap - m.get("SwapFree", 0)]


def processes():
    out = {}
    for p in os.listdir("/proc"):
        if not p.isdigit():
            continue
        try:
            with open(f"/proc/{p}/stat") as f:
                s = f.read()
            r = s.rfind(")")
            f2 = s[r + 2:].split()
            out[int(p)] = (s[s.find("(") + 1:r], int(f2[11]) + int(f2[12]), int(f2[21]) * PAGE,
                           os.stat(f"/proc/{p}").st_uid == UID)
        except (OSError, ValueError, IndexError):   # процесс успел завершиться
            pass
    return out


def main():
    interval = float(sys.argv[1]) if len(sys.argv) > 1 else 2.0
    prev_t, prev_i = cpu_total()
    prev = processes()
    prev_time = time.monotonic()
    pause = 0.5   # первый замер быстрее, чтобы панель не ждала
    while True:
        time.sleep(pause)
        pause = interval
        t, i = cpu_total()
        cur = processes()
        now = time.monotonic()
        dt = max(0.01, now - prev_time)
        rows = []
        for pid, (name, ticks, rss, mine) in cur.items():
            old = prev.get(pid)
            c = 100 * (ticks - old[1]) / HZ / dt / NCPU if old and old[0] == name else 0.0
            rows.append([pid, name, round(max(0.0, c), 1), round(rss / 1048576, 1), mine])
        mem, swap = meminfo()
        print(json.dumps({"cpu": round(100 * (1 - (i - prev_i) / max(1, t - prev_t)), 1),
                          "mem": mem, "swap": swap, "ncpu": NCPU, "procs": rows},
                         ensure_ascii=False), flush=True)
        prev_t, prev_i, prev, prev_time = t, i, cur, now


if __name__ == "__main__":
    try:
        main()
    except (KeyboardInterrupt, BrokenPipeError):
        pass
