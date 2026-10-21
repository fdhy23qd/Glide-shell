#!/usr/bin/env python3
"""Праздники и производственный календарь России для календаря Glide Shell.

    glide-holidays.py ГОД      — JSON {"year", "source", "days": {"MM-DD": {"t": off|work|short, "name"}}}

В "days" только отличия от обычной недели: выходной в будний день (off), рабочая суббота/воскресенье (work),
сокращённый предпраздничный день (short), плюс названия праздников. Переносы — с isdayoff.ru (без ключа,
отправляется только год), кэш ~/.local/state/glide-shell/holidays-ГОД.json на 30 дней. Нет сети или года ещё
нет на сайте — только государственные праздники по закону (без переносов), source "builtin".
"""
import datetime as dt
import json
import os
import sys
import time
import urllib.request
from pathlib import Path

state = Path(os.environ.get("XDG_STATE_HOME") or Path.home() / ".local/state") / "glide-shell"
FRESH = 30 * 86400

# ст. 112 ТК РФ: нерабочие праздничные дни
NAMES = {
    "01-01": "Новый год", "01-02": "Новогодние каникулы", "01-03": "Новогодние каникулы",
    "01-04": "Новогодние каникулы", "01-05": "Новогодние каникулы", "01-06": "Новогодние каникулы",
    "01-07": "Рождество Христово", "01-08": "Новогодние каникулы",
    "02-23": "День защитника Отечества", "03-08": "Международный женский день",
    "05-01": "Праздник Весны и Труда", "05-09": "День Победы",
    "06-12": "День России", "11-04": "День народного единства",
}


def builtin(year):
    days = {}
    for md, name in NAMES.items():
        d = dt.date(year, int(md[:2]), int(md[3:]))
        days[md] = {"name": name}
        if d.weekday() < 5:
            days[md]["t"] = "off"
    return days


def parse(year, codes):
    """Строка isdayoff (?pre=1): по цифре на день — 0 рабочий, 1 выходной, 2 сокращённый, 4 рабочий (особый)."""
    start = dt.date(year, 1, 1)
    n = (dt.date(year + 1, 1, 1) - start).days
    if len(codes) != n or set(codes) - set("0124"):
        raise ValueError("неожиданный ответ")
    days = {}
    for i, c in enumerate(codes):
        d = start + dt.timedelta(days=i)
        md = d.strftime("%m-%d")
        weekend = d.weekday() >= 5
        entry = {}
        if c == "1" and not weekend:
            entry["t"] = "off"
        elif c in "024" and weekend:
            entry["t"] = "work"
        elif c == "2":
            entry["t"] = "short"
        if md in NAMES:
            entry["name"] = NAMES[md]
        if entry:
            days[md] = entry
    return days


def fetch(year):
    url = f"https://isdayoff.ru/api/getdata?year={year}&pre=1"
    req = urllib.request.Request(url, headers={"User-Agent": "glide-shell"})
    with urllib.request.urlopen(req, timeout=10) as r:
        return r.read().decode().strip()


def main():
    year = int(sys.argv[1]) if len(sys.argv) > 1 else dt.date.today().year
    cache = state / f"holidays-{year}.json"
    try:
        old = json.loads(cache.read_text())
    except (OSError, ValueError):
        old = None
    if old and old.get("source") == "isdayoff" and time.time() - cache.stat().st_mtime < FRESH:
        print(json.dumps(old, ensure_ascii=False))
        return
    try:
        out = {"year": year, "source": "isdayoff", "days": parse(year, fetch(year))}
        state.mkdir(parents=True, exist_ok=True)
        cache.write_text(json.dumps(out, ensure_ascii=False))
    except Exception:
        # сети нет — прежние данные с сайта лучше встроенных
        out = old if old and old.get("source") == "isdayoff" else {"year": year, "source": "builtin", "days": builtin(year)}
    print(json.dumps(out, ensure_ascii=False))


if __name__ == "__main__":
    main()
