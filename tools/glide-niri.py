#!/usr/bin/env python3
"""Настройки niri из панели Glide Shell: клавиатура, тачпад, мышь, мониторы, список горячих клавиш.

    glide-niri.py read                 — JSON: {"managed", "input": {...}, "binds": [...]}
    glide-niri.py set-input JSON        — изменить ввод (частичный JSON того же вида), проверить niri validate
    glide-niri.py save-outputs JSON     — [{name, mode "WxH@R", scale, transform, x, y, off}] → glide-outputs.kdl

Как устроено (проверено на niri 26.04): у обычных разделов (input, layout…) из нескольких определений побеждает
ПОСЛЕДНЕЕ и слияние идёт по полям, у мониторов (output "имя") — ПЕРВОЕ. Флаги вида `tap` позже выключить нельзя
(`tap false` niri не принимает). Поэтому при первой правке ввода блок `input { }` пользователя ПЕРЕНОСИТСЯ
в ~/.config/niri/glide-settings.kdl (в config.kdl он закомментирован с пометкой, копия — рядом), файл подключается
в конце config.kdl; мониторы — glide-outputs.kdl, подключён в начале. Узлы, которых панель не знает, переносятся
дословно. Любая запись проверяется `niri validate`; не прошла — оба файла возвращаются как были.
"""
import json
import os
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path

NIRI = Path(os.environ.get("GLIDE_NIRI_DIR") or Path(os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config") / "niri")
CONFIG = NIRI / "config.kdl"
SETTINGS = NIRI / "glide-settings.kdl"
OUTPUTS = NIRI / "glide-outputs.kdl"
MARK = "// [glide-shell] "
HEAD = "// Glide Shell: настройки niri из панели («Настройки» → «niri»). Файл пишет оболочка — правки руками\n" \
       "// сохраняются, пока их не поменяли в панели.\n"


# ------------------------------------------------------------------ разбор KDL (то подмножество, что у niri)
class Node:
    def __init__(self, name, start):
        self.name, self.args, self.props, self.children = name, [], {}, None
        self.start, self.end = start, start      # границы в исходном тексте (для дословного переноса)
        self.dirty = False
        self.raw_args = ""                        # исходный текст аргументов и свойств

    def child(self, name):
        for c in self.children or []:
            if c.name == name:
                return c
        return None


def tokenize(src):
    """Токены: (тип, значение, начало, конец). Типы: id, str, num, '{', '}', ';', nl, '=', slashdash."""
    i, n, out = 0, len(src), []
    while i < n:
        c = src[i]
        if c in " \t\r":
            i += 1
        elif c == "\\":                                   # продолжение строки
            j = src.find("\n", i)
            i = n if j < 0 else j + 1
        elif c == "\n":
            out.append(("nl", None, i, i + 1)); i += 1
        elif src.startswith("//", i):
            j = src.find("\n", i)
            i = n if j < 0 else j
        elif src.startswith("/*", i):
            depth, j = 1, i + 2
            while j < n and depth:
                if src.startswith("/*", j): depth += 1; j += 2
                elif src.startswith("*/", j): depth -= 1; j += 2
                else: j += 1
            i = j
        elif src.startswith("/-", i):
            out.append(("slashdash", None, i, i + 2)); i += 2
        elif c in "{};=":
            out.append((c, c, i, i + 1)); i += 1
        elif c == '"':
            j, buf = i + 1, []
            while j < n and src[j] != '"':
                if src[j] == "\\" and j + 1 < n:
                    buf.append({"n": "\n", "t": "\t", '"': '"', "\\": "\\"}.get(src[j + 1], src[j + 1])); j += 2
                else:
                    buf.append(src[j]); j += 1
            out.append(("str", "".join(buf), i, j + 1)); i = j + 1
        elif c == "r" and re.match(r'r#*"', src[i:i + 40] or ""):
            m = re.match(r'r(#*)"', src[i:]); hashes = m.group(1)
            end = src.find('"' + hashes, i + len(m.group(0)))
            end = n if end < 0 else end
            out.append(("str", src[i + len(m.group(0)):end], i, end + 1 + len(hashes))); i = end + 1 + len(hashes)
        else:
            m = re.match(r'[^\s{};="\\]+', src[i:])
            tok = m.group(0)
            if re.fullmatch(r"[+-]?\d[\d_]*(\.\d+)?([eE][+-]?\d+)?", tok):
                out.append(("num", float(tok.replace("_", "")) if "." in tok or "e" in tok.lower() else int(tok.replace("_", "")), i, i + len(tok)))
            else:
                out.append(("id", tok, i, i + len(tok)))
            i += len(tok)
    return out


def parse(src):
    toks, pos = tokenize(src), 0

    def nodes(until_brace):
        nonlocal pos
        out = []
        while pos < len(toks):
            t = toks[pos]
            if t[0] in ("nl", ";"):
                pos += 1; continue
            if t[0] == "}":
                if until_brace:
                    return out, t[3]
                pos += 1; continue
            skip = False
            if t[0] == "slashdash":
                skip = True; pos += 1
                while pos < len(toks) and toks[pos][0] == "nl": pos += 1
                if pos >= len(toks): break
                t = toks[pos]
            node = Node(str(t[1]), t[2]); pos += 1
            arg_from = t[3]
            while pos < len(toks) and toks[pos][0] not in ("nl", ";", "{", "}"):
                tk = toks[pos]
                if tk[0] == "slashdash":                     # закомментированный аргумент
                    pos += 2; continue
                if pos + 2 < len(toks) and toks[pos + 1][0] == "=":
                    node.props[str(tk[1])] = toks[pos + 2][1]; pos += 3
                else:
                    v = tk[1]
                    if tk[0] == "id" and v in ("true", "#true"): v = True
                    elif tk[0] == "id" and v in ("false", "#false"): v = False
                    node.args.append(v); pos += 1
            node.raw_args = src[arg_from:toks[pos - 1][3]] if toks[pos - 1][2] >= arg_from else ""
            node.end = toks[pos - 1][3]
            if pos < len(toks) and toks[pos][0] == "{":
                pos += 1
                node.children, close_end = nodes(True)
                pos += 1
                node.end = close_end
            if not skip:
                out.append(node)
        return out, len(src)

    tree, _ = nodes(False)
    return tree


def find(tree, name):
    return [n for n in tree if n.name == name]


# ------------------------------------------------------------------ вывод KDL
def q(s):
    return '"' + str(s).replace("\\", "\\\\").replace('"', '\\"') + '"'


def render(node, src, depth):
    """Узел текстом: нетронутый — дословно из исходника, изменённый — заново (дети — так же)."""
    pad = "    " * depth
    if not node.dirty:
        return pad + src[node.start:node.end]
    head = node.name
    if node.raw_args and not node.args_changed:
        head += " " + node.raw_args.strip()
    else:
        for a in node.args:
            head += " " + (q(a) if isinstance(a, str) else ("true" if a is True else "false" if a is False else str(a)))
        for k, v in node.props.items():
            head += f" {k}=" + (q(v) if isinstance(v, str) else str(v))
    if node.children is None:
        return pad + head
    inner = "\n".join(render(c, src, depth + 1) for c in node.children)
    return pad + head + " {\n" + inner + ("\n" if inner else "") + pad + "}"


Node.args_changed = False


# ------------------------------------------------------------------ чтение настроек ввода
def input_node(tree):
    ns = find(tree, "input")
    return ns[-1] if ns else None


def flag(node, name):
    return bool(node and node.child(name) is not None)


def val(node, name, default=None):
    c = node.child(name) if node else None
    return c.args[0] if c is not None and c.args else default


def read_input(tree):
    inp = input_node(tree)
    kb = inp.child("keyboard") if inp else None
    xkb = kb.child("xkb") if kb else None
    tp = inp.child("touchpad") if inp else None
    ms = inp.child("mouse") if inp else None
    return {
        "keyboard": {"layout": val(xkb, "layout", ""), "variant": val(xkb, "variant", ""), "options": val(xkb, "options", ""),
                     "repeat_delay": val(kb, "repeat-delay"), "repeat_rate": val(kb, "repeat-rate"),
                     "numlock": flag(kb, "numlock"), "track_layout": val(kb, "track-layout", "global")},
        "touchpad": {"tap": flag(tp, "tap"), "natural_scroll": flag(tp, "natural-scroll"), "dwt": flag(tp, "dwt"),
                     "accel_speed": val(tp, "accel-speed", 0.0), "accel_profile": val(tp, "accel-profile", "adaptive"),
                     "disabled_on_external_mouse": flag(tp, "disabled-on-external-mouse"), "off": flag(tp, "off")},
        "mouse": {"natural_scroll": flag(ms, "natural-scroll"), "accel_speed": val(ms, "accel-speed", 0.0),
                  "accel_profile": val(ms, "accel-profile", "adaptive")},
        "focus_follows_mouse": flag(inp, "focus-follows-mouse"),
        "warp_mouse_to_focus": flag(inp, "warp-mouse-to-focus"),
    }


def read_binds(tree, src):
    out = []
    for b in find(tree, "binds"):
        for n in b.children or []:
            act = n.children[0] if n.children else None
            action = ""
            if act is not None:
                action = act.name + (" " + " ".join(str(a) for a in act.args) if act.args else "")
            out.append({"key": n.name, "title": n.props.get("hotkey-overlay-title", ""), "action": action[:200]})
    return out


def effective_tree():
    """Где сейчас живёт ввод: в файле оболочки (если перенесён) или в config.kdl."""
    if SETTINGS.exists():
        s = SETTINGS.read_text()
        t = parse(s)
        if input_node(t) is not None:
            return t, s, True
    s = CONFIG.read_text()
    return parse(s), s, False


# ------------------------------------------------------------------ правка ввода
def ensure(node, name, src):
    """Дочерний узел (создать пустой блок, если нет)."""
    c = node.child(name)
    if c is None:
        c = Node(name, 0); c.children = []; c.dirty = True; c.args_changed = True
        node.children = (node.children or []) + [c]
    if c.children is None:
        c.children = []
    return c


def set_flag(node, name, on):
    has = node.child(name) is not None
    if on and not has:
        n = Node(name, 0); n.dirty = True; n.args_changed = True
        node.children.append(n)
    elif not on and has:
        node.children = [c for c in node.children if c.name != name]
    else:
        return False
    return True


def set_val(node, name, value):
    c = node.child(name)
    if value is None or value == "":
        if c is None:
            return False
        node.children = [x for x in node.children if x.name != name]
        return True
    if c is not None and c.args and c.args[0] == value:
        return False
    if c is None:
        c = Node(name, 0); node.children.append(c)
    c.args, c.props, c.children = [value], {}, None
    c.dirty = c.args_changed = True
    return True


def apply_input(tree, patch):
    inp = input_node(tree)
    if inp is None:
        inp = Node("input", 0); inp.children = []; tree.append(inp)
    if inp.children is None:
        inp.children = []
    changed = []

    def mark(*nodes):
        for n in nodes: n.dirty = True

    kb = patch.get("keyboard") or {}
    if kb:
        k = ensure(inp, "keyboard", None)
        x = ensure(k, "xkb", None)
        for key, name in (("layout", "layout"), ("variant", "variant"), ("options", "options")):
            if key in kb and set_val(x, name, kb[key]): mark(inp, k, x); changed.append(name)
        for key, name in (("repeat_delay", "repeat-delay"), ("repeat_rate", "repeat-rate")):
            if key in kb and set_val(k, name, kb[key]): mark(inp, k); changed.append(name)
        if "numlock" in kb and set_flag(k, "numlock", kb["numlock"]): mark(inp, k); changed.append("numlock")
        if "track_layout" in kb and set_val(k, "track-layout", None if kb["track_layout"] == "global" else kb["track_layout"]):
            mark(inp, k); changed.append("track-layout")
    for sec, flags, vals in (("touchpad", ("tap", "natural_scroll", "dwt", "disabled_on_external_mouse", "off"),
                              ("accel_speed", "accel_profile")),
                             ("mouse", ("natural_scroll",), ("accel_speed", "accel_profile"))):
        p = patch.get(sec) or {}
        if not p:
            continue
        nd = ensure(inp, sec, None)
        for f in flags:
            if f in p and set_flag(nd, f.replace("_", "-"), p[f]): mark(inp, nd); changed.append(sec + "." + f)
        for v in vals:
            if v in p:
                value = p[v]
                if v == "accel_speed": value = None if value in (None, 0, 0.0) else round(float(value), 2)
                if v == "accel_profile" and value == "adaptive": value = None
                if set_val(nd, v.replace("_", "-"), value): mark(inp, nd); changed.append(sec + "." + v)
    for f in ("focus_follows_mouse", "warp_mouse_to_focus"):
        if f in patch and set_flag(inp, f.replace("_", "-"), patch[f]): mark(inp); changed.append(f)
    return inp, changed


def validate():
    r = subprocess.run(["niri", "validate", "-c", str(CONFIG)], capture_output=True, text=True, stdin=subprocess.DEVNULL)
    if r.returncode == 0:
        return None
    err = re.sub(r"\x1b\[[0-9;]*m", "", r.stderr + r.stdout)
    lines = [l for l in err.splitlines() if l.strip() and "DEBUG" not in l]
    return "\n".join(lines[-12:])


def backup(path):
    if path.exists():
        stamp = time.strftime("%Y%m%d-%H%M%S")
        shutil.copy2(path, path.with_name(path.name + ".before-glide-" + stamp))


def migrate():
    """Перенести блок input из config.kdl в glide-settings.kdl (комментарий с пометкой) и подключить файл."""
    src = CONFIG.read_text()
    tree = parse(src)
    inp = input_node(tree)
    block = src[inp.start:inp.end] if inp else "input {\n}"
    new = src
    if inp:
        line_start = src.rfind("\n", 0, inp.start) + 1
        commented = "\n".join(MARK + l if l.strip() else l for l in src[line_start:inp.end].split("\n"))
        new = src[:line_start] + MARK + "перенесено в glide-settings.kdl (настройки niri в Glide Shell)\n" + commented + src[inp.end:]
    if 'include "glide-settings.kdl"' not in new:
        new = new.rstrip("\n") + '\n\n// Glide Shell: ввод и прочие настройки niri из панели (подключать последним)\ninclude "glide-settings.kdl"\n'
    backup(CONFIG)
    SETTINGS.write_text(HEAD + "\n" + block + "\n")
    CONFIG.write_text(new)


def write_settings(tree, src):
    parts = []
    for n in tree:
        parts.append(render(n, src, 0))
    SETTINGS.write_text(HEAD + "\n" + "\n\n".join(parts) + "\n")


def set_input(patch):
    old_conf = CONFIG.read_text() if CONFIG.exists() else None
    old_set = SETTINGS.read_text() if SETTINGS.exists() else None
    try:
        tree, src, managed = effective_tree()
        if not managed:
            migrate()
            tree, src, managed = effective_tree()
        _, changed = apply_input(tree, patch)
        if changed:
            write_settings(tree, src)
        err = validate()
        if err:
            raise RuntimeError(err)
        return {"ok": True, "changed": changed}
    except Exception as e:
        if old_conf is not None: CONFIG.write_text(old_conf)
        if old_set is None: SETTINGS.unlink(missing_ok=True)
        else: SETTINGS.write_text(old_set)
        return {"ok": False, "error": str(e)}


# ------------------------------------------------------------------ мониторы
def save_outputs(items):
    old_conf = CONFIG.read_text()
    old_out = OUTPUTS.read_text() if OUTPUTS.exists() else None
    try:
        blocks = []
        for o in items:
            lines = []
            if o.get("off"):
                lines.append("    off")
            else:
                if o.get("mode"): lines.append(f"    mode {q(o['mode'])}")
                if o.get("scale"): lines.append(f"    scale {float(o['scale']):g}")
                if o.get("transform") and o["transform"] != "normal": lines.append(f"    transform {q(o['transform'])}")
                if "x" in o and "y" in o: lines.append(f"    position x={int(o['x'])} y={int(o['y'])}")
            blocks.append(f"output {q(o['name'])} {{\n" + "\n".join(lines) + "\n}")
        OUTPUTS.write_text(HEAD + "// Мониторы: этот файл подключён ПЕРВЫМ — у niri для монитора побеждает первое определение.\n\n"
                           + "\n\n".join(blocks) + "\n")
        if 'include "glide-outputs.kdl"' not in old_conf:
            backup(CONFIG)
            CONFIG.write_text('// Glide Shell: мониторы из панели (подключать первым)\ninclude "glide-outputs.kdl"\n\n' + old_conf)
        err = validate()
        if err:
            raise RuntimeError(err)
        return {"ok": True}
    except Exception as e:
        CONFIG.write_text(old_conf)
        if old_out is None: OUTPUTS.unlink(missing_ok=True)
        else: OUTPUTS.write_text(old_out)
        return {"ok": False, "error": str(e)}


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else "read"
    if cmd == "read":
        tree, src, managed = effective_tree()
        csrc = CONFIG.read_text()
        print(json.dumps({"managed": managed, "input": read_input(tree), "binds": read_binds(parse(csrc), csrc)}, ensure_ascii=False))
    elif cmd == "set-input":
        print(json.dumps(set_input(json.loads(sys.argv[2])), ensure_ascii=False))
    elif cmd == "save-outputs":
        print(json.dumps(save_outputs(json.loads(sys.argv[2])), ensure_ascii=False))
    else:
        sys.exit("glide-niri.py read | set-input JSON | save-outputs JSON")


if __name__ == "__main__":
    main()
