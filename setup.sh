#!/bin/sh
# Установщик Glide Shell для нового компьютера (niri + Quickshell). Спрашивает перед каждым изменением системы.
#   sh setup.sh               — поставить: зависимости, оболочку (службой), первые настройки, клавиши niri
#   sh setup.sh --yes         — то же без вопросов (ответ «да» на всё безопасное)
#   sh setup.sh --uninstall   — убрать оболочку, службу и клавиши (настройки и данные остаются; --purge — и их)
# Обновление уже установленной — sh install.sh (его же зовёт этот установщик).
set -u
src=$(cd "$(dirname "$0")" && pwd)
cfg="${XDG_CONFIG_HOME:-$HOME/.config}"
state="${XDG_STATE_HOME:-$HOME/.local/state}"
niri_dir="$cfg/niri"
niri_cfg="$niri_dir/config.kdl"
glide_kdl="$niri_dir/glide-shell.kdl"
yes=0; mode=install; purge=0
for a in "$@"; do
    case $a in
        --yes|-y) yes=1 ;;
        --uninstall) mode=uninstall ;;
        --purge) purge=1 ;;
        -h|--help) sed -n '2,6p' "$0"; exit 0 ;;
    esac
done

bold() { printf '\033[1m%s\033[0m\n' "$*"; }
ok() { printf '  \033[32m✓\033[0m %s\n' "$*"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$*"; }
ask() {   # ask "вопрос" → 0 — да
    [ "$yes" = 1 ] && return 0
    printf '  %s [Д/н] ' "$1"; read -r r || r=n
    case $r in ""|[ДдYy]*) return 0 ;; *) return 1 ;; esac
}
stamp=$(date +%Y%m%d-%H%M%S)

# ---------------------------------------------------------------- удаление
if [ "$mode" = uninstall ]; then
    bold "Удаление Glide Shell"
    systemctl --user disable --now glide-shell.service 2>/dev/null; ok "служба остановлена и выключена"
    rm -f "$cfg/systemd/user/glide-shell.service" "$cfg/systemd/user/glide-shell-rescue.service" \
          "$cfg/systemd/user/app-.service.d/glide-after-shell.conf"
    systemctl --user daemon-reload 2>/dev/null
    rm -rf "$cfg/quickshell/glide-shell" "$cfg/quickshell/glide-shell.prev"; ok "оболочка удалена"
    rm -f "$HOME/.local/bin/glide-shell" "${XDG_DATA_HOME:-$HOME/.local/share}/dbus-1/services/org.glide.Shell.service"
    if [ -f "$niri_cfg" ] && grep -q 'include "glide-shell.kdl"' "$niri_cfg"; then
        cp "$niri_cfg" "$niri_cfg.before-glide-uninstall-$stamp"
        sed -i '/include "glide-shell.kdl"/d; /^\/\/ Glide Shell: клавиши/d' "$niri_cfg"
        rm -f "$glide_kdl"; ok "клавиши niri убраны (копия конфига — $niri_cfg.before-glide-uninstall-$stamp)"
    fi
    # что установщик выключил в автозапуске niri (другие оболочки) — вернуть
    if [ -f "$niri_cfg" ] && grep -q "выключено установщиком Glide Shell" "$niri_cfg" \
       && ask "Вернуть в автозапуск niri то, что выключил установщик (другие бары, уведомления)?"; then
        sed -i -E 's/^(\s*)\/\/ (spawn-at-startup .*)  \/\/ выключено установщиком Glide Shell$/\1\2/' "$niri_cfg"
        ok "возвращено в автозапуск (заработает после перезахода)"
    fi
    replaced="$state/glide-shell/setup-replaced"
    if [ -s "$replaced" ] && ask "Вернуть то, что установщик выключил вместо Glide Shell ($(sed -n 's/^unit //p' "$replaced" | tr '\n' ' ' | sed 's/ $//')${replaced:+, запуск их демона уведомлений шиной})?"; then
        while read -r kind what; do
            case $kind in
                unit) systemctl --user enable --now "$what" 2>/dev/null && ok "включена $what" ;;
                dbus) rm -f "$what" && ok "убрано своё описание имени уведомлений на шине" ;;
            esac
        done < "$replaced"
        busctl --user call org.freedesktop.DBus /org/freedesktop/DBus org.freedesktop.DBus ReloadConfig >/dev/null 2>&1
        rm -f "$replaced"
    fi
    if [ "$purge" = 1 ]; then
        rm -rf "$cfg/glide-shell" "$state/glide-shell" "${XDG_CACHE_HOME:-$HOME/.cache}/glide-shell"
        ok "настройки, история и кэш удалены"
    else
        echo "  настройки и данные остались: $cfg/glide-shell, $state/glide-shell (удалить: --uninstall --purge)"
    fi
    exit 0
fi

bold "Glide Shell — установка"
echo "  Оболочка рабочего стола для niri: бар с островом, док, панель, уведомления, блокировка, обои."

# ---------------------------------------------------------------- 1. зависимости
bold "1. Зависимости"
need="quickshell niri python python-gobject wl-clipboard libnotify libpulse networkmanager curl ttf-jetbrains-mono-nerd inter-font util-linux glib2 xdg-utils"
want="python-pillow ffmpeg bluez-utils upower power-profiles-daemon udisks2 wf-recorder slurp grim tesseract tesseract-data-rus tesseract-data-eng kdeconnect gst-plugin-pipewire gst-plugins-good gst-plugins-bad gst-plugin-va"
# команда или файл, по которым видно, что пакет есть (без pacman — например, на другом дистрибутиве)
probe() {
    case $1 in
        quickshell) command -v qs ;; python) command -v python3 ;; python-gobject) python3 -c "import gi" ;;
        wl-clipboard) command -v wl-copy ;; libnotify) command -v notify-send ;; libpulse) command -v pactl ;;
        networkmanager) command -v nmcli ;; ttf-jetbrains-mono-nerd) fc-list | grep -qi "JetBrainsMono Nerd" ;;
        inter-font) fc-list | grep -qi "Inter" ;; util-linux) command -v setpriv ;; glib2) command -v gdbus ;;
        xdg-utils) command -v xdg-open ;; python-pillow) python3 -c "import PIL" ;; bluez-utils) command -v bluetoothctl ;;
        gst-plugin-pipewire) gst-inspect-1.0 --exists pipewiresrc ;; gst-plugins-good) gst-inspect-1.0 --exists matroskamux ;;
        gst-plugins-bad) gst-inspect-1.0 --exists h264parse ;; gst-plugin-va) gst-inspect-1.0 --exists vah264enc ;;
        upower) command -v upower ;; udisks2) command -v udisksctl ;; power-profiles-daemon) command -v powerprofilesctl ;; kdeconnect) command -v kdeconnect-cli ;;
        *) command -v "$1" ;;
    esac >/dev/null 2>&1
}
miss_need=""; miss_want=""
for p in $need; do probe "$p" || miss_need="$miss_need $p"; done
for p in $want; do probe "$p" || miss_want="$miss_want $p"; done
[ -z "$miss_need" ] && ok "всё нужное есть" || warn "не хватает:$miss_need"
[ -n "$miss_want" ] && warn "по желанию (обои-картинки и видео, Bluetooth, батарея, флешки, запись экрана, телефон):$miss_want"
if [ -n "$miss_need$miss_want" ]; then
    if command -v pacman >/dev/null; then
        list="$miss_need"
        [ -n "$miss_want" ] && ask "Поставить и необязательные?$miss_want" && list="$list $miss_want"
        if [ -n "$(echo $list)" ] && ask "Установить через pacman (нужен пароль sudo):$list?"; then
            sudo pacman -S --needed $list || warn "pacman не справился — поставь вручную и запусти setup.sh снова"
        fi
    else
        warn "это не Arch: поставь пакеты сам (названия — как в Arch, у твоего дистрибутива могут отличаться)"
    fi
fi
for p in quickshell niri python; do probe "$p" || { echo "Без $p оболочка не запустится — выход." >&2; exit 1; }; done

# ---------------------------------------------------------------- 2. другие оболочки
bold "2. Другие оболочки"
# Бар — один, уведомления и окно пароля polkit — только у одной программы. Ищем чужие: запущенные процессы,
# автозапуск niri, службы systemd и хозяина имени уведомлений на шине (так виден и незнакомый демон).
# «Да» — остановить сейчас и убрать из автозапуска (вернёт setup.sh --uninstall), «нет» — оставить, а у Glide
# Shell выключить то, что занято. Что выключено — в $replaced, чтобы удаление вернуло ровно это.
replaced="$state/glide-shell/setup-replaced"
bars="dms waybar ironbar eww ags"
notifd="mako dunst swaync fnott"
polkitd="polkit-gnome-authentication-agent-1 polkit-kde-authentication-agent-1 lxpolkit hyprpolkitagent polkit-mate-authentication-agent-1"
running() { pgrep -f "(^|/)$1( |\$)" >/dev/null; }
in_niri() { [ -f "$niri_cfg" ] && grep -vE '^\s*//' "$niri_cfg" | grep -qE "^\s*spawn(-sh)?-at-startup\s.*[\"/ ]$1[\" ]"; }
unit_on() { systemctl --user is-enabled --quiet "$1.service" 2>/dev/null || systemctl --user is-active --quiet "$1.service" 2>/dev/null; }
found=""; found_n=0; found_p=0
for x in $bars $notifd $polkitd; do
    how=""
    running "$x" && how="запущен"
    in_niri "$x" && how="${how:+$how, }автозапуск niri"
    unit_on "$x" && how="${how:+$how, }служба $x.service"
    [ -n "$how" ] || continue
    found="$found $x"
    case " $notifd dms " in *" $x "*) found_n=1 ;; esac
    case " $polkitd dms " in *" $x "*) found_p=1 ;; esac
    warn "$x — $how"
done
# уведомления у незнакомой программы: её служба (если есть) — тоже под замену
owner=$(busctl --user status org.freedesktop.Notifications 2>/dev/null)
owner_comm=$(echo "$owner" | sed -n 's/^Comm=//p' | head -1)
owner_unit=$(echo "$owner" | sed -n 's/^UserUnit=//p' | head -1)
case $owner_unit in glide-shell.service|"") owner_unit="" ;; esac
case $owner_comm in qs|quickshell) owner_unit="" ;; esac
case $owner_comm in qs|quickshell|"") ;; *)
    case " $found " in *" $owner_comm "*) ;; *)
        found_n=1; warn "уведомления держит «$owner_comm»${owner_unit:+ (служба $owner_unit)}" ;;
    esac ;;
esac
notifs=true; polkit=true
if [ -z "$found" ] && [ "$found_n" = 0 ]; then
    ok "других оболочек и демонов уведомлений не видно"
elif ask "Заменить их Glide Shell? (остановлю сейчас и уберу из автозапуска; вернуть — sh setup.sh --uninstall)"; then
    mkdir -p "$state/glide-shell"
    for x in $found; do
        if unit_on "$x"; then
            systemctl --user disable --now "$x.service" 2>/dev/null && echo "unit $x.service" >> "$replaced"
        fi
    done
    if [ -n "$owner_unit" ] && ! grep -qx "unit $owner_unit" "$replaced" 2>/dev/null \
       && systemctl --user disable --now "$owner_unit" 2>/dev/null; then
        echo "unit $owner_unit" >> "$replaced"
    fi
    if [ -f "$niri_cfg" ]; then
        cp "$niri_cfg" "$niri_cfg.before-glide-$stamp"
        for x in $found; do
            sed -i -E "/^\s*\/\//! s/^(\s*)(spawn(-sh)?-at-startup\s.*[\"\/ ]$x[\" ].*)\$/\1\/\/ \2  \/\/ выключено установщиком Glide Shell/" "$niri_cfg"
        done
        cmp -s "$niri_cfg" "$niri_cfg.before-glide-$stamp" && rm -f "$niri_cfg.before-glide-$stamp" \
            || ok "убраны из автозапуска niri (копия конфига — $niri_cfg.before-glide-$stamp)"
    fi
    for x in $found; do pkill -f "(^|/)$x( |\$)" 2>/dev/null; done
    case " qs quickshell $found " in *" $owner_comm "*) ;; *) [ -n "$owner_comm" ] && pkill -x "$owner_comm" 2>/dev/null ;; esac
    # mako, dunst и др. поднимаются шиной сами по первому уведомлению — своё описание имени важнее системного
    dbus_dir="${XDG_DATA_HOME:-$HOME/.local/share}/dbus-1/services"
    if grep -lqs "^Name=org.freedesktop.Notifications" "${GLIDE_SETUP_SYS_DBUS:-/usr/share/dbus-1/services}"/*.service 2>/dev/null \
       && [ ! -f "$dbus_dir/org.freedesktop.Notifications.service" ]; then
        mkdir -p "$dbus_dir"
        printf '%s\n' "# Glide Shell (setup.sh): уведомления — у Glide Shell, а не у демона, поднятого шиной" \
            "[D-BUS Service]" "Name=org.freedesktop.Notifications" "Exec=/usr/bin/systemctl --user start glide-shell.service" \
            "SystemdService=glide-shell.service" > "$dbus_dir/org.freedesktop.Notifications.service"
        echo "dbus $dbus_dir/org.freedesktop.Notifications.service" >> "$replaced"
        busctl --user call org.freedesktop.DBus /org/freedesktop/DBus org.freedesktop.DBus ReloadConfig >/dev/null 2>&1
    fi
    sleep 1
    ok "остановлены:$found — уведомления и окно пароля теперь у Glide Shell"
else
    [ "$found_n" = 1 ] && notifs=false
    [ "$found_p" = 1 ] && polkit=false
    # прежде отвечали «да» — своё описание имени на шине мешало бы шине поднять их демон
    if [ "$notifs" = false ] && grep -q "^dbus " "$replaced" 2>/dev/null; then
        grep "^dbus " "$replaced" | while read -r _ f; do rm -f "$f"; done
        sed -i '/^dbus /d' "$replaced"
        busctl --user call org.freedesktop.DBus /org/freedesktop/DBus org.freedesktop.DBus ReloadConfig >/dev/null 2>&1
    fi
    [ "$notifs" = false ] && ok "уведомления оставлены прежней программе — у Glide Shell они выключены (включить: Настройки → Уведомления)"
    [ "$polkit" = false ] && ok "окно пароля polkit оставлено прежней программе — у Glide Shell выключено"
    case " $found " in *" dms "*|*" waybar "*|*" ironbar "*|*" eww "*|*" ags "*)
        warn "второй бар останется — будут два бара сразу (убрать потом: sh setup.sh ещё раз)" ;; esac
fi

# ---------------------------------------------------------------- 3. оболочка
bold "3. Оболочка"
sh "$src/install.sh" || { echo "install.sh не справился — смотри сообщения выше" >&2; exit 1; }

# ---------------------------------------------------------------- 4. первые настройки
bold "4. Настройки"
conf="$cfg/glide-shell/config.json"
if [ -f "$conf" ]; then
    ok "настройки уже есть — оставляю ($conf)"
    # кроме уведомлений и polkit: они должны совпадать с выбором в п. 2, иначе две программы спорят за шину
    cur=$(python3 -I -c 'import json,sys; p=json.load(open(sys.argv[1])).get("panel", {})
print(str(p.get("notifications") is not False).lower(), str(p.get("polkit") is not False).lower())' "$conf" 2>/dev/null)
    if [ -n "$cur" ] && [ "$cur" != "$notifs $polkit" ]; then
        python3 -I "$src/tools/qp-config.py" set panel.notifications "$notifs" \
            && python3 -I "$src/tools/qp-config.py" set panel.polkit "$polkit" \
            && systemctl --user restart glide-shell.service 2>/dev/null
        onoff() { [ "$1" = true ] && echo "включены" || echo "выключены"; }
        ok "у Glide Shell уведомления $(onoff "$notifs"), окно пароля polkit — $(onoff "$polkit" | sed 's/ы$/о/') (по выбору выше)"
    fi
else
    mkdir -p "$cfg/glide-shell"
    cat > "$conf" <<EOF
{
  "panel": { "notifications": $notifs, "polkit": $polkit, "welcome": true },
  "disabled": []
}
EOF
    chmod 600 "$conf"
    ok "созданы: $conf"
    systemctl --user restart glide-shell.service 2>/dev/null
fi

# ---------------------------------------------------------------- 5. клавиши niri
bold "5. Клавиши niri"
if [ ! -f "$niri_cfg" ]; then
    warn "нет $niri_cfg — клавиши не добавлены (создай конфиг niri и запусти setup.sh снова)"
elif grep -q 'include "glide-shell.kdl"' "$niri_cfg"; then
    ok "уже подключены ($glide_kdl)"
elif ! niri validate -c "$niri_cfg" >/dev/null 2>&1; then
    warn "конфиг niri уже с ошибкой — клавиши не добавлены (подробности: niri validate). Исправь и запусти setup.sh снова"
elif ask "Добавить клавиши Glide Shell в niri (Mod+D — приложения, Super+Alt+L — замок, яркость, Print)?"; then
    # клавиши, которые у пользователя уже заняты, пропускаем — дубликат niri не примет
    taken() { grep -vE '^\s*//' "$niri_cfg" | grep -qE "^\s*$1(\s|\{)"; }
    {
        echo "// Glide Shell (setup.sh): клавиши оболочки. Убрать — удалить строку include в config.kdl."
        echo "binds {"
        taken "Mod\+D" || echo '    Mod+D hotkey-overlay-title="Приложения (Glide Shell)" { spawn "qs" "-c" "glide-shell" "ipc" "call" "panel" "launcher"; }'
        taken "Super\+Alt\+L" || echo '    Super+Alt+L hotkey-overlay-title="Заблокировать экран" { spawn "qs" "-c" "glide-shell" "ipc" "call" "lock" "lock"; }'
        taken "XF86MonBrightnessUp" || echo '    XF86MonBrightnessUp allow-when-locked=true { spawn-sh "sh ~/.config/quickshell/glide-shell/tools/glide-brightness.sh +10"; }'
        taken "XF86MonBrightnessDown" || echo '    XF86MonBrightnessDown allow-when-locked=true { spawn-sh "sh ~/.config/quickshell/glide-shell/tools/glide-brightness.sh -10"; }'
        taken "XF86Tools" || echo '    XF86Tools hotkey-overlay-title="Центр управления (короткое нажатие Super через keyd)" { spawn "qs" "-c" "glide-shell" "ipc" "call" "panel" "category" "control"; }'
        taken "Mod\+Shift\+Escape" || echo '    Mod+Shift+Escape hotkey-overlay-title="Перезапустить Glide Shell" { spawn "systemctl" "--user" "restart" "glide-shell.service"; }'
        echo "}"
    } > "$glide_kdl"
    cp "$niri_cfg" "$niri_cfg.before-glide-keys-$stamp"
    printf '\n// Glide Shell: клавиши оболочки\ninclude "glide-shell.kdl"\n' >> "$niri_cfg"
    if niri validate -c "$niri_cfg" >/dev/null 2>&1; then
        ok "добавлены: $glide_kdl (копия конфига — $niri_cfg.before-glide-keys-$stamp)"
        grep -c "spawn" "$glide_kdl" | xargs -I{} echo "  клавиш: {} (занятые у тебя — пропущены)"
    else
        cp "$niri_cfg.before-glide-keys-$stamp" "$niri_cfg"; rm -f "$glide_kdl"
        warn "niri не принял конфиг с клавишами — вернул как было. Подробности: niri validate"
    fi
fi

# ---------------------------------------------------------------- 5б. короткое нажатие Super
if [ "$yes" = 0 ] && ! systemctl is-active --quiet keyd 2>/dev/null && [ -f "$glide_kdl" ] \
   && ask "Открывать центр управления коротким нажатием Super? (ставит keyd — нужен пароль sudo; удержание Super — как обычно)"; then
    sudo sh "$src/extras/keyd/install.sh" && ok "короткое нажатие Super — центр управления (выключить: sudo sh extras/keyd/install.sh --remove)" \
        || warn "keyd не настроен — можно позже: sudo sh extras/keyd/install.sh"
fi

# ---------------------------------------------------------------- 6. запуск вместе с niri
bold "6. Запуск"
if systemctl --user is-active --quiet glide-shell.service; then
    ok "Glide Shell работает (служба glide-shell.service, запускается вместе с сеансом niri)"
else
    warn "служба не запущена — она стартует с graphical-session.target, то есть когда niri запущен как сеанс"
    warn "(niri-session или вход через экран входа). Запустить сейчас: systemctl --user start glide-shell"
fi
echo
bold "Готово."
echo "  Открыть панель — щелчок по острову сверху; приложения — Mod+D; настройки — шестерёнка в панели."
echo "  Лог — journalctl --user -u glide-shell; обновить — sh install.sh; удалить — sh setup.sh --uninstall"
echo "  Экран входа Glide (по желанию) — sudo sh greeter/install.sh --enable"
