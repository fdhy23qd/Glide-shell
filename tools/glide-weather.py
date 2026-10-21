#!/usr/bin/env python3
"""Погода для Glide Shell: печатает JSON для Weather.qml.

    glide-weather.py [город]

Данные — Open-Meteo (без ключа). Место: город из настроек (геокодер Open-Meteo, по-русски) или,
если он не задан, по IP (ipwho.is). Место кэшируется в ~/.local/state/glide-shell/weather-place.json,
прогноз — в weather.json на 20 минут: частые вызовы сеть не трогают.
"""
import json
import os
import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path

state = Path(os.environ.get("XDG_STATE_HOME") or Path.home() / ".local/state") / "glide-shell"
place_file, cache_file = state / "weather-place.json", state / "weather.json"
FRESH = 20 * 60


def get(url):
    req = urllib.request.Request(url, headers={"User-Agent": "glide-shell"})
    with urllib.request.urlopen(req, timeout=10) as r:
        return json.loads(r.read().decode())


def local_tz():
    tz = os.environ.get("TZ", "").lstrip(":")
    if not tz:
        real = os.path.realpath("/etc/localtime")
        tz = real.split("zoneinfo/", 1)[1] if "zoneinfo/" in real else ""
    return tz


def save(place):
    state.mkdir(parents=True, exist_ok=True)
    place_file.write_text(json.dumps(place, ensure_ascii=False))
    return place


def locate_city(name, query):
    q = urllib.parse.urlencode({"name": name, "count": 1, "language": "ru", "format": "json"})
    res = (get("https://geocoding-api.open-meteo.com/v1/search?" + q).get("results") or [None])[0]
    if not res:
        raise LookupError(f"город «{name}» не найден")
    return save({"name": res["name"], "lat": res["latitude"], "lon": res["longitude"], "query": query})


def locate(city):
    """Место {name, lat, lon, query}; query — по чему искали ("" — по IP)."""
    try:
        cached = json.loads(place_file.read_text())
        if cached.get("query") == city:
            return cached
    except (OSError, ValueError):
        pass
    if city:
        return locate_city(city, city)
    else:
        res = get("https://ipwho.is/?lang=ru")
        if not res.get("success", True):
            raise LookupError("не удалось определить место по IP")
        tz = local_tz()
        if tz and "/" in tz and (res.get("timezone") or {}).get("id") != tz:
            # IP из другого пояса (VPN) — надёжнее город системного часового пояса
            return locate_city(tz.split("/")[-1].replace("_", " "), "")
        place = {"name": res.get("city") or "", "lat": res["latitude"], "lon": res["longitude"]}
    place["query"] = city
    return save(place)


def forecast(place):
    q = urllib.parse.urlencode({
        "latitude": place["lat"], "longitude": place["lon"], "timezone": "auto",
        "current": "temperature_2m,apparent_temperature,relative_humidity_2m,weather_code,wind_speed_10m,is_day",
        "hourly": "temperature_2m,weather_code,is_day",
        "daily": "weather_code,temperature_2m_max,temperature_2m_min,sunrise,sunset",
        "forecast_days": 5, "wind_speed_unit": "ms",
    })
    d = get("https://api.open-meteo.com/v1/forecast?" + q)
    cur, hourly, daily = d["current"], d["hourly"], d["daily"]
    now = cur["time"][:13]   # "2026-10-20T08"
    start = next((i for i, t in enumerate(hourly["time"]) if t[:13] >= now), 0)
    return {
        "place": place["name"], "updated": int(time.time()),
        "now": {"temp": cur["temperature_2m"], "feels": cur["apparent_temperature"],
                "humidity": cur["relative_humidity_2m"], "wind": cur["wind_speed_10m"],
                "code": cur["weather_code"], "day": bool(cur["is_day"])},
        "hours": [{"time": hourly["time"][i][11:16], "temp": hourly["temperature_2m"][i],
                   "code": hourly["weather_code"][i], "day": bool(hourly["is_day"][i])}
                  for i in range(start + 1, min(start + 13, len(hourly["time"])), 2)],
        "days": [{"date": daily["time"][i], "max": daily["temperature_2m_max"][i],
                  "min": daily["temperature_2m_min"][i], "code": daily["weather_code"][i]}
                 for i in range(len(daily["time"]))],
        "sunrise": daily["sunrise"][0][11:16], "sunset": daily["sunset"][0][11:16],
    }


def main():
    city = (sys.argv[1] if len(sys.argv) > 1 else "").strip()
    try:
        cached = json.loads(cache_file.read_text())
        if cached.get("query") == city and time.time() - cached.get("updated", 0) < FRESH:
            print(json.dumps(cached, ensure_ascii=False))
            return
    except (OSError, ValueError):
        cached = None
    try:
        data = forecast(locate(city))
        data["query"] = city
        state.mkdir(parents=True, exist_ok=True)
        cache_file.write_text(json.dumps(data, ensure_ascii=False))
    except Exception as e:   # нет сети и т. п. — отдаём старое, если оно про тот же город
        if cached and cached.get("query") == city:
            cached["stale"] = True
            data = cached
        else:
            data = {"error": str(e) or e.__class__.__name__, "query": city}
    print(json.dumps(data, ensure_ascii=False))


if __name__ == "__main__":
    main()
