#!/bin/sh
# HTML-сцена webpaper для обоев Glide Shell:
#   glide-scene.sh stop            — остановить (обои — своя картинка, GIF или видео)
#   glide-scene.sh start [СЦЕНА]   — запустить; СЦЕНА — путь к .html: подставляется в --html службы через
#                                    drop-in ~/.config/systemd/user/webpaper.service.d/glide-scene.conf
#                                    (сам файл службы не трогаем); пусто — drop-in убрать, сцена как в службе
# Нет службы webpaper — ничего не делает.
set -u
systemctl --user cat webpaper.service >/dev/null 2>&1 || exit 0
if [ "${1:-}" = stop ]; then
    exec systemctl --user stop webpaper.service
fi
scene=${2:-}
case $scene in "~"|"~/"*) scene=$HOME${scene#"~"} ;; esac
dir="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user/webpaper.service.d"
conf="$dir/glide-scene.conf"
old=$(cat "$conf" 2>/dev/null)
if [ -n "$scene" ] && [ -f "$scene" ]; then
    unit=$(systemctl --user show -p FragmentPath --value webpaper.service)
    new=$(python3 -I - "$unit" "$scene" <<'PY'
import re, shlex, sys
unit, scene = sys.argv[1], sys.argv[2]
line = next(l for l in open(unit).read().splitlines() if l.startswith("ExecStart="))
args = shlex.split(line[len("ExecStart="):])
if "--html" in args:
    args[args.index("--html") + 1] = scene
else:
    args += ["--html", scene]
q = lambda a: '"' + a.replace("\\", "\\\\").replace('"', '\\"') + '"' if re.search(r'[\s"\\]', a) else a
print("# Сцена обоев — выбирается в Glide Shell (настройки → «Обои»); удалить файл — сцена как в службе")
print("[Service]\nExecStart=\nExecStart=" + " ".join(q(a) for a in args))
PY
)
    if [ "$new" != "$old" ]; then
        mkdir -p "$dir" && printf '%s\n' "$new" > "$conf"
        systemctl --user daemon-reload
        exec systemctl --user restart webpaper.service
    fi
elif [ -n "$old" ]; then
    rm -f "$conf"
    systemctl --user daemon-reload
    exec systemctl --user restart webpaper.service
fi
exec systemctl --user start webpaper.service
