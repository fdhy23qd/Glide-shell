#!/bin/sh
case "$QP_TEXT" in ''|*[!0-9]*) notify-send "Таймер" "Нужно число минут"; exit 1;; esac
QP_TEXT=$(printf %s "$QP_TEXT" | sed 's/^0*//')   # "08" иначе читается как восьмеричное
[ -n "$QP_TEXT" ] || { notify-send "Таймер" "Нужно больше нуля минут"; exit 1; }
secs=$((QP_TEXT * 60))
end=$(( ($(date +%s) + secs) * 1000 ))
# Состояние для острова: «конец_мс всего_с pid»; по окончании файл очищается, если таймер всё ещё этот
dir="${XDG_STATE_HOME:-$HOME/.local/state}/glide-shell"; mkdir -p "$dir"; f="$dir/timer"
[ "$QP_STYLE" = island ] || notify-send "Таймер" "Запущен на $QP_TEXT мин"   # в острове и так виден
setsid sh -c 'sleep "$1"; notify-send -u critical "Таймер" "Прошло $2 мин"
    [ "$(cut -d" " -f1 "$3" 2>/dev/null)" = "$4" ] && : > "$3"' sh "$secs" "$QP_TEXT" "$f" "$end" >/dev/null 2>&1 &
printf '%s %s %s\n' "$end" "$secs" "$!" > "$f"
