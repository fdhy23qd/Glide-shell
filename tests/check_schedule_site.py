#!/usr/bin/env python3
"""Живая проверка сайта СыктГУ: не поменялась ли вёрстка расписания (тесты — на сохранённой странице).

    python3 tests/check_schedule_site.py [ГРУППА]      группа по умолчанию — из настроек (panel.scheduleGroup)

Код выхода 0 — разбор работает; 1 — сайт ответил, но разобрать не вышло (вёрстка поменялась: обновить
tools/glide-schedule.py и tests/fixtures/schedule-group.html); 2 — нет сети или группы.
"""
import importlib.util
import json
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("sch", ROOT / "tools/glide-schedule.py")
sch = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sch)

group = sys.argv[1] if len(sys.argv) > 1 else ""
if not group:
    try:
        cfg = Path(os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config") / "glide-shell" / "config.json"
        group = json.loads(cfg.read_text()).get("panel", {}).get("scheduleGroup", "")
    except (OSError, ValueError):
        pass
if not group:
    sys.exit("нет группы: укажи её аргументом или в настройках расписания")
try:
    page = sch.post({"num_group": group, "searchdata": ""})
except Exception as e:
    print(f"сайт недоступен: {e}")
    sys.exit(2)
d = sch.parse(page)
lessons = sum(len(x["lessons"]) for x in d["days"])
problems = [p for p, bad in [("нет дат недели", not d["from"]), ("нет кнопки следующей недели", not d["curr"]),
                             ("нет дней", not d["days"])] if bad]
if problems:
    print(f"группа {group}: вёрстка изменилась? " + ", ".join(problems))
    sys.exit(1)
print(f"группа {group}: {d['from']}–{d['to']}, дней {len(d['days'])}, пар {lessons} — разбор работает")
