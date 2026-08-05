#!/usr/bin/env python3
from pathlib import Path
import sys

if len(sys.argv) != 2:
    raise SystemExit("usage: patch-webos-mouse-warp.py <scummvm-source-dir>")

path = Path(sys.argv[1]) / "backends/graphics/sdl/sdl-graphics.cpp"
text = path.read_text(encoding="utf-8")
marker = "WEBOS_DISABLE_CURSOR_WARP"

if marker in text:
    print(f"already patched: {path}")
    raise SystemExit(0)

old = (
    "void SdlGraphicsManager::setSystemMousePosition(const int x, const int y) {\n"
    "\tassert(_window);\n"
)
new = (
    "void SdlGraphicsManager::setSystemMousePosition(const int x, const int y) {\n"
    "\t// WEBOS_DISABLE_CURSOR_WARP: Magic Remote supplies absolute positions.\n"
    "\t// Warping the SDL cursor is fed back as a real motion event on webOS.\n"
    "\twarning(\"WEBOS_INPUT suppressed mouse warp x=%d y=%d\", x, y);\n"
    "\treturn;\n"
    "\tassert(_window);\n"
)

if old not in text:
    raise SystemExit(f"patch anchor not found in {path}")

path.write_text(text.replace(old, new, 1), encoding="utf-8")
print(f"patched: {path}")
