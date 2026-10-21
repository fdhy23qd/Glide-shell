#!/bin/sh
# Яркость экрана через logind — без root и без brightnessctl. Работает и без запущенного Glide Shell;
# если он запущен, показывает новое значение в острове.
#   glide-brightness.sh +10   — ярче на 10 %
#   glide-brightness.sh -10   — темнее на 10 %
#   glide-brightness.sh 50    — ровно 50 %
d=$(ls -d /sys/class/backlight/* 2>/dev/null | head -1)
[ -n "$d" ] || { echo "нет подсветки в /sys/class/backlight" >&2; exit 1; }
cur=$(cat "$d/brightness"); max=$(cat "$d/max_brightness")
pct=$(( (cur * 100 + max / 2) / max ))
case "${1:-}" in
    +[0-9]*) pct=$((pct + ${1#+})) ;;
    -[0-9]*) pct=$((pct - ${1#-})) ;;
    [0-9]*)  pct=$1 ;;
    *) echo "использование: $0 +N | -N | N" >&2; exit 2 ;;
esac
[ "$pct" -gt 100 ] && pct=100
[ "$pct" -lt 1 ] && pct=1   # не гасим экран в ноль
new=$(( (pct * max + 50) / 100 )); [ "$new" -lt 1 ] && new=1
busctl call org.freedesktop.login1 /org/freedesktop/login1/session/auto org.freedesktop.login1.Session \
    SetBrightness ssu backlight "${d##*/}" "$new" || exit 1
qs -c glide-shell ipc call panel brightnessOsd "$pct" >/dev/null 2>&1 &
echo "$pct"
