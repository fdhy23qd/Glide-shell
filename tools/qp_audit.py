"""Общее для qp-discover.py и glide-widgets.py: разрешения API 2 и подсказка, что код обходит api.

Не защита (песочницы нет, docs/API.md, раздел 10), а подсказка человеку в «Настройки» → «Плагины».
"""
import re

# то же в Permissions.qml
PERMISSIONS = ["exec", "network", "clipboard", "notifications", "windows", "phone", "system", "messages", "island"]

# обращения к системе в обход api
AUDIT = [(re.compile(r"import\s+Quickshell\.Io\b"), "Quickshell.Io"), (re.compile(r"\bProcess\s*\{"), "Process"),
         (re.compile(r"\bexecDetached\b"), "execDetached"), (re.compile(r"\bXMLHttpRequest\b"), "XMLHttpRequest"),
         (re.compile(r"\bcreateQmlObject\b"), "createQmlObject"), (re.compile(r"\bQuickshell\.Services\.Pam\b"), "Pam"),
         (re.compile(r"\bPermissions\s*\."), "Permissions"), (re.compile(r"\bPrefs\s*\.\s*(?:set|run|reset|data)\b"), "Prefs"),
         # внутренние объекты оболочки (через import qs): ими можно выдать себе права или действовать мимо api
         (re.compile(r"\bCore\s*\.\s*root\b"), "Core.root"),
         (re.compile(r"\b(?:Notifs|Niri|KdeConnect|Recorder|Activities|LockScreen|Updates|ArchUpdates|LauncherEntries)\s*\."), "внутренние объекты"),
         (re.compile(r"\bApiScope\b"), "ApiScope"), (re.compile(r"\bQt\s*\.\s*createComponent\b"), "createComponent"), (re.compile(r"[\"']data:"), "data: URL")]


def audit(d):
    """Какие обходы встречаются в QML и JS папки d: ["Process", "XMLHttpRequest", …]."""
    found = []
    for f in sorted(d.rglob("*")):
        if f.suffix not in (".qml", ".js", ".mjs") or not f.is_file():
            continue
        try:
            text = f.read_text(errors="replace")
        except OSError:
            continue
        found += [name for rx, name in AUDIT if name not in found and rx.search(text)]
    return found
