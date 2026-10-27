#!/usr/bin/env python3
import base64, hashlib, json, os, re, secrets, string, sys, time, uuid
import xml.dom.minidom as minidom
from urllib.parse import quote, unquote

text = os.environ.get("QP_TEXT", "")
cmd = sys.argv[1] if len(sys.argv) > 1 else ""


def b64url(s):
    return base64.urlsafe_b64decode(s + "=" * (-len(s) % 4))


def fmt_time(t):
    t = float(t)
    if t > 1e12:
        t /= 1000
    return (time.strftime("%Y-%m-%d %H:%M:%S UTC", time.gmtime(t)) + "\n" +
            time.strftime("%Y-%m-%d %H:%M:%S local", time.localtime(t)))


def main():
    if cmd == "uuid":
        print(uuid.uuid4())
    elif cmd == "password":
        alphabet = string.ascii_letters + string.digits + "-_.!@#$%^&*"
        pw = "".join(secrets.choice(alphabet) for _ in range(24))
        # пароль скопирует qp-run обычным wl-copy — пусть история буфера (clip.py) его пропустит
        skip = os.path.join(os.environ.get("XDG_RUNTIME_DIR") or "/nonexistent", "glide-shell-clip-skip")
        try:
            fd = os.open(skip, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
            with os.fdopen(fd, "w") as f:
                f.write(hashlib.sha256(pw.encode()).hexdigest())
        except OSError:
            pass
        print(pw)
    elif cmd == "now":
        print(int(time.time()))
    elif cmd == "json-fmt":
        print(json.dumps(json.loads(text), ensure_ascii=False, indent=2))
    elif cmd == "json-min":
        print(json.dumps(json.loads(text), ensure_ascii=False, separators=(",", ":")))
    elif cmd == "xml-fmt":
        pretty = minidom.parseString(text.strip().encode()).toprettyxml(indent="  ")
        print("\n".join(l for l in pretty.splitlines() if l.strip()))
    elif cmd == "jwt":
        h, p, _ = text.strip().split(".")
        header, payload = json.loads(b64url(h)), json.loads(b64url(p))
        out = {"header": header, "payload": payload}
        for k in ("exp", "iat", "nbf"):
            if isinstance(payload.get(k), (int, float)):
                out[k + "_utc"] = time.strftime("%Y-%m-%d %H:%M:%S", time.gmtime(payload[k]))
        print(json.dumps(out, ensure_ascii=False, indent=2))
    elif cmd == "ts":
        print(fmt_time(text.strip()))
    elif cmd == "b64d":
        print(base64.b64decode("".join(text.split()), validate=True).decode("utf-8"))
    elif cmd == "b64e":
        print(base64.b64encode(text.encode()).decode())
    elif cmd == "urle":
        print(quote(text.strip(), safe=""))
    elif cmd == "urld":
        print(unquote(text.strip()))
    elif cmd == "hash":
        print(hashlib.new(sys.argv[2], text.encode()).hexdigest())
    elif cmd == "regex":
        src = os.environ.get("QP_CLIPBOARD", "")
        found = list(re.finditer(text, src))
        lines = [f"Совпадений: {len(found)}"]
        for m in found[:10]:
            line = f"{m.start()}: {m.group(0)[:80]!r}"
            if m.groups():
                line += "  группы: " + ", ".join(repr(g) for g in m.groups())
            lines.append(line)
        print("\n".join(lines))
    else:
        raise SystemExit(f"неизвестная команда: {cmd}")


try:
    main()
except Exception as e:
    print(f"{type(e).__name__}: {e}", file=sys.stderr)
    sys.exit(1)
