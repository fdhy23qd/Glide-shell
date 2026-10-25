#!/usr/bin/env python3
"""Оглавление документации: между <!-- toc --> и <!-- /toc --> — ссылки на все заголовки ## и ###.

    docs-toc.py           — обновить docs/API.md, docs/API.ru.md, README.md, README.ru.md
    docs-toc.py --check   — только проверить (код 1, если оглавление устарело); так делает tests/test_helpers.py

В справочниках API перед каждой чертой «---» после оглавления ставится ссылка «↑ к оглавлению» — длинный документ
листается назад одним щелчком. Якоря — как у GitHub: строчные буквы, пробел → «-», знаки препинания убираются.
В русских файлах (ASCII_IDS) у каждого заголовка свой латинский якорь прямо в строке: `## <a id="ustanovka"></a>Установка`
— кириллические якоря GitHub понимает, а мобильное приложение и многие просмотрщики нет. Ссылки на прежние
кириллические якоря внутри документа переписываются на латинские.
"""
import re
import sys
import unicodedata
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FILES = ["docs/API.md", "docs/API.ru.md", "README.md", "README.ru.md"]
START, END = "<!-- toc -->", "<!-- /toc -->"
ASCII_IDS = {"docs/API.ru.md", "README.ru.md"}
BACK = {"Contents": "[↑ Contents](#contents)", "Оглавление": "[↑ К оглавлению](#oglavlenie)"}
TAG = re.compile(r'^<a id="([^"]+)"></a>')
TR = dict(zip("абвгдеёзийклмнопрстуфхцыэ", "abvgdeeziyklmnoprstufhcye"))
TR.update({"ж": "zh", "ч": "ch", "ш": "sh", "щ": "sch", "ю": "yu", "я": "ya", "ъ": "", "ь": ""})


def translit(anchor):
    return "".join(TR.get(ch, ch) for ch in anchor)


def slug(title):
    """Якорь заголовка, как его строит GitHub (github-slugger)."""
    out = []
    for ch in title.strip().lower():
        if ch.isalnum() or ch in " -_" or unicodedata.category(ch).startswith("M"):
            out.append(ch)
    return "".join(out).replace(" ", "-")


def headings(text):
    """[(уровень, заголовок, якорь)] вне блоков кода; повторяющиеся якоря получают -1, -2…"""
    seen, out, code = {}, [], False
    for line in text.splitlines():
        if line.lstrip().startswith("```"):
            code = not code
            continue
        m = None if code else re.match(r"(#{1,6})\s+(.*?)\s*#*\s*$", line)
        if not m:
            continue
        title = m.group(2)
        tag = TAG.match(title)
        if tag:   # свой якорь в заголовке: он и есть адрес, заголовок — без тега
            title = title[tag.end():]
        base = slug(title)
        n = seen.get(base, 0)
        seen[base] = n + 1
        out.append((len(m.group(1)), title, tag.group(1) if tag else base if n == 0 else f"{base}-{n}"))
    return out


def ascii_ids(text):
    """Каждому заголовку — латинский якорь в строке; ссылки на прежние кириллические якоря — на новые."""
    old = {}
    lines, code, seen = text.split("\n"), False, {}
    for i, line in enumerate(lines):
        if line.lstrip().startswith("```"):
            code = not code
            continue
        m = None if code else re.match(r"(#{1,6})\s+(.*?)\s*#*\s*$", line)
        if not m or len(m.group(1)) == 1:
            continue
        title = m.group(2)
        tag = TAG.match(title)
        if tag:
            title = title[tag.end():]
        base = slug(title)
        n = seen.get(base, 0)
        seen[base] = n + 1
        gh = base if n == 0 else f"{base}-{n}"
        new = translit(gh)
        old[gh] = new
        lines[i] = f'{m.group(1)} <a id="{new}"></a>{title}'
    text = "\n".join(lines)
    return re.sub(r"\]\(#([^)\s]+)\)", lambda mm: "](#" + old.get(mm.group(1), mm.group(1)) + ")", text)


def build(text, back_links):
    toc_title = next((t for lvl, t, _ in headings(text) if lvl == 2 and t in BACK), None)
    if not toc_title or START not in text:
        return text
    head, rest = text.split(START, 1)
    rest = rest.split(END, 1)[1] if END in rest else rest
    lines = rest.split("\n")
    if back_links:   # «наверх» — убрать старые и поставить перед каждой чертой после первого раздела и в конце
        back = BACK[toc_title]
        out, seen = [], False
        for line in (x for x in lines if x.strip() != back):
            if line.startswith("## "):
                seen = True
            if line.strip() == "---" and seen:
                while out and out[-1] == "":
                    out.pop()
                out += ["", back, ""]
            out.append(line)
        while out and out[-1] == "":
            out.pop()
        lines = out + ["", back, ""]
    rest = "\n".join(lines)
    entries = ["  " * (lvl - 2) + f"- [{title}](#{anchor})" for lvl, title, anchor in headings(rest) if lvl in (2, 3)]
    return head + START + "\n" + "\n".join(entries) + "\n" + END + rest


def links_ok(text):
    """Якоря ссылок [..](#якорь) внутри документа, которых нет среди заголовков."""
    anchors = {a for _, _, a in headings(text)}
    return sorted({a for a in re.findall(r"\]\(#([^)\s]+)\)", text) if a not in anchors})


def main(argv):
    check = "--check" in argv
    stale = []
    for name in FILES:
        f = ROOT / name
        text = f.read_text()
        new = build(ascii_ids(text) if name in ASCII_IDS else text, name.startswith("docs/"))
        broken = links_ok(new)
        if broken:
            stale.append(f"{name}: ссылки на несуществующие заголовки: {', '.join(broken)}")
        if new != text:
            if check:
                stale.append(f"{name}: оглавление устарело — запусти tools/docs-toc.py")
            else:
                f.write_text(new)
                print(f"обновлено: {name}")
    if stale:
        print("\n".join(stale), file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main(sys.argv[1:])
