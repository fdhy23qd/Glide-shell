#!/usr/bin/env python3
"""qp-run.py <copy|notify|copy+notify> -- команда...
Запускает команду; её stdout копируется в буфер и/или показывается уведомлением."""
import subprocess, sys

mode = sys.argv[1]
argv = sys.argv[sys.argv.index("--") + 1:]
NULL = subprocess.DEVNULL

def notify(body):
    try:
        subprocess.run(["notify-send", "-a", "Glide Shell", "Glide Shell", body[:700]], stderr=NULL)
    except OSError:
        print(body, file=sys.stderr)   # нет libnotify

try:
    r = subprocess.run(argv, capture_output=True, text=True)
except OSError as e:
    notify(f"Не удалось запустить {argv[0]}: {e}")
    sys.exit(1)

out, err = r.stdout.strip(), r.stderr.strip()
if r.returncode != 0:
    notify("Ошибка: " + (err.splitlines()[-1] if err else out or f"код {r.returncode}"))
    sys.exit(r.returncode)
if "copy" in mode and out:
    try:
        subprocess.run(["wl-copy"], input=out.encode(), stdout=NULL, stderr=NULL)
    except OSError:
        notify("Нет wl-copy (пакет wl-clipboard)")
if "notify" in mode:
    notify(out or "(пусто)")
