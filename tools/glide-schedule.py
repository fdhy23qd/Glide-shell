#!/usr/bin/env python3
"""Расписание пар СыктГУ (campus.syktsu.ru) для Glide Shell: печатает JSON.

    glide-schedule.py ГРУППА [now|next] [--force]

Сайт — форма с POST (num_group), неделя — кнопки «тек./след.» (curr/next = «дата-понедельника_группа»).
Таблица с пропущенными <tr>, поэтому разбираем по ячейкам: день → № → время → занятие (одна ячейка
colspan=2 — для всей группы, две половины — подгруппы 1 и 2). Кэш — ~/.local/state/glide-shell/schedule-*.json
на 3 часа: сайт университета не дёргаем часто, без сети отдаём последнее.
"""
import datetime as dt
import hashlib
import html
import json
import os
import re
import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path

URL = "https://campus.syktsu.ru/schedule/group/"
FRESH = 3 * 3600
PAIR_MIN = 90
state = Path(os.environ.get("XDG_STATE_HOME") or Path.home() / ".local/state") / "glide-shell"


def post(fields):
    data = urllib.parse.urlencode(fields).encode()
    req = urllib.request.Request(URL, data=data, headers={"User-Agent": "Mozilla/5.0 (Glide Shell)"})
    with urllib.request.urlopen(req, timeout=20) as r:
        return r.read().decode("utf-8", "replace")


def text(cell):
    cell = re.sub(r"<br\s*/?>", "\n", cell)
    return [l.strip() for l in html.unescape(re.sub(r"<[^>]+>", "", cell)).splitlines() if l.strip()]


def lesson(cell, subgroup):
    lines = text(cell)
    if not lines:
        return None
    title, rest = lines[0], lines[1:]
    kind = ""
    m = re.match(r"^(.*?)\s*\(([^()]*)\)\s*$", title)   # «Математика (л.)» → тип занятия
    if m:
        title, kind = m.group(1), m.group(2)
    teacher, room = "", ""
    for l in rest:
        if l.lower().startswith("подгруппа"):
            subgroup = subgroup or int(re.sub(r"\D", "", l) or 0)
            continue
        if not teacher:
            parts = [p.strip() for p in l.rsplit(",", 1)]
            teacher, room = (parts[0], parts[1]) if len(parts) == 2 else (l, "")
    kinds = {"л.": "лекция", "пр.": "практика", "лаб.": "лабораторная", "сем.": "семинар"}
    return {"title": title, "kind": kinds.get(kind, kind), "teacher": teacher, "room": room, "subgroup": subgroup}


def parse(page):
    head = re.search(r"на неделю c ([\d.]+) по ([\d.]+)", page)
    upd = re.search(r"Расписание обновлено ([^<.]+(?:\.\d+)*[^<]*?)\.\s*<", page)
    week = re.search(r'<option value="[^"]*" selected="selected"[^>]*>([^<]+)</option>', page)
    curr = re.search(r'name="curr" value="([^"]+)"', page)
    table = page[page.find('class="schedule"'):]
    table = table[:table.find("</table>")]
    days, day, num, time_ = [], None, None, None
    pending = []   # ячейки занятия одной пары (1 — вся группа, 2 — подгруппы)
    for m in re.finditer(r"<td([^>]*)>(.*?)</td>", table, re.S):
        attrs, cell = m.group(1), m.group(2)
        if "dayofweek" in attrs:
            t = text(cell)
            day = {"name": t[0], "date": t[1].strip("()") if len(t) > 1 else "", "today": "today" in attrs, "lessons": []}
            days.append(day)
            continue
        if day is None:
            continue
        plain = text(cell)
        if num is None and plain and re.fullmatch(r"\d", plain[0]) and "colspan" not in attrs:
            num = int(plain[0])
            continue
        if num is not None and time_ is None and plain and re.fullmatch(r"\d\d:\d\d", plain[0]):
            time_ = plain[0]
            continue
        if num is None or time_ is None:
            continue
        pending.append(cell)
        if "colspan" in attrs or len(pending) == 2:   # пара собрана
            halves = pending if len(pending) == 2 else [pending[0]]
            for i, c in enumerate(halves):
                le = lesson(c, (i + 1) if len(halves) == 2 else 0)
                if le:
                    h, mnt = map(int, time_.split(":"))
                    end = (dt.datetime(2000, 1, 1, h, mnt) + dt.timedelta(minutes=PAIR_MIN)).strftime("%H:%M")
                    day["lessons"].append({"n": num, "start": time_, "end": end, **le})
            num, time_, pending = None, None, []
    return {"from": head.group(1) if head else "", "to": head.group(2) if head else "",
            "week": week.group(1).strip() if week else "", "updated": upd.group(1).strip() if upd else "",
            "curr": curr.group(1) if curr else "", "days": days}


def fetch(group, which):
    page = post({"num_group": group, "searchdata": ""})
    data = parse(page)
    if which == "next" and data["curr"]:
        data = parse(post({"next": data["curr"]}))
    if not data["days"]:
        raise LookupError(f"расписание для группы «{group}» не найдено")
    return data


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if not args:
        print(__doc__)
        sys.exit(2)
    group, which = args[0], (args[1] if len(args) > 1 else "now")
    key = hashlib.sha1(f"{group}|{which}|{dt.date.today().isocalendar()[:2]}".encode()).hexdigest()[:12]
    cache = state / f"schedule-{key}.json"
    try:
        cached = json.loads(cache.read_text())
        if "--force" not in sys.argv and time.time() - cached.get("fetched", 0) < FRESH:
            print(json.dumps(cached, ensure_ascii=False))
            return
    except (OSError, ValueError):
        cached = None
    try:
        data = fetch(group, which)
        data.update(group=group, which=which, fetched=int(time.time()))
        state.mkdir(parents=True, exist_ok=True)
        for old in state.glob("schedule-*.json"):   # прошлые недели не копим
            if old != cache and time.time() - old.stat().st_mtime > 14 * 86400:
                old.unlink(missing_ok=True)
        cache.write_text(json.dumps(data, ensure_ascii=False))
    except Exception as e:
        data = dict(cached, stale=True) if cached else {"error": str(e) or e.__class__.__name__, "group": group}
    print(json.dumps(data, ensure_ascii=False))


if __name__ == "__main__":
    main()
