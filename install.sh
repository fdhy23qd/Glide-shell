#!/bin/sh
# Чистая установка/обновление Glide Shell.
set -e
src=$(cd "$(dirname "$0")" && pwd)
cfg="${XDG_CONFIG_HOME:-$HOME/.config}"
state="${XDG_STATE_HOME:-$HOME/.local/state}"
data="${XDG_DATA_HOME:-$HOME/.local/share}"
dst="$cfg/quickshell/glide-shell"
if [ "$src" = "$(cd "$dst" 2>/dev/null && pwd)" ]; then
    echo "install.sh запущен из установленной копии ($dst) — запусти его из исходной папки" >&2
    exit 1
fi

# Переезд с прежнего имени (Quick Panel): настройки, данные и заметки — один раз
qs kill -c quickpanel 2>/dev/null || pkill -f "^qs -c quickpanel$" 2>/dev/null || true
for pair in "$cfg/quickpanel:$cfg/glide-shell" "$state/quickpanel:$state/glide-shell" \
            "$data/quickpanel:$data/glide-shell" "$HOME/quickpanel-notes.md:$HOME/glide-notes.md" \
            "${XDG_RUNTIME_DIR:-/tmp}/quickpanel-awake.pid:${XDG_RUNTIME_DIR:-/tmp}/glide-shell-awake.pid"; do
    old=${pair%%:*}; new=${pair#*:}
    if [ -e "$old" ] && [ ! -e "$new" ]; then mv "$old" "$new" && echo "перенесено: $old → $new"; fi
done
rm -rf "$cfg/quickshell/quickpanel"

# Тесты помощников и словаря перевода (~3 с): сломано — не ставим (пропустить: GLIDE_SKIP_TESTS=1)
if [ "${GLIDE_SKIP_TESTS:-}" != 1 ] && [ -d "$src/tests" ]; then
    if ! (cd "$src" && python3 -m unittest discover -s tests -q 2>/tmp/glide-tests.$$); then
        tail -25 /tmp/glide-tests.$$ >&2; rm -f /tmp/glide-tests.$$
        echo "тесты не прошли — установка остановлена (пропустить: GLIDE_SKIP_TESTS=1 sh install.sh)" >&2
        exit 1
    fi
    rm -f /tmp/glide-tests.$$
fi

# Glide Shell работает службой systemd (перезапуск при падении, запасной DMS — см. systemd/)
# Пока идёт установка, автоматический откат на DMS не нужен: сломанная версия падает 5 раз за секунды, systemd
# зовёт glide-rescue.sh auto — и DMS запускался рядом (22.10.2026). Метка — для него; откатывает сам install.sh.
installing="${XDG_RUNTIME_DIR:-/tmp}/glide-shell-installing"
: > "$installing"
trap 'rm -f "$installing"' EXIT
stop() {
    systemctl --user stop glide-shell.service 2>/dev/null || true
    pkill -f "^qs -c glide-shell$" 2>/dev/null || true   # запущенный по-старому, не службой
    true
}
stop
rm -rf "$dst.prev"
[ -d "$dst" ] && mv "$dst" "$dst.prev"   # прежняя рабочая версия — на случай, если новая не загрузится
mkdir -p "$dst"
cp -r "$src"/. "$dst"/
rm -rf "$dst/.git"
echo "установлено в $dst"
# свои виджеты рабочего стола: при первой установке — папка с примером (дальше её не трогаем)
widgets="$cfg/glide-shell/widgets"
if [ ! -d "$widgets" ]; then
    mkdir -p "$widgets" && cp -r "$src"/examples/widgets/. "$widgets"/ && echo "пример своего виджета: $widgets"
fi

units="$cfg/systemd/user"
mkdir -p "$units"
cp "$src"/systemd/*.service "$units"/
mkdir -p "$units/app-.service.d"   # приложения автозапуска — после оболочки (порядок, не зависимость)
cp "$src"/systemd/app-.service.d/*.conf "$units/app-.service.d/"
systemctl --user daemon-reload
systemctl --user enable glide-shell.service >/dev/null 2>&1

since=""
start() {
    systemctl --user reset-failed glide-shell.service 2>/dev/null || true
    since=$(date +%s)
    systemctl --user start glide-shell.service || true   # не запустилась — разберётся broken()
    sleep 6
}
log() { journalctl --user -u glide-shell.service --since "@$since" --no-pager -o cat 2>/dev/null; }
broken() {   # не загрузилась, упала в первые секунды или systemd уже перезапускал её
    log | grep -q "Failed to load configuration\|has crashed" \
        || ! systemctl --user is-active --quiet glide-shell.service \
        || [ "$(systemctl --user show -p NRestarts --value glide-shell.service)" != "0" ]
}
start
if broken; then
    echo "--- новая версия не загрузилась или упала ---" >&2
    log | grep -E "ERROR|caused by" | head -8 >&2
    if [ -d "$dst.prev" ]; then
        stop
        rm -rf "$dst" && mv "$dst.prev" "$dst"
        start
        echo "возвращена прежняя версия — бар на месте; исправь ошибку и запусти install.sh снова" >&2
    fi
    exit 1
fi
echo "--- лог (journalctl --user -u glide-shell) ---"
log
# ошибки JS не роняют оболочку, но ломают плагин или кусок интерфейса молча (расписание в v0.39) — громко о них
if log | grep -qE "TypeError|ReferenceError|is not a function|is not defined"; then
    echo "--- ВНИМАНИЕ: ошибки выполнения в первые секунды (оболочка работает, но что-то сломано) ---" >&2
    log | grep -E "TypeError|ReferenceError|is not a function|is not defined" | head -8 >&2
fi
