"""tools/glide-ocr.py на заглушках slurp / grim / tesseract: выделение, отмена, нет программ, подготовка картинки."""
import json
import os
import sys
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TOOL = ROOT / "tools" / "glide-ocr.py"

GRIM = """#!/usr/bin/env python3
import sys
from PIL import Image
Image.new("L", (60, 20), 20).save(sys.argv[-1])   # тёмная картинка 60×20
open(sys.argv[0] + ".log", "a").write(" ".join(sys.argv[1:]) + "\\n")
"""
TESSERACT = """#!/usr/bin/env python3
import sys
from PIL import Image, ImageStat
if sys.argv[1] == "--list-langs":
    print('List of available languages in "/usr/share/tessdata/" (3):'); print("eng"); print("osd"); print("rus"); sys.exit(0)
im = Image.open(sys.argv[1])
print(f"\\n  {im.size[0]}x{im.size[1]} {'light' if ImageStat.Stat(im).mean[0] > 128 else 'dark'} {sys.argv[sys.argv.index('-l') + 1]}\\n\\n\\f")
"""


class Ocr(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix="glide-ocr-test-"))
        self.bin = self.tmp / "bin"
        self.bin.mkdir()
        self.shim("grim", GRIM)
        self.shim("tesseract", TESSERACT)
        self.shim("slurp", "#!/bin/sh\necho '10,20 60x20'\n")

    def tearDown(self):
        import shutil
        shutil.rmtree(self.tmp, ignore_errors=True)

    def shim(self, name, body):
        p = self.bin / name
        p.write_text(body)
        p.chmod(0o755)

    def run_tool(self, *args, path=None):
        env = dict(os.environ, PATH=path or f"{self.bin}:/usr/bin")
        r = subprocess.run([sys.executable, "-I", str(TOOL), *args], env=env, capture_output=True, text=True,
                           stdin=subprocess.DEVNULL, timeout=30)
        return json.loads(r.stdout)

    def test_region(self):
        r = self.run_tool()
        self.assertEqual(r, {"ok": True, "text": "120x40 light rus+eng", "langs": "rus+eng"})   # ×2, обращена, края обрезаны
        self.assertIn("-g 10,20 60x20", (self.bin / "grim.log").read_text())

    def test_cancel(self):
        self.shim("slurp", "#!/bin/sh\nexit 1\n")
        self.assertEqual(self.run_tool(), {"ok": False, "cancelled": True})

    def test_geometry_skips_slurp(self):
        self.shim("slurp", "#!/bin/sh\nexit 1\n")
        self.assertTrue(self.run_tool("--geometry", "0,0 60x20")["ok"])

    def test_missing(self):
        (self.bin / "tesseract").unlink()
        (self.bin / "grim").unlink()
        empty = self.tmp / "empty"
        empty.mkdir()
        (empty / "slurp").symlink_to(self.bin / "slurp")
        r = self.run_tool(path=str(empty))
        self.assertFalse(r["ok"])
        self.assertEqual(r["missing"], ["tesseract", "grim"])
        self.assertIn("tesseract-data-rus", r["install"])

    def test_no_langs(self):
        self.shim("tesseract", "#!/bin/sh\necho 'List of available languages (1):'; echo osd\n")
        self.assertEqual(self.run_tool()["missing"], ["tesseract-data-rus"])


if __name__ == "__main__":
    unittest.main()
