#!/usr/bin/env python3
"""Состояние батареи из /sys/class/power_supply (без root и без UPower): JSON-список батарей.

{name, maker, model, tech, status, percent, health (ёмкость сейчас от новой, %), full_wh, design_wh, now_wh,
 cycles, watts (сколько тратит или получает сейчас), volts}. Поля, которых драйвер не даёт, — null.
Ёмкость — energy_* (мкВт·ч) или charge_* (мкА·ч × напряжение). Каталог — $GLIDE_POWER_SUPPLY (для тестов).
"""
import json
import os
from pathlib import Path

ROOT = Path(os.environ.get("GLIDE_POWER_SUPPLY") or "/sys/class/power_supply")


def num(d, name):
    try:
        return int((d / name).read_text().strip())
    except (OSError, ValueError):
        return None


def txt(d, name):
    try:
        return (d / name).read_text().strip()
    except OSError:
        return ""


def battery(d):
    volts = num(d, "voltage_now") or num(d, "voltage_min_design")
    vdesign = num(d, "voltage_min_design") or volts

    def wh(energy, charge, v):   # мкВт·ч → Вт·ч; или мкА·ч × мкВ
        e = num(d, energy)
        if e is not None:
            return e / 1e6
        c = num(d, charge)
        return c * v / 1e12 if c is not None and v else None

    full, design, now = wh("energy_full", "charge_full", vdesign), wh("energy_full_design", "charge_full_design", vdesign), \
        wh("energy_now", "charge_now", volts)
    p = num(d, "power_now")
    if p is None and num(d, "current_now") is not None and volts:
        p = num(d, "current_now") * volts / 1e6
    cycles = num(d, "cycle_count")
    r = lambda x, n=1: round(x, n) if x is not None else None
    return {
        "name": d.name, "maker": txt(d, "manufacturer"), "model": txt(d, "model_name"), "tech": txt(d, "technology"),
        "status": txt(d, "status"), "percent": num(d, "capacity"),
        "health": r(100 * full / design) if full and design else None,
        "full_wh": r(full), "design_wh": r(design), "now_wh": r(now),
        "cycles": cycles if cycles else None,           # 0 — драйвер не считает
        "watts": r(p / 1e6) if p else None, "volts": r(volts / 1e6, 2) if volts else None,
    }


def main():
    out = []
    if ROOT.is_dir():
        for d in sorted(ROOT.iterdir()):
            if txt(d, "type") == "Battery" and txt(d, "scope") != "Device":   # мышь, наушники — не батарея ноутбука
                out.append(battery(d))
    print(json.dumps(out, ensure_ascii=False))


if __name__ == "__main__":
    main()
