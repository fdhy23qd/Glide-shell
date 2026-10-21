#!/usr/bin/env python3
"""Заметки. Подкоманды: add (по умолчанию, текст в $QP_TEXT), list, open."""
import json, os, re, subprocess, sys, time

path = os.environ.get("QP_NOTES_FILE") or os.path.expanduser("~/glide-notes.md")
cmd = sys.argv[1] if len(sys.argv) > 1 else "add"
LINE = re.compile(r"^- \[([^\]]+)\] (.*?)(?:  _\((.*)\)_)?$")

if cmd == "add":
    text = " ".join(os.environ.get("QP_TEXT", "").split())
    try:
        w = json.loads(os.environ.get("QP_FOCUSED", "null")) or {}
    except ValueError:
        w = {}
    ctx = " — ".join(x for x in (w.get("app_id"), w.get("title")) if x)
    with open(path, "a", encoding="utf-8") as f:
        f.write(f"- [{time.strftime('%Y-%m-%d %H:%M')}] {text}" + (f"  _({ctx})_" if ctx else "") + "\n")
elif cmd == "list":   # последние сверху: "текст<TAB>текст · дата"
    try:
        lines = open(path, encoding="utf-8").read().splitlines()
    except OSError:
        lines = []
    for l in reversed(lines):
        m = LINE.match(l)
        if m and m[2].strip():
            note = m[2].replace("\t", " ")
            print(f"{note}\t{note}  ·  {m[1][5:]}")   # дата без года
elif cmd == "open":
    if not os.path.exists(path):
        open(path, "a").close()
    subprocess.Popen(["xdg-open", path], start_new_session=True,
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
