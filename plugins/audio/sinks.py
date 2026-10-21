#!/usr/bin/env python3
import json, subprocess
try:
    sinks = json.loads(subprocess.run(["pactl", "-f", "json", "list", "sinks"],
                                      capture_output=True, text=True, timeout=3).stdout)
    default = subprocess.run(["pactl", "get-default-sink"], capture_output=True, text=True,
                             timeout=3).stdout.strip()
except (OSError, ValueError, subprocess.TimeoutExpired):
    sinks, default = [], ""
def title(s):
    """Человеческое имя выхода; у некоторых карт PipeWire отдаёт описание строкой "(null)"."""
    props = s.get("properties", {})
    for v in (s.get("description"), props.get("device.description"), props.get("node.nick"),
              props.get("device.product.name"), props.get("device.nick")):
        if v and v != "(null)":
            return v
    return s["name"]


for s in sinks:
    mark = "● " if s["name"] == default else "  "
    print(f"{s['name']}\t{mark}{title(s)}")
