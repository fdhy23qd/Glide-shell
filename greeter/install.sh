#!/bin/sh
# Экран входа Glide для greetd. Запускать через sudo из своей сессии:
#   sudo sh greeter/install.sh            — поставить файлы (вход не меняется)
#   sudo sh greeter/install.sh --enable   — то же + greetd запускает экран входа Glide (копия конфига — рядом)
#   sudo sh greeter/install.sh --disable  — вернуть прежний экран входа из копии (DMS и т.п.)
# greetd НЕ перезапускается: это выкинуло бы из сеанса. Новый экран входа появится после перезагрузки.
# Если с ним что-то не так: Ctrl+Alt+F2 → войти в консоли → sudo sh …/greeter/install.sh --disable → reboot.
set -e
[ "$(id -u)" = 0 ] || { echo "запусти через sudo: sudo sh $0 $*" >&2; exit 1; }
src=$(cd "$(dirname "$0")" && pwd)
share=/usr/local/share/glide-greeter
conf=/etc/greetd/config.toml
user=${SUDO_USER:-}
home=$(getent passwd "$user" | cut -d: -f6)

if [ "${1:-}" = "--disable" ]; then
    last=$(ls -1t /etc/greetd/config.toml.before-glide-* 2>/dev/null | head -1)
    if [ -n "$last" ]; then
        cp "$last" "$conf"
        echo "вход возвращён из $last:"
    else
        sed -i 's|^command = .*|command = "/usr/bin/dms-greeter --command niri --cache-dir /var/cache/dms-greeter"|' "$conf"
        echo "копии не нашлось — поставлен dms-greeter:"
    fi
    grep "^command" "$conf"
    echo "подействует после перезагрузки"
    exit 0
fi

command -v greetd >/dev/null || { echo "greetd не установлен" >&2; exit 1; }
command -v niri >/dev/null && command -v qs >/dev/null || { echo "нужны niri и quickshell (qs)" >&2; exit 1; }
id greeter >/dev/null 2>&1 || { echo "нет пользователя greeter (его создаёт пакет greetd)" >&2; exit 1; }

# ---- файлы ----
install -d -m 755 "$share"
install -m 644 "$src"/shell.qml "$src"/Look.qml "$src"/LoginView.qml "$share"/
install -m 644 "$src"/Reveal.qml "$share"/   # ссылка на ../Reveal.qml (общий с Glide Shell): уход фона после пароля
install -m 755 "$src"/glide-greeter /usr/local/bin/glide-greeter
install -m 755 "$src"/glide-session /usr/local/bin/glide-session   # чистит консоль VT перед сеансом

# ---- niri экрана входа: раскладки и мониторы — как у пользователя ----
niricfg="$home/.config/niri/config.kdl"
xkb=""
[ -f "$niricfg" ] && xkb=$(awk '/xkb[ \t]*\{/{f=1;next} f&&/\}/{f=0} f' "$niricfg" \
    | grep -vE '^[[:space:]]*//' | grep -E '^[[:space:]]*(layout|options|variant|model|rules)[[:space:]]' || true)
[ -n "$xkb" ] || xkb='layout "us,ru"'
outputs=""
if [ -f "$home/.config/niri/dms/outputs.kdl" ]; then
    outputs=$(grep -vE '^[[:space:]]*//' "$home/.config/niri/dms/outputs.kdl")
elif [ -f "$niricfg" ]; then
    outputs=$(awk '/^output[ \t]/{f=1} f{print} f&&/^\}/{f=0}' "$niricfg")
fi
XKB="$xkb" OUTPUTS="$outputs" SHARE="$share" WHO="$user" python3 -I - "$src/niri.kdl.in" "$share/niri.kdl" <<'EOF'
import os, sys
t = open(sys.argv[1]).read()
xkb = "\n".join("            " + l.strip() for l in os.environ["XKB"].splitlines() if l.strip())
t = (t.replace("@XKB@", xkb).replace("@OUTPUTS@", os.environ["OUTPUTS"])
      .replace("@SHARE@", os.environ["SHARE"]).replace("@USER@", os.environ["WHO"] or "—"))
open(sys.argv[2], "w").write(t)
EOF
chmod 644 "$share/niri.kdl"
if ! niri validate -c "$share/niri.kdl" >/dev/null 2>&1; then
    echo "niri.kdl экрана входа не прошёл проверку (niri validate) — исправь $share/niri.kdl" >&2
    niri validate -c "$share/niri.kdl" >&2 || true
    exit 1
fi

# ---- память (кто и в какой сеанс входил) и доступ к теме пользователя ----
install -d -o greeter -g greeter -m 750 /var/cache/glide-greeter
if [ -n "$home" ] && command -v setfacl >/dev/null; then
    # чтение настроек Glide Shell пользователя (акцент, тон, фон замка): только проход по папкам и чтение
    setfacl -m g:greeter:rx "$home" "$home/.config" 2>/dev/null || true
    [ -d "$home/.config/glide-shell" ] && setfacl -m g:greeter:rx "$home/.config/glide-shell" 2>/dev/null || true
fi
echo "экран входа Glide установлен: $share, /usr/local/bin/glide-greeter, /usr/local/bin/glide-session"

# ---- включить ----
if [ "${1:-}" = "--enable" ]; then
    backup="/etc/greetd/config.toml.before-glide-$(date +%Y%m%d-%H%M%S)"
    cp "$conf" "$backup"
    if grep -q '^command = ' "$conf"; then
        sed -i '0,/^command = .*/s||command = "/usr/local/bin/glide-greeter"|' "$conf"
    else
        printf '\n[default_session]\ncommand = "/usr/local/bin/glide-greeter"\nuser = "greeter"\n' >> "$conf"
    fi
    echo "greetd: экран входа Glide включён (прежний конфиг — $backup)"
    grep "^command" "$conf"
    echo "подействует после перезагрузки. Если что-то не так: Ctrl+Alt+F2 → вход в консоли →"
    echo "  sudo sh $src/install.sh --disable && reboot"
else
    echo "greetd не менялся. Включить: sudo sh $0 --enable"
fi
