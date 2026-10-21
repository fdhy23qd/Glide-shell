#!/usr/bin/env python3
"""Обои Glide: список картинок с миниатюрами и цвета темы из картинки.

    glide-walls.py list ПУТЬ      → [{"path", "thumb", "name"}] — папка (картинки в ней) или один файл;
                                     миниатюры 320×180 — в ~/.cache/glide-shell/wall-thumbs (для настроек:
                                     целую картинку на 4K ради значка декодировать дорого)
    glide-walls.py palette ФАЙЛ   → {"accent": "#rrggbb" | null, "tone": "glide|amoled|soft"}
    glide-walls.py prepare ФАЙЛ Ш В К/С → {"file": путь} — GIF и видео для обоев: один раз перекодировать в H.264
                                     под экран (Ш×В, не больше К/С кадров в секунду, без звука) в
                                     ~/.cache/glide-shell/wall-video; подходящее видео — как есть

Акцент — самый «живой» оттенок картинки (насыщенные пиксели средней яркости, по кругу оттенков),
приведённый к читаемому на тёмном фоне (насыщенность 0.5–0.85, светлота 0.55–0.68). Картинка почти
без цвета — accent: null (акцент не трогаем). Тон: очень тёмная — amoled, синеватая и не тёмная — soft.
"""
import colorsys
import hashlib
import json
import os
import sys
from pathlib import Path

from PIL import Image

IMAGES = {".jpg", ".jpeg", ".png", ".webp", ".bmp", ".avif"}
GIFS = {".gif"}
VIDEOS = {".mp4", ".webm", ".mkv", ".mov", ".m4v"}
EXTS = IMAGES | GIFS | VIDEOS
CACHE = Path(os.environ.get("XDG_CACHE_HOME") or Path.home() / ".cache") / "glide-shell" / "wall-thumbs"
VCACHE = CACHE.parent / "wall-video"


def kind(p: Path) -> str:
    s = p.suffix.lower()
    return "gif" if s in GIFS else "video" if s in VIDEOS else "image"


def frame(p: Path) -> Image.Image:
    """Картинка для миниатюры и цветов: сама картинка, первый кадр GIF или кадр видео (на 1-й секунде)."""
    if kind(p) != "video":
        im = Image.open(p)
        im.seek(0)
        return im
    import io
    import subprocess
    out = subprocess.run(["ffmpeg", "-v", "error", "-ss", "1", "-i", str(p), "-frames:v", "1",
                          "-vf", "scale=640:-2", "-f", "image2pipe", "-c:v", "png", "-"],
                         capture_output=True, timeout=30).stdout
    if not out:   # видео короче секунды
        out = subprocess.run(["ffmpeg", "-v", "error", "-i", str(p), "-frames:v", "1", "-vf", "scale=640:-2",
                              "-f", "image2pipe", "-c:v", "png", "-"], capture_output=True, timeout=30).stdout
    return Image.open(io.BytesIO(out))


def images(path: Path):
    if path.is_file():
        return [path] if path.suffix.lower() in EXTS else []
    if not path.is_dir():
        return []
    return sorted((p for p in path.iterdir() if p.is_file() and p.suffix.lower() in EXTS),
                  key=lambda p: p.name.lower())


def thumb(p: Path) -> str:
    st = p.stat()
    key = hashlib.sha1(f"{p}:{st.st_mtime_ns}:{st.st_size}".encode()).hexdigest()[:20]
    out = CACHE / f"{key}.jpg"
    if not out.exists():
        CACHE.mkdir(parents=True, exist_ok=True)
        with frame(p) as im:
            im.draft("RGB", (640, 360))          # JPEG декодируется сразу уменьшенным — быстро
            im = im.convert("RGB")
            # заполнить 16:9 с обрезкой, как обои на экране
            w, h = im.size
            tw, th = 320, 180
            s = max(tw / w, th / h)
            im = im.resize((max(tw, round(w * s)), max(th, round(h * s))), Image.LANCZOS)
            l, t = (im.width - tw) // 2, (im.height - th) // 2
            im.crop((l, t, l + tw, t + th)).save(out, "JPEG", quality=82)
    return str(out)


def palette(p: Path):
    with frame(p) as im:
        im.draft("RGB", (256, 256))
        im = im.convert("RGB")
        im.thumbnail((96, 96))
        px = list(im.get_flattened_data() if hasattr(im, "get_flattened_data") else im.getdata())
    bins = [0.0] * 36
    sums = [[0.0, 0.0, 0.0] for _ in range(36)]
    lum = sat = 0.0
    for r, g, b in px:
        h, l, s = colorsys.rgb_to_hls(r / 255, g / 255, b / 255)
        lum += l
        sat += s
        if s < 0.2 or l < 0.08 or l > 0.92:
            continue
        w = s * (1 - abs(l - 0.5) * 1.6)        # живые цвета средней яркости весят больше
        i = int(h * 36) % 36
        bins[i] += w
        sums[i][0] += r * w; sums[i][1] += g * w; sums[i][2] += b * w
    n = len(px) or 1
    lum, sat = lum / n, sat / n
    # соседние ячейки вместе (оттенок на границе ячеек не делится пополам)
    smooth = [bins[i - 1] + bins[i] + bins[(i + 1) % 36] for i in range(36)]
    best = max(range(36), key=lambda i: smooth[i])
    accent = None
    if smooth[best] > n * 0.02:
        idx = [best - 1, best, (best + 1) % 36]
        wsum = sum(bins[i] for i in idx) or 1
        r = sum(sums[i][0] for i in idx) / wsum
        g = sum(sums[i][1] for i in idx) / wsum
        b = sum(sums[i][2] for i in idx) / wsum
        h, l, s = colorsys.rgb_to_hls(r / 255, g / 255, b / 255)
        s = min(0.85, max(0.5, s))
        l = min(0.68, max(0.55, l))
        r, g, b = colorsys.hls_to_rgb(h, l, s)
        accent = "#%02x%02x%02x" % (round(r * 255), round(g * 255), round(b * 255))
        hue = h
    else:
        hue = None
    if lum < 0.12:
        tone = "amoled"
    elif hue is not None and 0.52 <= hue <= 0.72 and lum > 0.28:
        tone = "soft"
    else:
        tone = "glide"
    return {"accent": accent, "tone": tone}


def main():
    if len(sys.argv) < 3:
        print(__doc__, file=sys.stderr)
        sys.exit(2)
    cmd, arg = sys.argv[1], Path(os.path.expanduser(sys.argv[2]))
    if cmd == "list":
        out = []
        for p in images(arg):
            try:
                out.append({"path": str(p), "thumb": thumb(p), "name": p.stem, "kind": kind(p)})
            except Exception as e:   # битая картинка — пропускаем, остальные показываем
                print(f"glide-walls: {p}: {e}", file=sys.stderr)
        print(json.dumps(out, ensure_ascii=False))
    elif cmd == "palette":
        try:
            print(json.dumps(palette(arg)))
        except Exception as e:
            print(f"glide-walls: {arg}: {e}", file=sys.stderr)
            print(json.dumps({"accent": None, "tone": None}))
    elif cmd == "prepare":
        try:
            print(json.dumps({"file": prepare(arg, int(sys.argv[3]), int(sys.argv[4]), int(sys.argv[5]))}))
        except Exception as e:
            print(f"glide-walls: {arg}: {e}", file=sys.stderr)
            print(json.dumps({"file": None}))
    else:
        sys.exit(2)


def probe(p: Path):
    import subprocess
    out = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries",
                          "stream=codec_name,width,height,avg_frame_rate", "-of", "json", str(p)],
                         capture_output=True, text=True, timeout=30).stdout
    s = (json.loads(out or "{}").get("streams") or [{}])[0]
    num, _, den = (s.get("avg_frame_rate") or "0/1").partition("/")
    fps = float(num) / float(den or 1) if float(den or 1) else 0
    return s.get("codec_name"), int(s.get("width") or 0), int(s.get("height") or 0), fps


def prepare(p: Path, w: int, h: int, fps: int) -> str:
    """Готовое к обоям видео: H.264 (его декодирует и видеокарта, и процессор дёшево), не больше экрана и fps,
    без звука, moov в начале. Перекодируется один раз (кэш по пути, времени изменения и параметрам) —
    фоном, с низким приоритетом. Уже подходящее видео не трогаем."""
    import subprocess
    if kind(p) == "video":
        codec, vw, vh, vfps = probe(p)
        if codec == "h264" and vw <= w * 1.05 and vh <= h * 1.05 and 0 < vfps <= fps + 1:
            return str(p)
    st = p.stat()
    key = hashlib.sha1(f"{p}:{st.st_mtime_ns}:{st.st_size}:{w}x{h}@{fps}".encode()).hexdigest()[:20]
    out = VCACHE / f"{key}.mp4"
    if out.exists():
        return str(out)
    VCACHE.mkdir(parents=True, exist_ok=True)
    tmp = out.with_suffix(".part.mp4")
    # закрыть экран целиком (обрезку по краям сделает VideoOutput), чётные стороны — требование yuv420p
    vf = (f"scale={w}:{h}:force_original_aspect_ratio=increase:flags=lanczos,"
          f"scale=trunc(iw/2)*2:trunc(ih/2)*2,fps={fps},format=yuv420p")
    cmd = ["nice", "-n", "19", "ionice", "-c", "3", "ffmpeg", "-v", "error", "-y", "-i", str(p), "-an",
           "-vf", vf, "-c:v", "libx264", "-preset", "veryfast", "-crf", "23", "-movflags", "+faststart", str(tmp)]
    if subprocess.run(cmd, timeout=1800).returncode != 0 or not tmp.exists():
        tmp.unlink(missing_ok=True)
        raise RuntimeError("ffmpeg не смог перекодировать")
    tmp.rename(out)
    return str(out)


if __name__ == "__main__":
    main()
