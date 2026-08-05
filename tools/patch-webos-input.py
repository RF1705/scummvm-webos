#!/usr/bin/env python3
from pathlib import Path
import sys

if len(sys.argv) != 2:
    raise SystemExit(f"usage: {sys.argv[0]} SCUMMVM_SOURCE_DIR")

source = Path(sys.argv[1])
events = source / "backends/events/sdl/sdl2-events.cpp"
graphics = source / "backends/graphics/sdl/sdl-graphics.cpp"

text = events.read_text()
marker = "LG webOS colour keys"
if marker not in text:
    needle = "Common::KeyCode SdlEventSource::SDLToOSystemKeycode(const SDL_Keycode key) {\n\tswitch (key) {\n"
    replacement = needle + """\
\t// LG webOS colour keys. SDL 2 has no named keycodes for these TV\n
\t// buttons, so expose them as F13-F16 for ScummVM's keymapper.\n
\tcase static_cast<SDL_Keycode>(0x18e):\n
\tcase static_cast<SDL_Keycode>(0x1008ffa3): return Common::KEYCODE_F13;\n
\tcase static_cast<SDL_Keycode>(0x18f):\n
\tcase static_cast<SDL_Keycode>(0x1008ffa4): return Common::KEYCODE_F14;\n
\tcase static_cast<SDL_Keycode>(0x190):\n
\tcase static_cast<SDL_Keycode>(0x1008ffa5): return Common::KEYCODE_F15;\n
\tcase static_cast<SDL_Keycode>(0x191):\n
\tcase static_cast<SDL_Keycode>(0x1008ffa6): return Common::KEYCODE_F16;\n
\n
"""
    if needle not in text:
        raise SystemExit(f"keycode insertion point not found in {events}")
    events.write_text(text.replace(needle, replacement, 1))

text = graphics.read_text()
marker = "Keep the physical Magic Remote position authoritative for TWP"
if marker not in text:
    needle = "void SdlGraphicsManager::setSystemMousePosition(const int x, const int y) {\n\tassert(_window);\n"
    replacement = """void SdlGraphicsManager::setSystemMousePosition(const int x, const int y) {
\t// The LG Magic Remote supplies absolute pointer coordinates. TWP may
\t// request cursor warps for controller navigation; on webOS these can be
\t// fed back as real pointer events and pull the cursor to the top-left.
\t// Keep the physical Magic Remote position authoritative for TWP.
\tif (ConfMan.hasKey("engineid") && ConfMan.get("engineid") == "twp")
\t\treturn;

\tassert(_window);
"""
    if needle not in text:
        raise SystemExit(f"mouse-warp insertion point not found in {graphics}")
    graphics.write_text(text.replace(needle, replacement, 1))
