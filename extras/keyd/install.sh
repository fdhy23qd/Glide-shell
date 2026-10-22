#!/bin/sh
# Короткое нажатие Super → центр управления Glide Shell (через keyd: удержание Super — как обычно).
#   sudo sh extras/keyd/install.sh            — поставить keyd, настроить, включить
#   sudo sh extras/keyd/install.sh --remove   — выключить и вернуть прежний /etc/keyd/default.conf
# Клавиша в niri (XF86Tools) — в config.kdl пользователя (setup.sh добавляет её в glide-shell.kdl).
set -e
[ "$(id -u)" = 0 ] || { echo "запусти через sudo: sudo sh $0 $*" >&2; exit 1; }
src=$(cd "$(dirname "$0")" && pwd)
conf=/etc/keyd/default.conf
if [ "${1:-}" = "--remove" ]; then
    systemctl disable --now keyd 2>/dev/null || true
    if [ -f "$conf.before-glide" ]; then mv "$conf.before-glide" "$conf"; else rm -f "$conf"; fi
    echo "keyd выключен, прежняя настройка возвращена"
    exit 0
fi
pacman -Q keyd >/dev/null 2>&1 || pacman -S --needed --noconfirm keyd
mkdir -p /etc/keyd
# копия — только чужой настройки (повторная установка не должна сохранить нашу прежнюю как «исходную»)
if [ -f "$conf" ] && [ ! -f "$conf.before-glide" ] && ! grep -q "Glide Shell" "$conf"; then cp "$conf" "$conf.before-glide"; fi
install -m 644 "$src/super-tap.conf" "$conf"
systemctl enable --now keyd
keyd reload 2>/dev/null || true
echo "готово: короткое нажатие Super — центр управления. Выключить: sudo sh $0 --remove"
echo "если клавиатура ведёт себя странно: Backspace+Escape+Enter одновременно выключают keyd"
