#!/usr/bin/env python3
import os, re, subprocess, sys, tempfile

text = os.environ.get("QP_TEXT") or os.environ.get("QP_SELECTION") or os.environ.get("QP_CLIPBOARD", "")
cmd = sys.argv[1] if len(sys.argv) > 1 else ""


def words(s):
    return re.findall(r"[A-Za-zА-Яа-яЁё0-9]+", re.sub(r"([a-zа-яё0-9])([A-ZА-ЯЁ])", r"\1 \2", s))


def main():
    if not text.strip():
        raise SystemExit("нет текста: выдели его или скопируй")
    if cmd == "count":
        print(f"символов: {len(text)}\nбез пробелов: {len(re.sub(r'\s', '', text))}\n"
              f"слов: {len(text.split())}\nстрок: {len(text.splitlines())}")
    elif cmd == "upper":
        print(text.upper())
    elif cmd == "lower":
        print(text.lower())
    elif cmd == "title":
        print(text.title())
    elif cmd == "snake":
        print("_".join(w.lower() for w in words(text)))
    elif cmd == "camel":
        w = [x.lower() for x in words(text)]
        print((w[0] + "".join(x.capitalize() for x in w[1:])) if w else "")
    elif cmd == "clean":
        lines = [re.sub(r"[ \t]+", " ", l).strip() for l in text.splitlines()]
        print(re.sub(r"\n{3,}", "\n\n", "\n".join(lines)).strip())
    elif cmd == "sort":
        print("\n".join(sorted(text.splitlines(), key=str.lower)))
    elif cmd == "uniq":
        seen, out = set(), []
        for l in text.splitlines():
            if l not in seen:
                seen.add(l)
                out.append(l)
        print("\n".join(out))
    elif cmd == "qr":
        # не в общий /tmp: там чужая ссылка с этим именем подменила бы файл, который перезапишет qrencode
        path = os.path.join(os.environ.get("XDG_RUNTIME_DIR") or tempfile.mkdtemp(), "glide-shell-qr.png")
        subprocess.run(["qrencode", "-s", "8", "-o", path], input=text.encode(), check=True)
        subprocess.Popen(["xdg-open", path], start_new_session=True,
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    else:
        raise SystemExit(f"неизвестная команда: {cmd}")


try:
    main()
except FileNotFoundError as e:
    print(f"не найдена программа: {e.filename} (для QR нужен qrencode)", file=sys.stderr)
    sys.exit(1)
except Exception as e:
    print(f"{type(e).__name__}: {e}", file=sys.stderr)
    sys.exit(1)
