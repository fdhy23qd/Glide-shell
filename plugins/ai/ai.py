#!/usr/bin/env python3
"""ИИ для Glide Shell: чат и разовые действия над текстом.

Подкоманды:
  info               JSON {backend, label, ready, hint} — чем будем отвечать
  history            JSON-список сообщений текущего чата
  send               сообщение из $QP_TEXT → поток JSON-строк {"t": "delta"|"done"|"error", ...}
  reset              начать новый чат
  once <задача>      разовое действие над $QP_TEXT (fix, translate, summary), ответ — в stdout
  setup-api          поставить SDK anthropic в отдельное venv (для бэкенда "api")

Бэкенды (выбор: $QP_AI_BACKEND = claude | api, по умолчанию — первый доступный):
  claude  Claude Code CLI (подписка, ключ не нужен). Путь: $QP_CLAUDE, PATH или расширение VS Code.
  api     Claude API через SDK anthropic. Ключ: $ANTHROPIC_API_KEY или ~/.config/glide-shell/anthropic-key.
Модель: $QP_AI_MODEL (для api по умолчанию claude-opus-5-5; для claude — модель из настроек Claude Code).
"""
import glob, json, os, shutil, signal, subprocess, sys, time
from pathlib import Path

STATE = Path(os.environ.get("XDG_STATE_HOME") or Path.home() / ".local/state") / "glide-shell"
CHAT = STATE / "ai-chat.json"
CFG = Path(os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config") / "glide-shell"
KEY_FILE = CFG / "anthropic-key"
VENV = Path(os.environ.get("XDG_DATA_HOME") or Path.home() / ".local/share") / "glide-shell" / "ai-venv"
API_MODEL = os.environ.get("QP_AI_MODEL") or "claude-opus-5-5"
MAX_HISTORY = 40   # сообщений в истории чата

SYSTEM = (
    "Ты — ИИ-помощник во всплывающей панели быстрых действий на Linux (Wayland, niri). "
    "Пользователь пишет коротко и ждёт короткий, сразу полезный ответ. "
    "Отвечай на языке пользователя (обычно по-русски). Используй Markdown: списки, `код`, блоки кода. "
    "Без вступлений и без пересказа вопроса. Если нужна команда для терминала — дай её одной строкой."
)

TASKS = {
    "fix": "Исправь орфографию, пунктуацию и грамматику в тексте ниже, сохрани смысл, стиль и язык. "
           "Выведи только исправленный текст, без комментариев.",
    "translate": "Переведи текст ниже: если он на русском — на английский, иначе — на русский. "
                 "Выведи только перевод, без комментариев.",
    "summary": "Кратко перескажи текст ниже в 2–5 пунктах. Выведи только пересказ.",
}


# ---------- общие ----------
def emit(**ev):
    print(json.dumps(ev, ensure_ascii=False), flush=True)


def load_chat():
    try:
        d = json.loads(CHAT.read_text())
        return d if isinstance(d, dict) else {}
    except (OSError, ValueError):
        return {}


def save_chat(d):
    STATE.mkdir(parents=True, exist_ok=True)
    del d.setdefault("messages", [])[:-MAX_HISTORY]   # на месте: вызывающий держит ссылку на список
    tmp = CHAT.with_suffix(".tmp")
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as f:
        json.dump(d, f, ensure_ascii=False)
    os.replace(tmp, CHAT)


def find_claude():
    for c in (os.environ.get("QP_CLAUDE"), shutil.which("claude"),
              str(Path.home() / ".local/bin/claude"), str(Path.home() / ".claude/local/claude")):
        if c and os.access(c, os.X_OK):
            return c
    # бинарник, который ставит расширение VS Code / VSCodium / Cursor; берём самую новую версию
    found = []
    for base in (".vscode", ".vscode-oss", ".cursor", ".windsurf"):
        found += glob.glob(str(Path.home() / base / "extensions/anthropic.claude-code-*/resources/native-binary/claude"))
    found = [f for f in found if os.access(f, os.X_OK)]
    return max(found, key=os.path.getmtime) if found else None


def api_key():
    if os.environ.get("ANTHROPIC_API_KEY"):
        return os.environ["ANTHROPIC_API_KEY"]
    try:
        return KEY_FILE.read_text().strip() or None
    except OSError:
        return None


def have_sdk():
    try:
        import anthropic  # noqa: F401
        return True
    except ImportError:
        return (VENV / "bin/python").exists()


def backend():
    want = os.environ.get("QP_AI_BACKEND", "")
    if want in ("", "claude") and find_claude():
        return "claude"
    if want in ("", "api") and api_key():
        return "api"
    return None


def ensure_sdk():
    """Для бэкенда api: если SDK нет в системном python — перезапуститься из своего venv."""
    try:
        import anthropic  # noqa: F401
    except ImportError:
        py = VENV / "bin/python"
        if py.exists() and sys.executable != str(py):
            os.execv(str(py), [str(py)] + sys.argv)
        raise SystemExit("нет SDK anthropic: нажми «Настроить API» в чате или выполни "
                         f"python3 {__file__} setup-api")


# ---------- бэкенд: Claude Code CLI ----------
def claude_stream(prompt, session=None, system=SYSTEM, persist=True):
    """Генератор: ("delta", текст) ... ("done", session_id) | ("error", текст)."""
    argv = [find_claude(), "-p", prompt, "--output-format", "stream-json", "--include-partial-messages",
            "--verbose", "--tools", "", "--strict-mcp-config", "--system-prompt", system]
    if os.environ.get("QP_AI_MODEL"):
        argv += ["--model", os.environ["QP_AI_MODEL"]]
    if session:
        argv += ["--resume", session]
    if not persist:
        argv += ["--no-session-persistence"]
    # отдельная рабочая папка: сессии чата не смешиваются с проектами и не видят их CLAUDE.md
    cwd = STATE / "ai-cwd"
    cwd.mkdir(parents=True, exist_ok=True)
    p = subprocess.Popen(argv, cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    sid, got = session, False
    try:
        for line in p.stdout:
            try:
                e = json.loads(line)
            except ValueError:
                continue
            sid = e.get("session_id") or sid
            if e.get("type") == "stream_event":
                ev = e.get("event", {})
                if ev.get("type") == "content_block_delta" and ev.get("delta", {}).get("type") == "text_delta":
                    got = True
                    yield "delta", ev["delta"]["text"]
            elif e.get("type") == "result":
                if e.get("is_error") or e.get("subtype") != "success":
                    yield "error", str(e.get("result") or e.get("subtype") or "ошибка Claude Code")
                    return
                if not got and e.get("result"):
                    yield "delta", e["result"]
        p.wait()
        if p.returncode != 0:
            err = (p.stderr.read() or "").strip().splitlines()
            yield "error", err[-1] if err else f"Claude Code завершился с кодом {p.returncode}"
            return
        yield "done", sid
    finally:
        if p.poll() is None:
            p.terminate()
            try:
                p.wait(timeout=2)
            except subprocess.TimeoutExpired:
                p.kill()


# ---------- бэкенд: Claude API ----------
def api_stream(messages, system=SYSTEM):
    """Генератор: ("delta", текст) ... ("done", None) | ("error", текст). messages — [{role, content}]."""
    ensure_sdk()
    import anthropic

    client = anthropic.Anthropic(api_key=api_key())
    try:
        with client.beta.messages.stream(
            model=API_MODEL,
            max_tokens=64000,
            system=system,
            messages=messages,
            output_config={"effort": "medium"},
            # если модель откажется отвечать, API сам повторит запрос на подходящей резервной модели
            betas=["server-side-fallback-2026-07-01"],
            fallbacks="default",
        ) as stream:
            for text in stream.text_stream:
                yield "delta", text
            final = stream.get_final_message()
        if final.stop_reason == "refusal":
            yield "error", "Модель отказалась отвечать на этот запрос"
            return
        yield "done", None
    except anthropic.AuthenticationError:
        yield "error", "Неверный API-ключ (ANTHROPIC_API_KEY или ~/.config/glide-shell/anthropic-key)"
    except anthropic.RateLimitError:
        yield "error", "Лимит запросов API, попробуй через минуту"
    except anthropic.APIStatusError as e:
        yield "error", f"Ошибка API {e.status_code}: {e.message}"
    except anthropic.APIConnectionError:
        yield "error", "Нет соединения с API"


# ---------- команды ----------
def cmd_info():
    b = backend()
    if b == "claude":
        emit(backend=b, ready=True, label="Claude Code · подписка", hint="")
    elif b == "api":
        emit(backend=b, ready=have_sdk(), label=f"Claude API · {API_MODEL}",
             hint="" if have_sdk() else "Нужен SDK anthropic — нажми «Настроить API»")
    else:
        emit(backend=None, ready=False, label="ИИ не настроен",
             hint="Установи Claude Code (claude.com/claude-code) и войди в аккаунт — ключ не нужен. "
                  "Или положи API-ключ в ~/.config/glide-shell/anthropic-key")


def cmd_send():
    text = os.environ.get("QP_TEXT", "").strip()
    if not text:
        return
    b = backend()
    if not b:
        emit(t="error", text="ИИ не настроен: нужен Claude Code или API-ключ")
        return
    chat = load_chat()
    if chat.get("backend") not in (None, b):   # сменился бэкенд — сессию CLI не переносим
        chat.pop("session", None)
    chat["backend"] = b
    msgs = chat.setdefault("messages", [])
    msgs.append({"role": "user", "text": text, "ts": int(time.time())})
    save_chat(chat)

    answer, ok = [], False
    if b == "claude":
        gen = claude_stream(text, chat.get("session"))
    else:
        history = [{"role": m["role"], "content": m["text"]} for m in msgs if m.get("text")]
        gen = api_stream(history)
    try:
        for kind, val in gen:
            if kind == "delta":
                answer.append(val)
                emit(t="delta", text=val)
            elif kind == "done":
                ok = True
                if b == "claude" and val:
                    chat["session"] = val
            else:
                emit(t="error", text=val)
    except KeyboardInterrupt:   # «Стоп» в панели
        gen.close()
        answer.append("\n\n_(остановлено)_")
    full = "".join(answer).strip()
    if full:
        msgs.append({"role": "assistant", "text": full, "ts": int(time.time())})
    elif not ok:
        msgs.pop()   # без ответа — не оставляем висящий вопрос в истории
    save_chat(chat)
    emit(t="done")


def cmd_once(task):
    text = (os.environ.get("QP_TEXT") or os.environ.get("QP_SELECTION") or os.environ.get("QP_CLIPBOARD", "")).strip()
    if not text:
        raise SystemExit("нет текста: выдели его или скопируй")
    prompt = f"{TASKS[task]}\n\n<text>\n{text}\n</text>"
    system = "Ты выполняешь одну операцию над текстом и выводишь только результат."
    b = backend()
    if b == "claude":
        gen = claude_stream(prompt, system=system, persist=False)
    elif b == "api":
        gen = api_stream([{"role": "user", "content": prompt}], system=system)
    else:
        raise SystemExit("ИИ не настроен: нужен Claude Code или API-ключ")
    out = []
    for kind, val in gen:
        if kind == "delta":
            out.append(val)
        elif kind == "error":
            raise SystemExit(val)
    print("".join(out).strip())


def cmd_setup_api():
    VENV.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run([sys.executable, "-m", "venv", str(VENV)], check=True)
    subprocess.run([str(VENV / "bin/pip"), "install", "-q", "--upgrade", "anthropic"], check=True)
    print(f"SDK anthropic установлен в {VENV}")


def on_term(*_):   # панель останавливает ответ через SIGTERM — сохраняем то, что уже пришло
    raise KeyboardInterrupt


def main():
    signal.signal(signal.SIGTERM, on_term)
    cmd = sys.argv[1] if len(sys.argv) > 1 else ""
    if cmd == "info":
        cmd_info()
    elif cmd == "history":
        print(json.dumps(load_chat().get("messages", []), ensure_ascii=False))
    elif cmd == "send":
        cmd_send()
    elif cmd == "reset":
        save_chat({})
    elif cmd == "once" and len(sys.argv) > 2 and sys.argv[2] in TASKS:
        cmd_once(sys.argv[2])
    elif cmd == "setup-api":
        cmd_setup_api()
    else:
        raise SystemExit(f"неизвестная команда: {' '.join(sys.argv[1:])}")


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        sys.exit(130)
