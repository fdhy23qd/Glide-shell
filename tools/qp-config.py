#!/usr/bin/env python3
"""Меняет ~/.config/glide-shell/config.json, не трогая остальные ключи.

  qp-config.py set panel.width 440        значение — JSON (true, 120, "текст")
  qp-config.py toggle-disabled <id>       включить/выключить плагин
  qp-config.py move-category <id> <±1>    сдвинуть категорию в порядке
  qp-config.py reset-panel                сбросить настройки панели
"""
import json, os, sys
from pathlib import Path

cfg_home = Path(os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config") / "glide-shell"
path = cfg_home / "config.json"

try:
    cfg = json.loads(path.read_text())
    if not isinstance(cfg, dict):
        raise ValueError
except OSError:
    cfg = {}
except ValueError:
    sys.exit(f"qp-config: {path} повреждён, не перезаписываю")

cmd, args = sys.argv[1], sys.argv[2:]
if cmd == "set":
    *parents, last = args[0].split(".")
    node = cfg
    for k in parents:
        node = node.setdefault(k, {})
    node[last] = json.loads(args[1])
elif cmd == "toggle-disabled":
    dis = cfg.setdefault("disabled", [])
    if args[0] in dis:
        dis.remove(args[0])
    else:
        dis.append(args[0])
elif cmd == "move-category":
    # текущий видимый порядок приходит третьим аргументом, чтобы учесть категории не из списка
    order = json.loads(args[2]) if len(args) > 2 else cfg.get("categoryOrder", [])
    if args[0] in order:
        i = order.index(args[0])
        j = max(0, min(len(order) - 1, i + int(args[1])))
        order.insert(j, order.pop(i))
        cfg["categoryOrder"] = order
elif cmd == "reset-panel":
    cfg.pop("panel", None)
else:
    sys.exit(f"qp-config: неизвестная команда {cmd}")

cfg_home.mkdir(parents=True, exist_ok=True)
tmp = path.with_suffix(".tmp")
tmp.write_text(json.dumps(cfg, ensure_ascii=False, indent=2) + "\n")
os.replace(tmp, path)
