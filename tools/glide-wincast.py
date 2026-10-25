#!/usr/bin/env python3
"""Запись одного окна niri в MP4: glide-wincast.py ID_ОКНА ФАЙЛ [--audio УСТРОЙСТВО_PULSE] [--check]

Окно отдаёт сам niri через D-Bus org.gnome.Mutter.ScreenCast (RecordWindow по id окна) — без диалога портала и без
правки настроек xdg-desktop-portal. Поток PipeWire пишет GStreamer: аппаратный H.264 (vah264enc, пакет gst-plugin-va),
без него — openh264enc или x264enc; звук (монитор выхода или микрофон) — AAC (fdkaacenc) или Opus.
SIGINT/SIGTERM — конец записи (EOS), сеанс niri закрывается. Окно закрыли — запись заканчивается сама.
Пишется сначала MKV (Matroska читается при любом обрыве: окно закрылось и поток оборвался посреди кадра, упала
оболочка), в конце ffmpeg перепаковывает его в MP4 без перекодирования; не вышло — остаётся .mkv. --check — только проверить, чем писать (JSON: {ok, video, audio, missing}).
"""
import json
import os
import shlex
import shutil
import signal
import subprocess
import sys
import warnings

warnings.filterwarnings("ignore", category=DeprecationWarning)   # GLib.unix_signal_add: GLibUnix есть не везде
from gi.repository import Gio, GLib  # noqa: E402

# niri шлёт кадры только при перерисовке окна (framerate 0/1): videorate делает ровные 30 кадров/с — иначе у mp4mux
# нет меток времени, а неподвижное окно давало бы видео из одного кадра
RATE = "video/x-raw(memory:DMABuf),framerate=30/1"
BUS_NAME, ROOT = "org.gnome.Mutter.ScreenCast", "/org/gnome/Mutter/ScreenCast"
SESSION, STREAM = "org.gnome.Mutter.ScreenCast.Session", "org.gnome.Mutter.ScreenCast.Stream"


def have(element):
    return subprocess.run(["gst-inspect-1.0", "--exists", element], stdin=subprocess.DEVNULL).returncode == 0


def encoders():
    """(видео — кусок конвейера, звук — кусок конвейера, чего не хватает)"""
    # niri отдаёт кадры только в памяти видеокарты (DMA-BUF): videoconvert их не берёт — VA принимает сам,
    # для программных кодировщиков кадр копируется через GL
    missing = [e for e in ("pipewiresrc", "matroskamux", "h264parse", "videoconvert", "glupload", "gldownload") if not have(e)]
    if not shutil.which("ffmpeg"):
        missing.append("ffmpeg")
    gl = "glupload ! glcolorconvert ! gldownload ! videoconvert"
    if have("vah264enc") and have("vapostproc"):
        video = "vapostproc ! video/x-raw(memory:VAMemory),format=NV12 ! vah264enc bitrate=6000"   # кодирует видеокарта
    elif have("openh264enc"):
        video = gl + " ! video/x-raw,format=I420 ! openh264enc bitrate=6000000 complexity=low"
    elif have("x264enc"):
        video = gl + " ! x264enc speed-preset=veryfast tune=zerolatency bitrate=6000"
    else:
        video, missing = "", missing + ["vah264enc|openh264enc|x264enc"]
    video = os.environ.get("GLIDE_WINCAST_VIDEO") or video   # для проверки других конвейеров
    audio = "audioconvert ! fdkaacenc" if have("fdkaacenc") else "audioconvert ! opusenc" if have("opusenc") else ""
    return video, audio, missing


def main():
    args = sys.argv[1:]
    video, audio, missing = encoders()
    if "--check" in args:
        print(json.dumps({"ok": not missing, "video": video.split("!")[-1].split()[0] if video else "", "audio": bool(audio),
                          "missing": missing}))
        return
    if len(args) < 2:
        sys.exit(__doc__)
    if missing:
        sys.exit("glide-wincast: нет элементов GStreamer: " + ", ".join(missing))
    win, out = int(args[0]), args[1]
    source = args[args.index("--audio") + 1] if "--audio" in args and args.index("--audio") + 1 < len(args) else ""
    os.makedirs(os.path.dirname(out) or ".", exist_ok=True)
    part = os.path.splitext(out)[0] + ".part.mkv"   # на виду: упадёт что-то — запись не потеряется в скрытом файле

    bus = Gio.bus_get_sync(Gio.BusType.SESSION)

    def call(path, iface, method, params=None, rtype=None):
        return bus.call_sync(BUS_NAME, path, iface, method, params, GLib.VariantType(rtype) if rtype else None, 0, 5000, None)

    session = call(ROOT, BUS_NAME, "CreateSession", GLib.Variant("(a{sv})", ({},)), "(o)")[0]
    stream = call(session, SESSION, "RecordWindow",
                  GLib.Variant("(a{sv})", ({"window-id": GLib.Variant("t", win), "cursor-mode": GLib.Variant("u", 1)},)), "(o)")[0]
    loop = GLib.MainLoop()
    state = {"gst": None, "code": 0, "stopping": False}

    def finish(*_):
        """Конец записи: EOS в GStreamer, потом — сеанс niri."""
        if state["stopping"]:
            return True
        state["stopping"] = True
        g = state["gst"]
        if g and g.poll() is None:
            g.send_signal(signal.SIGINT)
        else:
            loop.quit()
        return True

    def started(_c, _s, _p, _i, _sig, params):
        # niri шлёт PipeWireStreamAdded и при закрытии окна: второй gst-launch обнулил бы файл — запускаем один раз
        if state["gst"] or state["stopping"]:
            return
        node = params.unpack()[0]
        # файл открываем сами и отдаём дескриптором: filesink при закрытии окна (поток оборвался) обрезал файл до
        # нуля, а по fdsink назад не перемотать — записанное остаётся
        fd = os.open(part, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o644)
        pipe = f"pipewiresrc path={node} do-timestamp=true keepalive-time=1000 on-disconnect=eos ! queue ! videorate ! {RATE} ! {video} ! h264parse ! queue ! matroskamux name=mux streamable=true ! fdsink fd={fd}"
        if source and audio:
            pipe += f" pulsesrc device=\"{source}\" client-name=\"Glide Shell: запись окна\" ! queue ! {audio} ! queue ! mux."
        # по словам: gst-launch экранирует пробелы внутри каждого аргумента — путь с пробелами остаётся одним словом
        state["gst"] = subprocess.Popen(["setpriv", "--pdeathsig", "INT", "gst-launch-1.0", "-e", "-v" if os.environ.get("GLIDE_WINCAST_VERBOSE") else "-q"] + shlex.split(pipe), stdin=subprocess.DEVNULL, pass_fds=(fd,))
        os.close(fd)
        GLib.child_watch_add(GLib.PRIORITY_DEFAULT, state["gst"].pid, gst_done)

    def gst_done(_pid, status):
        state["code"] = os.waitstatus_to_exitcode(status) if status else 0
        loop.quit()

    bus.signal_subscribe(None, STREAM, "PipeWireStreamAdded", stream, None, 0, started)
    bus.signal_subscribe(None, SESSION, "Closed", session, None, 0, lambda *_: finish())   # окно закрыли
    for sig in (signal.SIGINT, signal.SIGTERM):
        GLib.unix_signal_add(GLib.PRIORITY_HIGH, sig, finish)
    call(session, SESSION, "Start")
    GLib.timeout_add(10000, lambda: (finish() if not state["gst"] else None) and False)   # поток так и не пришёл
    loop.run()
    try:
        call(session, SESSION, "Stop")
    except GLib.Error:
        pass                                   # уже закрыт (окно исчезло)
    sys.exit(0 if state["gst"] and remux(part, out) else 1)


def remux(part, out):
    """MKV → MP4 без перекодирования; не вышло — оставить запись как .mkv. True — файл есть."""
    if not os.path.exists(part) or os.path.getsize(part) == 0:
        if os.path.exists(part):
            os.remove(part)
        return False
    r = subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", part, "-c", "copy", "-movflags", "+faststart", out],
                       stdin=subprocess.DEVNULL, capture_output=True, text=True)
    if r.returncode == 0 and os.path.exists(out) and os.path.getsize(out) > 0:
        os.remove(part)
        print("FILE " + out, flush=True)      # куда записалось — для Recorder.qml
        return True
    print("glide-wincast: в MP4 не перепаковалось, оставлено MKV: " + r.stderr.strip()[-300:], file=sys.stderr)
    os.replace(part, os.path.splitext(out)[0] + ".mkv")
    print("FILE " + os.path.splitext(out)[0] + ".mkv", flush=True)
    return True


if __name__ == "__main__":
    main()
