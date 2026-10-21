#!/bin/sh
# Аварийный откат Glide Shell → DMS (без DMS — просто перезапуск Glide Shell):
#   sh ~/.config/quickshell/glide-shell/tools/glide-rescue.sh        — остановить Glide Shell, запустить DMS целиком
#                                                                      (Mod+Shift+Escape или из TTY)
#   sh ~/.config/quickshell/glide-shell/tools/glide-rescue.sh undo   — обратно: остановить DMS, запустить Glide Shell
#   sh ~/.config/quickshell/glide-shell/tools/glide-rescue.sh auto   — то же, что без аргумента, но для systemd
#                                                                      (OnFailure службы): при запертом экране — ничего
# Glide Shell — служба systemd glide-shell.service (перезапуск при падении); DMS в автозапуске нет, откат
# запускает его до перезахода. Уведомления и агент polkit могут быть лишь у одного владельца, поэтому одна
# оболочка всегда останавливается раньше, чем стартует другая.
# Экран заперт блокировкой Glide Shell и она не снимается — ручной запуск из TTY (Ctrl+Alt+F2, вход по паролю)
# перезапускает Glide Shell в тестовом режиме: niri принимает новый замок вместо «мёртвого», и тот снимается
# сам через 60 с. Автоматический режим так не делает никогда: иначе падение оболочки снимало бы блокировку.
# (Передать замок DMS нельзя: DMS при этом падает.)
set -u
dms_cfg="${XDG_CONFIG_HOME:-$HOME/.config}/DankMaterialShell/settings.json"
mode="${1:-rescue}"
run="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

# Что из DMS выключено, пока работает Glide Shell: бар, док, всплывашки громкости/яркости (их показывает
# остров) и реакция на logind (блокировка)
set_dms_bar() {   # $1 = true | false
    [ -f "$dms_cfg" ] || return 0
    python3 -I - "$dms_cfg" "$1" <<'EOF'
import json, sys
path, on = sys.argv[1], sys.argv[2] == "true"
d = json.load(open(path))
for b in d.get("barConfigs", []):
    b["enabled"] = on
d["showDock"] = on   # док DMS — пока работает свой
d["loginctlLockIntegration"] = on   # loginctl lock-session и сон запирает Glide Shell, а не DMS
for k in ("osdVolumeEnabled", "osdMediaVolumeEnabled", "osdBrightnessEnabled", "osdMicMuteEnabled",
          "osdMicVolumeEnabled", "osdPowerProfileEnabled", "osdAudioOutputEnabled", "osdIdleInhibitorEnabled"):
    d[k] = on
with open(path, "w") as f:
    json.dump(d, f, ensure_ascii=False, indent=2)
    f.write("\n")
EOF
}

glide_stop() {
    systemctl --user stop glide-shell.service 2>/dev/null
    pkill -f "^qs -c glide-shell$" 2>/dev/null   # запущенный вручную, не службой
}
glide_start() {
    systemctl --user reset-failed glide-shell.service 2>/dev/null
    systemctl --user start glide-shell.service
}

if [ "$mode" = "undo" ]; then
    set_dms_bar false
    systemctl --user stop dms-rescue.service 2>/dev/null
    pkill -f "(^|/)dms run$" 2>/dev/null
    for _ in 1 2 3 4 5 6 7 8 9 10; do   # ждём, пока DMS отпустит уведомления и polkit
        pgrep -f "^qs -p .*/danklinux-shell/" >/dev/null || break
        sleep 0.5
    done
    pkill -f "^qs -p .*/danklinux-shell/" 2>/dev/null
    glide_start
    sleep 3
    notify-send -a "Glide Shell" "Glide Shell" "Снова работает Glide Shell, DMS остановлен" 2>/dev/null
    exit 0
fi

if [ -s "$run/glide-shell-lock" ]; then
    if [ "$mode" = "auto" ]; then   # падение при запертом экране: сессия остаётся запертой
        echo "glide-rescue: экран заперт — автоматически ничего не делаю (из TTY: glide-rescue.sh)" >&2
        exit 0
    fi
    # снять замок (через тестовый режим) можно только из терминала, где уже вошли по паролю. Хоткей niri
    # терминала не даёт: если ему когда-нибудь поставят allow-when-locked, это стало бы обходом блокировки.
    if [ ! -t 0 ]; then
        echo "glide-rescue: экран заперт, а запуск не из терминала — ничего не делаю (из TTY: glide-rescue.sh)" >&2
        exit 0
    fi
    echo test > "$run/glide-shell-lock"
    glide_stop
    sleep 1
    glide_start
    echo "Glide Shell перезапущен в тестовом режиме: экран разблокируется сам через 60 с."
    echo "Вернись в сессию (обычно Ctrl+Alt+F1 или F7). Перейти на DMS — запусти этот скрипт ещё раз."
    exit 0
fi

# DMS не установлен (чужой компьютер) — откатываться некуда: остановить Glide Shell значило бы остаться без
# рабочего стола. Пробуем поднять его заново и говорим, где искать причину.
if ! command -v dms >/dev/null 2>&1; then
    glide_stop
    sleep 1
    glide_start
    msg="Запасной оболочки (DMS) нет — Glide Shell перезапущен. Причина падений: journalctl --user -u glide-shell"
    echo "glide-rescue: $msg" >&2
    notify-send -a "Glide Shell" "Glide Shell падал" "$msg" 2>/dev/null
    exit 0
fi

set_dms_bar true
glide_stop
sleep 1   # уведомления и polkit освобождаются вместе с процессом
# отдельная служба: не в группе того, кто вызвал откат (oneshot-служба при выходе убила бы DMS)
pgrep -f "(^|/)dms run$" >/dev/null || systemd-run --user --unit=dms-rescue --collect --quiet dms run
sleep 4
notify-send -a "Glide Shell" "Glide Shell остановлен" \
    "Работает DMS. Вернуть Glide Shell: glide-rescue.sh undo" 2>/dev/null
exit 0
