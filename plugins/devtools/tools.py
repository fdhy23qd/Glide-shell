#!/usr/bin/env python3
import base64, hashlib, json, os, re, secrets, sys, time, urllib.parse, uuid
from datetime import datetime, timezone

text = os.environ.get("QP_TEXT", "")


def b64_decode(s):
    s = "".join(s.split())
    s += "=" * (-len(s) % 4)
    try:
        return base64.b64decode(s, validate=True)
    except ValueError:
        return base64.urlsafe_b64decode(s)


def human(ts):
    return datetime.fromtimestamp(ts, timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")


def json_fmt():
    return json.dumps(json.loads(text), indent=2, ensure_ascii=False)


def json_min():
    return json.dumps(json.loads(text), separators=(",", ":"), ensure_ascii=False)


def json_check():
    try:
        v = json.loads(text)
    except json.JSONDecodeError as e:
        return f"Ошибка JSON: {e.msg}\nстрока {e.lineno}, колонка {e.colno}"
    kind = {dict: f"объект, ключей: {len(v)}" if isinstance(v, dict) else "",
            list: f"массив, элементов: {len(v)}" if isinstance(v, list) else ""}.get(type(v), type(v).__name__)
    return "Корректный JSON: " + kind


def jwt():
    parts = text.strip().split(".")
    if len(parts) < 2:
        raise ValueError("не похоже на JWT")
    head, pay = (json.loads(b64_decode(p).decode("utf-8")) for p in parts[:2])
    out = ["header:", json.dumps(head, indent=2, ensure_ascii=False), "",
           "payload:", json.dumps(pay, indent=2, ensure_ascii=False), ""]
    for k in ("iat", "nbf", "exp"):
        if isinstance(pay.get(k), (int, float)):
            out.append(f"{k}: {human(pay[k])}")
    if isinstance(pay.get("exp"), (int, float)):
        out.append("СРОК ИСТЁК" if pay["exp"] < time.time() else "срок действия не истёк")
    out.append("\nПодпись НЕ проверяется.")
    return "\n".join(out)


def hashes():
    data = text.encode()
    return "\n".join(f"{a:7} {hashlib.new(a, data).hexdigest()}" for a in ("md5", "sha1", "sha256"))


def ts():
    s = text.strip()
    if not s:
        now = int(time.time())
        return f"unix: {now}\n{human(now)}"
    if re.fullmatch(r"-?\d+(\.\d+)?", s):
        v = float(s)
        if abs(v) > 1e11:
            v /= 1000
        d = datetime.fromtimestamp(v, timezone.utc)
        return f"UTC:   {d:%Y-%m-%d %H:%M:%S}\nlocal: {d.astimezone():%Y-%m-%d %H:%M:%S %Z}"
    d = datetime.fromisoformat(s.replace("Z", "+00:00"))
    if d.tzinfo is None:
        d = d.astimezone()
    return f"unix: {int(d.timestamp())}\nms:   {int(d.timestamp() * 1000)}"


OPS = {
    "json-fmt": json_fmt, "json-min": json_min, "json-check": json_check,
    "b64e": lambda: base64.b64encode(text.encode()).decode(),
    "b64d": lambda: b64_decode(text).decode("utf-8", "replace"),
    "urle": lambda: urllib.parse.quote(text, safe=""),
    "urld": lambda: urllib.parse.unquote(text),
    "jwt": jwt, "hash": hashes, "ts": ts,
    "uuid": lambda: str(uuid.uuid4()),
    "rand": lambda: secrets.token_urlsafe(24),
}

try:
    print(OPS[sys.argv[1]]())
except Exception as e:  # noqa: BLE001 — показываем причину пользователю
    print(f"Ошибка: {e}", file=sys.stderr)
    sys.exit(1)
