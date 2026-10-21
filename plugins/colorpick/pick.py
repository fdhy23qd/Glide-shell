#!/usr/bin/env python3
"""Пипетка niri: выбрать цвет на экране, напечатать HEX и rgb()."""
import json, subprocess, sys

r = subprocess.run(["niri", "msg", "-j", "pick-color"], capture_output=True, text=True)
try:
    rgb = json.loads(r.stdout)["rgb"]
except (ValueError, KeyError, TypeError):
    sys.exit("цвет не выбран")
c = [round(x * 255) for x in rgb]
print(f"#{c[0]:02x}{c[1]:02x}{c[2]:02x}")
print(f"rgb({c[0]}, {c[1]}, {c[2]})", file=sys.stderr)
