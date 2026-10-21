#!/bin/sh
# ExecStartPost службы: ждать, пока Glide Shell загрузится (IPC panel ready = yes). Служба считается
# запущенной только после этого, и приложения автозапуска (app-*.service: After=glide-shell.service,
# systemd/app-.service.d) стартуют следом — при входе на HDD они читали диск вместе с оболочкой,
# и бар появлялся через ~25 с. Не дольше 40 с; оболочка упала — выходим сразу. Всегда код 0:
# не дождались — пусть остальные запускаются как обычно, а служба не уходит в «failed».
# В журнал — за сколько загрузилась (journalctl --user -b -u glide-shell | grep готова): мерить вход.
t0=$(date +%s%N)
since() { echo "$(( ($(date +%s%N) - t0) / 1000000 ))"; }
i=0
while [ "$i" -lt 160 ]; do
    if [ -n "$MAINPID" ] && ! kill -0 "$MAINPID" 2>/dev/null; then exit 0; fi
    if [ "$(qs -c glide-shell ipc call panel ready 2>/dev/null)" = yes ]; then
        echo "Glide Shell готова за $(since) мс после запуска службы"
        exit 0
    fi
    i=$((i + 1))
    sleep 0.25
done
echo "Glide Shell не ответила за $(since) мс — приложения автозапуска запускаются без неё"
exit 0
