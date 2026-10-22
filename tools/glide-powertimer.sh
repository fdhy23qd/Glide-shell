#!/bin/sh
# Выключение/сон по таймеру для Glide Shell — таймером systemd (переживает перезапуск оболочки):
#   glide-powertimer.sh set МИНУТ poweroff|suspend   — поставить (прежний снимается)
#   glide-powertimer.sh cancel                       — снять
# Состояние — ~/.local/state/glide-shell/powertimer ({"action","end"}): по нему остров показывает остаток.
# За минуту до срока — уведомление (отдельный таймер …-warn).
set -u
st="${XDG_STATE_HOME:-$HOME/.local/state}/glide-shell/powertimer"
unit=glide-power-timer
cancel() {
    systemctl --user stop "$unit.timer" "$unit-warn.timer" 2>/dev/null
    systemctl --user reset-failed "$unit.service" "$unit-warn.service" 2>/dev/null
    rm -f "$st"
}
case "${1:-}" in
    cancel) cancel ;;
    set)
        min=${2:?минуты}; act=${3:-poweroff}
        case $act in poweroff|suspend) ;; *) echo "действие: poweroff | suspend" >&2; exit 2 ;; esac
        case $min in ''|*[!0-9]*) echo "минуты — число" >&2; exit 2 ;; esac
        cancel
        mkdir -p "${st%/*}"
        # после срабатывания состояние стирается само (сон — чтобы после пробуждения значок не висел)
        systemd-run --user --quiet --collect --unit="$unit" --on-active="${min}m" --timer-property=AccuracySec=1s \
            sh -c "rm -f '$st'; exec systemctl $act"
        if [ "$min" -gt 1 ]; then
            msg=$([ "$act" = suspend ] && echo "Через минуту — сон" || echo "Через минуту компьютер выключится")
            systemd-run --user --quiet --collect --unit="$unit-warn" --on-active="$((min - 1))m" --timer-property=AccuracySec=1s \
                notify-send -a "Glide Shell" -u critical -i system-shutdown "$msg" "Отменить: «Питание» → «Выключение по таймеру»"
        fi
        printf '{"action": "%s", "end": %s}\n' "$act" "$(( $(date +%s) + min * 60 ))" > "$st"
        ;;
    *) sed -n '2,6p' "$0"; exit 2 ;;
esac
