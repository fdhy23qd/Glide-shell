#!/usr/bin/env python3
import ast, json, math, operator as op, os, subprocess, sys
from pathlib import Path

state = Path(os.environ.get("XDG_STATE_HOME") or Path.home() / ".local/state") / "glide-shell"
hist = state / "calc.json"
BIN = {ast.Add: op.add, ast.Sub: op.sub, ast.Mult: op.mul, ast.Div: op.truediv,
       ast.FloorDiv: op.floordiv, ast.Mod: op.mod, ast.Pow: op.pow}
UN = {ast.USub: op.neg, ast.UAdd: op.pos}
FUNCS = {n: getattr(math, n) for n in
         ("sqrt", "sin", "cos", "tan", "log", "log2", "log10", "exp", "floor", "ceil",
          "radians", "degrees")}
FUNCS.update(abs=abs, round=round, min=min, max=max)
CONST = {"pi": math.pi, "e": math.e}


def ev(n):
    if isinstance(n, ast.Expression):
        return ev(n.body)
    if isinstance(n, ast.Constant) and isinstance(n.value, (int, float)) and not isinstance(n.value, bool):
        return n.value
    if isinstance(n, ast.BinOp) and type(n.op) in BIN:
        a, b = ev(n.left), ev(n.right)
        if isinstance(n.op, ast.Pow):
            if abs(b) > 1000:
                raise ValueError("слишком большая степень")
            # целые растут без предела: (9^999)^999 — уже миллионы цифр; > 100 000 бит не считаем
            if isinstance(a, int) and isinstance(b, int) and b > 0 and abs(a) > 1 and b * math.log2(abs(a)) > 100_000:
                raise ValueError("слишком большое число")
        return BIN[type(n.op)](a, b)
    if isinstance(n, ast.UnaryOp) and type(n.op) in UN:
        return UN[type(n.op)](ev(n.operand))
    if isinstance(n, ast.Name) and n.id in CONST:
        return CONST[n.id]
    if (isinstance(n, ast.Call) and isinstance(n.func, ast.Name) and n.func.id in FUNCS
            and not n.keywords):
        return FUNCS[n.func.id](*[ev(a) for a in n.args])
    raise ValueError("выражение не поддерживается")


def load():
    try:
        return json.loads(hist.read_text())
    except (OSError, ValueError):
        return []


cmd = sys.argv[1] if len(sys.argv) > 1 else ""
if cmd == "eval":
    expr = os.environ.get("QP_TEXT", "").strip()
    try:
        r = ev(ast.parse(expr.replace("^", "**").replace("×", "*").replace("÷", "/"),
                         mode="eval"))
        if isinstance(r, complex):
            raise ValueError("комплексный результат")
        if isinstance(r, float) and r.is_integer() and abs(r) < 1e15:
            r = int(r)
        res = (str(r) if abs(r) < 10**30 else f"{r:.12e}") if isinstance(r, int) else f"{r:.12g}"
    except Exception as e:
        print(f"{expr}: {e}", file=sys.stderr)
        sys.exit(1)
    items = [{"expr": expr, "res": res}] + [h for h in load() if h.get("expr") != expr]
    state.mkdir(parents=True, exist_ok=True)
    hist.write_text(json.dumps(items[:20], ensure_ascii=False))
    try:
        subprocess.run(["notify-send", "-a", "Glide Shell", expr, f"= {res}"], stderr=subprocess.DEVNULL)
    except OSError:
        pass
    print(res)
elif cmd == "list":
    for h in load():
        print(f"{h['res']}\t{h['expr']} = {h['res']}")
