#!/usr/bin/env python3
"""Ищет плагины и печатает JSON {"profile","categories","plugins"} для shell.qml.

Папки: <app>/plugins (встроенные) и ~/.config/glide-shell/plugins (пользовательские).
Пользовательский плагин с тем же id заменяет встроенный.

~/.config/glide-shell/config.json (настройки панели меняет tools/qp-config.py):
  {"panel": {"width": 380, "perPage": 6, "anim": 1, ...},
   "disabled": ["id"], "order": ["id"], "categoryOrder": ["media"],
   "categories": {"media": {"name": "Музыка", "icon": "♪"}},
   "placement": {"notes": ["quick", "dev"]},        # плагин сразу в нескольких категориях
   "profiles": {"study": {"categories": ["text", "quick"], "disabled": ["docker"],
                          "placement": {}}}}
Активный профиль: ~/.local/state/glide-shell/profile (меняется `ipc call panel profile <имя>`).
"""
import json, os, sys
from pathlib import Path

DEFAULT_CATS = {   # значки — Material Design Icons из JetBrainsMono Nerd Font
    "quick": ("Быстро", "\U000F140B"),       # молния
    "apps": ("Приложения", "\U000F003B"),    # сетка приложений
    "control": ("Управление", "\U000F1542"), # ползунки
    "notify": ("Уведомления", "\U000F009A"), # колокольчик
    "today": ("Сегодня", "\U000F00ED"),      # календарь
    "phone": ("Телефон", "\U000F011C"),     # KDE Connect
    "schedule": ("Расписание", "\U000F0474"), # шапочка выпускника
    "ai": ("ИИ", "\U000F167A"),              # робот
    "media": ("Медиа", "\U000F075A"),        # нота
    "clipboard": ("Буфер", "\U000F1267"),    # стопка буферов
    "dev": ("Разработка", "\U000F05C0"),     # </>
    "text": ("Текст", "\U000F0B34"),         # Aa
    "system": ("Система", "\U000F0A07"),     # монитор с графиком
    "net": ("Сеть", "\U000F059F"),           # глобус
    "power": ("Питание", "\U000F0425"),      # питание
}

app = Path(__file__).resolve().parent.parent
cfg_home = Path(os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config") / "glide-shell"
state_home = Path(os.environ.get("XDG_STATE_HOME") or Path.home() / ".local/state") / "glide-shell"
roots = [app / "plugins", cfg_home / "plugins"]

try:
    cfg = json.loads((cfg_home / "config.json").read_text())
except (OSError, ValueError):
    cfg = {}
try:
    profile = (state_home / "profile").read_text().strip()
except OSError:
    profile = ""
if profile in ("", "default"):
    profile, prof = "", {}
else:
    prof = (cfg.get("profiles") or {}).get(profile, {})

disabled = set(cfg.get("disabled", [])) | set(prof.get("disabled", []))
order = cfg.get("order", [])
cat_order = cfg.get("categoryOrder", list(DEFAULT_CATS))
placement = {**(cfg.get("placement") or {}), **(prof.get("placement") or {})}



API_VERSION = 1   # какую версию API плагинов понимает оболочка (docs/API.md)

def norm(c):
    if isinstance(c, list):
        return [str(x) for x in c if x] or ["quick"]
    return [str(c or "quick")]


found, every = {}, {}   # every — все плагины, включая выключенные (для экрана настроек)
for root in roots:
    if not root.is_dir():
        continue
    for d in sorted(p for p in root.iterdir() if p.is_dir()):
        try:
            m = json.loads((d / "plugin.json").read_text())
            pid, _ = m["id"], m["name"]
        except (OSError, ValueError, KeyError) as e:
            print(f"qp-discover: skip {d}: {e}", file=sys.stderr)
            continue
        # версия API: нет поля — 1 (так писались первые плагины); новее, чем знает оболочка, или не число — не грузим,
        # причина видна в «Настройки» → «Плагины»
        api = m.get("api", 1)
        problem = ""
        if not isinstance(api, int) or isinstance(api, bool):
            problem = f"поле api должно быть числом, а не {json.dumps(api, ensure_ascii=False)}"
        elif api > API_VERSION:
            problem = f"нужна более новая Glide Shell (API {api}, эта знает {API_VERSION})"
        every[pid] = {"id": pid, "name": m["name"], "icon": m.get("icon", ""),
                      "disabled": pid in disabled or m.get("enabled") is False, "problem": problem}
        if problem:
            print(f"qp-discover: {pid}: {problem}", file=sys.stderr)
            found.pop(pid, None)
            continue
        if pid in disabled or m.get("enabled") is False:
            found.pop(pid, None)
            continue
        m["dir"] = str(d)
        # время последней правки файлов плагина: ?v= в адресе QML — иначе движок берёт старую версию из кэша
        try:
            m["mtime"] = int(max(f.stat().st_mtime for f in d.iterdir() if f.is_file()))
        except ValueError:
            m["mtime"] = 0
        m["categories"] = norm(placement.get(pid, m.get("category")))
        m["category"] = m["categories"][0]
        found[pid] = m

plugins = list(found.values())
# порядок: config "order", затем "priority" из манифеста (больше — выше), затем имя папки
plugins.sort(key=lambda m: (order.index(m["id"]) if m["id"] in order else len(order), -int(m.get("priority", 0))))

cats = {}
for m in plugins:
    for i, cid in enumerate(m["categories"]):
        name, icon = DEFAULT_CATS.get(cid, (cid, (cid[:1].upper() or "•")))
        c = cats.setdefault(cid, {"id": cid, "name": name, "icon": icon})
        if i == 0 and m.get("categoryName"):
            c["name"] = m["categoryName"]
        if i == 0 and m.get("categoryIcon"):
            c["icon"] = m["categoryIcon"]
for cid, over in (cfg.get("categories") or {}).items():
    if cid in cats and isinstance(over, dict):
        cats[cid].update({k: v for k, v in over.items() if k in ("name", "icon")})

whitelist = prof.get("categories")
if whitelist:
    cats = {k: v for k, v in cats.items() if k in whitelist}
    cat_order = whitelist
    for m in plugins:
        m["categories"] = [c for c in m["categories"] if c in cats]
    plugins = [m for m in plugins if m["categories"]]

categories = sorted(cats.values(),
                    key=lambda c: cat_order.index(c["id"]) if c["id"] in cat_order else len(cat_order))
panel = cfg.get("panel") if isinstance(cfg.get("panel"), dict) else {}
print(json.dumps({"profile": profile, "categories": categories, "plugins": plugins,
                  "panel": panel, "allPlugins": sorted(every.values(), key=lambda p: p["name"].lower())},
                 ensure_ascii=False))
