#!/usr/bin/env python3
"""Каждые N секунд (аргумент, по умолчанию 2) печатает строку JSON с загрузкой CPU/RAM/диска/сети, температурой,
батареей и (если есть) GPU NVIDIA. Один процесс, пока панель открыта: не запускать Python заново на каждый замер."""
import json, shutil, subprocess, sys, time
from pathlib import Path


def cpu_times():
    v = list(map(int, open("/proc/stat").readline().split()[1:]))
    return v[3] + v[4], sum(v)


def net_bytes():
    rx = tx = 0
    for line in open("/proc/net/dev").read().splitlines()[2:]:
        name, data = line.split(":", 1)
        name = name.strip()
        if name == "lo" or name.startswith(("veth", "docker", "br-")):
            continue
        c = data.split()
        rx, tx = rx + int(c[0]), tx + int(c[8])
    return rx, tx



def sample(dt, i1, t1, n1):
    i2, t2 = cpu_times()
    n2 = net_bytes()
    mem = {}
    for l in open("/proc/meminfo"):
        k, v = l.split(":", 1)
        mem[k] = int(v.split()[0])
    disk = shutil.disk_usage("/")

    temps = []
    for p in Path("/sys/class/thermal").glob("thermal_zone*/temp"):
        try:
            temps.append(int(p.read_text()) / 1000)
        except (OSError, ValueError):
            pass

    bat = None
    for b in Path("/sys/class/power_supply").glob("BAT*"):
        try:
            bat = {"percent": int((b / "capacity").read_text()), "status": (b / "status").read_text().strip()}
            break
        except (OSError, ValueError):
            pass

    gpu = None
    if shutil.which("nvidia-smi"):
        try:
            out = subprocess.run(["nvidia-smi", "--query-gpu=utilization.gpu,temperature.gpu",
                                  "--format=csv,noheader,nounits"], capture_output=True, text=True, timeout=1).stdout
            u, t = [float(x) for x in out.strip().splitlines()[0].split(",")]
            gpu = {"percent": u, "temp": t}
        except (OSError, ValueError, IndexError, subprocess.TimeoutExpired):
            pass

    print(json.dumps({
        "cpu": 100 * (1 - (i2 - i1) / max(1, t2 - t1)),
        "mem_used": (mem["MemTotal"] - mem["MemAvailable"]) / 1048576,
        "mem_total": mem["MemTotal"] / 1048576,
        "disk_used": disk.used / 2**30, "disk_total": disk.total / 2**30,
        "temp": max(temps) if temps else None,
        "net_rx": max(0, n2[0] - n1[0]) / dt, "net_tx": max(0, n2[1] - n1[1]) / dt,
        "battery": bat, "gpu": gpu,
    }), flush=True)
    return i2, t2, n2


def main():
    interval = float(sys.argv[1]) if len(sys.argv) > 1 else 2.0
    i, t = cpu_times()
    n = net_bytes()
    pause = 0.4   # первый замер быстрее, чтобы панель не ждала
    while True:
        start = time.monotonic()
        time.sleep(pause)
        i, t, n = sample(time.monotonic() - start, i, t, n)
        pause = interval


if __name__ == "__main__":
    try:
        main()
    except (KeyboardInterrupt, BrokenPipeError):
        pass
