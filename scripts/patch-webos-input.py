#!/usr/bin/env python3
from pathlib import Path
import sys

if len(sys.argv) != 2:
    raise SystemExit("usage: patch-webos-input.py <scummvm-source-dir>")

root = Path(sys.argv[1])
events = root / "backends/events/sdl/sdl2-events.cpp"
graphics = root / "backends/graphics/sdl/sdl-graphics.cpp"


def replace_once(path: Path, old: str, new: str, marker: str) -> None:
    text = path.read_text(encoding="utf-8")
    if marker in text:
        print(f"already patched: {path}")
        return
    if old not in text:
        raise SystemExit(f"patch anchor not found in {path}: {old[:80]!r}")
    path.write_text(text.replace(old, new, 1), encoding="utf-8")
    print(f"patched: {path}")


replace_once(
    events,
    "Common::KeyCode SdlEventSource::SDLToOSystemKeycode(const SDL_Keycode key) {\n\tswitch (key) {\n",
    "Common::KeyCode SdlEventSource::SDLToOSystemKeycode(const SDL_Keycode key) {\n\tswitch (key) {\n"
    "\t// WEBOS_REMOTE_COLOUR_KEYS: expose LG colour buttons as F13-F16.\n"
    "\tcase static_cast<SDL_Keycode>(0x18e):\n"
    "\tcase static_cast<SDL_Keycode>(0x1008ffa3): return Common::KEYCODE_F13;\n"
    "\tcase static_cast<SDL_Keycode>(0x18f):\n"
    "\tcase static_cast<SDL_Keycode>(0x1008ffa4): return Common::KEYCODE_F14;\n"
    "\tcase static_cast<SDL_Keycode>(0x190):\n"
    "\tcase static_cast<SDL_Keycode>(0x1008ffa5): return Common::KEYCODE_F15;\n"
    "\tcase static_cast<SDL_Keycode>(0x191):\n"
    "\tcase static_cast<SDL_Keycode>(0x1008ffa6): return Common::KEYCODE_F16;\n",
    "WEBOS_REMOTE_COLOUR_KEYS",
)

replace_once(
    events,
    "bool SdlEventSource::dispatchSDLEvent(SDL_Event &ev, Common::Event &event) {\n\tswitch (ev.type) {\n",
    "bool SdlEventSource::dispatchSDLEvent(SDL_Event &ev, Common::Event &event) {\n"
    "\t// WEBOS_INPUT_TRACE: record the raw SDL values delivered by webOS.\n"
    "\tif (ev.type == SDL_KEYDOWN || ev.type == SDL_KEYUP) {\n"
    "\t\twarning(\"WEBOS_INPUT key type=%u sym=0x%x scancode=%d repeat=%d\",\n"
    "\t\t        ev.type, (unsigned int)ev.key.keysym.sym,\n"
    "\t\t        (int)ev.key.keysym.scancode, (int)ev.key.repeat);\n"
    "\t} else if (ev.type == SDL_MOUSEMOTION) {\n"
    "\t\twarning(\"WEBOS_INPUT mouse x=%d y=%d xrel=%d yrel=%d which=%u\",\n"
    "\t\t        ev.motion.x, ev.motion.y, ev.motion.xrel, ev.motion.yrel,\n"
    "\t\t        (unsigned int)ev.motion.which);\n"
    "\t}\n"
    "\tswitch (ev.type) {\n",
    "WEBOS_INPUT_TRACE",
)

replace_once(
    graphics,
    "void SdlGraphicsManager::setSystemMousePosition(const int x, const int y) {\n\tassert(_window);\n",
    "void SdlGraphicsManager::setSystemMousePosition(const int x, const int y) {\n"
    "\t// WEBOS_TWP_NO_MOUSE_WARP: Magic Remote reports absolute coordinates.\n"
    "\tif (ConfMan.hasKey(\"engineid\") && ConfMan.get(\"engineid\") == \"twp\") {\n"
    "\t\twarning(\"WEBOS_INPUT suppressed TWP mouse warp x=%d y=%d\", x, y);\n"
    "\t\treturn;\n"
    "\t}\n"
    "\tassert(_window);\n",
    "WEBOS_TWP_NO_MOUSE_WARP",
)
