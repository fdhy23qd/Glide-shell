#!/usr/bin/env python3
"""Заготовки для разработчиков Glide Shell (описание API — docs/API.md).

    glide-plugin.py new ID [ИМЯ]      — плагин API 2 в ~/.config/glide-shell/plugins/ID: раздел панели (Main.qml),
                                        элемент бара (Bar.qml), настройки и запрос разрешения — рабочий пример API
    glide-plugin.py widget ID [ИМЯ]   — свой виджет рабочего стола в ~/.config/glide-shell/widgets/ID
    glide-plugin.py pack ПАПКА [ФАЙЛ] — архив плагина для передачи (zip, по умолчанию ID.glideplugin) с проверками
    glide-plugin.py find              — JSON: архивы с плагинами в «Загрузках» за последние 30 дней (до 10)
    glide-plugin.py inspect АРХИВ     — JSON: что внутри (id, имя, разрешения, пометки аудита) — без установки
    glide-plugin.py install АРХИВ [--replace] — поставить в ~/.config/glide-shell/plugins/ID; прежняя версия —
                                        в ~/.local/state/glide-shell/plugin-backups

Плагин появится при следующем открытии панели (настройки — «Плагины», элемент бара — «Бар»).
Архив — обычный .zip или .tar.gz (.glideplugin — тот же zip): plugin.json в корне или в единственной папке внутри.
Свой формат не нужен: проверка одинакова для любого архива. Разрешения после установки всё равно выдаёт человек.
"""
import io
import json
import os
import re
import shutil
import stat
import sys
import tarfile
import tempfile
import time
import zipfile
from pathlib import Path

CFG = Path(os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config") / "glide-shell"
STATE = Path(os.environ.get("XDG_STATE_HOME") or Path.home() / ".local/state") / "glide-shell"
SHELL = Path(__file__).resolve().parent.parent          # папка оболочки: встроенные плагины — её plugins/
ID_RE = re.compile(r"[a-z0-9][a-z0-9_.-]{0,63}")
MAX_FILES, MAX_BYTES = 2000, 50 * 1024 * 1024
sys.path.insert(0, str(Path(__file__).resolve().parent))

PLUGIN_QML = r'''import QtQuick
import QtQuick.Layouts
import qs

// Раздел плагина в панели. api — docs/API.md: хранилище, настройки, уведомления, события, разрешения.
ColumnLayout {
    id: root
    property var api
    property string pluginDir
    spacing: 8

    readonly property int clicks: api ? api.storage.get("clicks", 0) : 0
    property string lastNotif: ""
    // чужие уведомления — по разрешению «notifications» (объявлено в plugin.json, выдаёт человек в «Плагинах»)
    readonly property bool canNotifs: !!api && api.permissions.granted.indexOf("notifications") >= 0

    Connections {   // события оболочки (ignoreUnknownSignals: пока api не передан, сигналов у цели нет)
        target: root.api
        ignoreUnknownSignals: true
        function onOpened() { root.api.log("панель открыта") }
        function onNotification(e) { root.lastNotif = e.appName + ": " + e.summary }
    }

    Text {
        text: root.api ? root.api.settings.greeting : ""
        color: Theme.text; font.pixelSize: Theme.fs(15); font.bold: true
    }
    Text {
        Layout.fillWidth: true
        text: "Нажатий: " + root.clicks + (root.api && root.api.player ? "  ·  играет: " + (root.api.player.trackTitle || "—") : "")
              + (root.lastNotif ? "\nПоследнее уведомление: " + root.lastNotif : "")
        color: Theme.textSecondary; font.pixelSize: Theme.fs(12); wrapMode: Text.WordWrap
    }
    Row {
        spacing: 8
        Rectangle {
            width: 120; height: 36; radius: Theme.r(18)
            color: ma.pressed ? Theme.accentPressed : ma.containsMouse ? Theme.accentLight : Theme.accent
            Text { anchors.centerIn: parent; text: "+1"; color: Theme.accentText; font.pixelSize: Theme.fs(13) }
            MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: root.api.storage.set("clicks", root.clicks + 1) }
        }
        Rectangle {
            width: 160; height: 36; radius: Theme.r(18)
            color: nm.pressed ? Theme.surfacePressed : nm.containsMouse ? Theme.surfaceHigher : Theme.surfaceHigh
            Text { anchors.centerIn: parent; text: "Уведомление"; color: Theme.text; font.pixelSize: Theme.fs(13) }
            MouseArea { id: nm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: root.api.notify("__NAME__", "Нажатий: " + root.clicks) }
        }
    }
    Text {   // без разрешения — объяснить и попросить; решает человек
        visible: !!root.api && !root.canNotifs
        Layout.fillWidth: true
        text: "Чтобы показывать последнее уведомление, нужно разрешение. Нажми, чтобы спросить."
        color: Theme.accent; font.pixelSize: Theme.fs(12); wrapMode: Text.WordWrap
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                    onClicked: root.api.permissions.request("notifications", "Показать последнее уведомление в разделе") }
    }
}
'''

BAR_QML = r'''import QtQuick
import qs

// Элемент бара плагина: want — показывать ли сейчас; щелчок — что угодно через api.
// Размер — от содержимого (implicitWidth), щелчок — MouseArea поверх (anchors.fill), не внутри Row.
Item {
    id: chip
    property var api
    readonly property bool want: !!api && api.settings.showBar && api.storage.get("clicks", 0) > 0
    implicitWidth: row.implicitWidth
    implicitHeight: 24
    Row {
        id: row
        anchors.verticalCenter: parent.verticalCenter
        spacing: 4
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "󰐱"; color: Theme.accent; font.family: chip.api ? chip.api.iconFont : ""; font.pixelSize: Theme.fs(14)
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: chip.api ? chip.api.storage.get("clicks", 0) : ""
            color: Theme.textVariant; font.pixelSize: Theme.fs(12)
        }
    }
    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: chip.api.flash("󰐱", "Нажатий: " + chip.api.storage.get("clicks", 0))
    }
}
'''

WIDGET_QML = r'''import QtQuick

// Свой виджет рабочего стола. api — docs/API.md (плюс k — масштаб, tint/sub — цвета текста), cfg — настройки из widget.json.
Column {
    property var api
    property var cfg: ({})
    spacing: 4 * (api ? api.k : 1)
    Text {
        text: cfg.title || "Виджет"
        color: api ? api.tint : "white"
        font.pixelSize: Math.round(28 * (api ? api.k : 1)); font.weight: Font.DemiBold
    }
    Text {
        text: api ? Qt.formatTime(api.now, "HH:mm") + "  ·  " + Math.round(api.cpu) + "% ЦП" : ""
        color: api ? api.sub : "gray"
        font.pixelSize: Math.round(14 * (api ? api.k : 1))
    }
}
'''


def write(dest, files):
    if dest.exists():
        sys.exit(f"уже есть: {dest}")
    dest.mkdir(parents=True)
    for name, text in files.items():
        (dest / name).write_text(text)
    print(dest)


# ------------------------------------------------------------------ архивы
class Bad(Exception):
    pass


def members(path):
    """[(имя, размер, тип, читатель)] — тип: file | dir | other (ссылки, устройства — не принимаем)."""
    out = []
    if zipfile.is_zipfile(path):
        z = zipfile.ZipFile(path)
        for i in z.infolist():
            mode = (i.external_attr >> 16) & 0o170000
            kind = "dir" if i.is_dir() else "other" if mode and mode not in (stat.S_IFREG,) else "file"
            out.append((i.filename, i.file_size, kind, (lambda i=i: z.read(i))))
        return out
    try:
        t = tarfile.open(path)
    except (tarfile.TarError, OSError):
        raise Bad("не архив (нужен .zip, .glideplugin или .tar.gz)")
    for m in t.getmembers():
        kind = "dir" if m.isdir() else "file" if m.isfile() else "other"
        out.append((m.name, m.size, kind, (lambda m=m: t.extractfile(m).read())))
    return out


def safe_name(name):
    parts = [p for p in name.replace("\\", "/").split("/") if p not in ("", ".")]
    if name.startswith("/") or any(p == ".." for p in parts) or not parts:
        raise Bad(f"путь наружу в архиве: {name}")
    return parts


def unpack(path, dest):
    """Распаковать в dest с проверками; вернуть папку с plugin.json."""
    items = members(path)
    if len(items) > MAX_FILES:
        raise Bad(f"слишком много файлов ({len(items)})")
    if sum(x[1] for x in items) > MAX_BYTES:
        raise Bad("распакованный архив больше 50 МБ")
    for name, size, kind, data in items:
        parts = safe_name(name)
        if kind == "other":
            raise Bad(f"ссылка или особый файл в архиве: {name}")
        target = dest.joinpath(*parts)
        if kind == "dir":
            target.mkdir(parents=True, exist_ok=True)
            continue
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data())
        target.chmod(0o644)                 # права из архива не переносим: исполняемым ничего не станет само
    if (dest / "plugin.json").is_file():
        return dest
    tops = [p for p in dest.iterdir()]
    if len(tops) == 1 and tops[0].is_dir() and (tops[0] / "plugin.json").is_file():
        return tops[0]
    raise Bad("нет plugin.json (в корне архива или в единственной папке внутри)")


def builtin_ids():
    d = SHELL / "plugins"
    return {p.name for p in d.iterdir() if p.is_dir()} if d.is_dir() else set()


def describe(d):
    """Карточка плагина из папки: то, что человек должен увидеть до установки."""
    try:
        m = json.loads((d / "plugin.json").read_text())
    except (OSError, ValueError) as e:
        raise Bad(f"plugin.json не читается: {e}")
    pid = m.get("id")
    if not isinstance(pid, str) or not ID_RE.fullmatch(pid):
        raise Bad("id в plugin.json — латиница в нижнем регистре, цифры, «-», «_», «.»")
    if not isinstance(m.get("name"), str) or not m["name"].strip():
        raise Bad("нет имени (name) в plugin.json")
    if pid in builtin_ids():
        raise Bad(f"id «{pid}» занят встроенным плагином")
    from qp_audit import PERMISSIONS, audit
    api = m.get("api", 1)
    perms = PERMISSIONS if api == 1 else [p for p in (m.get("permissions") or []) if p in PERMISSIONS]
    files = [str(f.relative_to(d)) for f in sorted(d.rglob("*")) if f.is_file()]
    return {"id": pid, "name": m["name"], "author": str(m.get("author") or ""), "description": str(m.get("description") or ""),
            "version": str(m.get("version") or ""), "api": api, "permissions": perms,
            "unknownPermissions": [p for p in (m.get("permissions") or []) if p not in PERMISSIONS],
            "audit": audit(d), "daemon": bool(m.get("daemon")), "files": files[:50], "fileCount": len(files),
            "installed": (CFG / "plugins" / pid).exists()}


def inspect(path):
    with tempfile.TemporaryDirectory(prefix="glide-plugin-") as tmp:
        try:
            info = describe(unpack(path, Path(tmp)))
            return dict(info, ok=True, file=str(path))
        except Bad as e:
            return {"ok": False, "error": str(e), "file": str(path)}


def install(path, replace=False):
    plugins = CFG / "plugins"
    plugins.mkdir(parents=True, exist_ok=True)
    tmp = Path(tempfile.mkdtemp(prefix=".install-", dir=plugins))   # та же ФС — переезд одним rename
    try:
        d = unpack(path, tmp)
        info = describe(d)
        dest = plugins / info["id"]
        if dest.exists():
            if not replace:
                return dict(info, ok=False, error="уже установлен — заменить?", exists=True)
            bk = STATE / "plugin-backups"
            bk.mkdir(parents=True, exist_ok=True)
            shutil.move(str(dest), str(bk / f"{info['id']}-{time.strftime('%Y%m%d-%H%M%S')}"))
        d.rename(dest)
        return dict(info, ok=True, dir=str(dest))
    except Bad as e:
        return {"ok": False, "error": str(e)}
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def pack(src, out=None):
    src = Path(src).resolve()
    info = describe(src)                   # те же проверки, что у получателя
    out = Path(out or f"{info['id']}.glideplugin").resolve()
    if src in out.parents:
        raise Bad("архив нельзя класть внутрь самой папки плагина")
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
        for f in sorted(src.rglob("*")):
            rel = f.relative_to(src)
            if f.is_symlink() or any(p.startswith(".") or p == "__pycache__" for p in rel.parts):
                continue
            if f.is_file():
                z.write(f, Path(info["id"]) / rel)
    return dict(info, ok=True, out=str(out))


def downloads():
    try:
        import subprocess
        d = subprocess.run(["xdg-user-dir", "DOWNLOAD"], capture_output=True, text=True, stdin=subprocess.DEVNULL).stdout.strip()
    except OSError:
        d = ""
    out = [Path(d)] if d else []
    return out + [p for p in (Path.home() / "Загрузки", Path.home() / "Downloads") if p not in out]


def has_manifest(path):
    """Быстро, без распаковки: plugin.json в корне архива или в единственной папке."""
    try:
        if zipfile.is_zipfile(path):
            names = zipfile.ZipFile(path).namelist()
        else:
            with tarfile.open(path) as t:
                names = t.getnames()
    except (OSError, zipfile.BadZipFile, tarfile.TarError):
        return False
    return any(n.strip("/").split("/")[-1] == "plugin.json" and n.strip("/").count("/") <= 1 for n in names)


def find():
    now, seen, out = time.time(), set(), []
    for d in downloads():
        if not d.is_dir():
            continue
        for f in d.iterdir():
            if f.name.endswith((".glideplugin", ".zip", ".tar.gz", ".tgz")) and f.is_file() and f.resolve() not in seen \
                    and now - f.stat().st_mtime < 30 * 86400 and f.stat().st_size < MAX_BYTES and has_manifest(f):
                seen.add(f.resolve())
                out.append({"file": str(f), "name": f.name, "mtime": int(f.stat().st_mtime)})
    return sorted(out, key=lambda x: -x["mtime"])[:10]


def main():
    a = sys.argv[1:]
    if a and a[0] == "find":
        print(json.dumps(find(), ensure_ascii=False))
        return
    if a and a[0] in ("inspect", "install", "pack"):
        if len(a) < 2:
            sys.exit(__doc__)
        try:
            r = inspect(a[1]) if a[0] == "inspect" else install(a[1], "--replace" in a) if a[0] == "install" \
                else pack(a[1], a[2] if len(a) > 2 else None)
        except Bad as e:
            r = {"ok": False, "error": str(e)}
        print(json.dumps(r, ensure_ascii=False))
        sys.exit(0 if r.get("ok") else 1)
    if len(a) < 2 or a[0] not in ("new", "widget") or not re.fullmatch(r"[a-z0-9][a-z0-9_-]*", a[1]):
        sys.exit(__doc__ + "\nID — латиница, цифры, - и _")
    pid, name = a[1], a[2] if len(a) > 2 else a[1]
    if a[0] == "new":
        manifest = {"id": pid, "api": 2, "name": name, "icon": "󰐱", "category": "quick",
                    "qml": "Main.qml", "bar": "Bar.qml", "permissions": ["notifications"],
                    "settings": [{"key": "greeting", "type": "text", "label": "Приветствие", "default": "Привет!"},
                                 {"key": "showBar", "type": "toggle", "label": "Показывать в баре", "default": True}]}
        write(CFG / "plugins" / pid, {"plugin.json": json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
                                      "Main.qml": PLUGIN_QML.replace("__ID__", pid).replace("__NAME__", name),
                                      "Bar.qml": BAR_QML})
    else:
        manifest = {"name": name, "icon": "F0954", "description": "", "api": 2, "permissions": [],
                    "settings": [{"key": "title", "type": "text", "label": "Заголовок", "default": name}]}
        write(CFG / "widgets" / pid, {"widget.json": json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
                                      "widget.qml": WIDGET_QML})


if __name__ == "__main__":
    main()
