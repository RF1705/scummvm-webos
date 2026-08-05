#!/usr/bin/env python3
from pathlib import Path
import sys

if len(sys.argv) != 2:
    raise SystemExit("usage: patch-webos-mouse.py <scummvm-source-dir>")

path = Path(sys.argv[1]) / "backends/events/sdl/sdl2-events.cpp"
text = path.read_text(encoding="utf-8")
marker = "WEBOS_RESET_MOUSE_STATE"

if marker in text:
    print(f"already patched: {path}")
    raise SystemExit(0)

old = (
    "\t} else if (ev.type == SDL_MOUSEMOTION) {\n"
    "\t\twarning(\"WEBOS_INPUT mouse x=%d y=%d xrel=%d yrel=%d which=%u\",\n"
    "\t\t        ev.motion.x, ev.motion.y, ev.motion.xrel, ev.motion.yrel,\n"
    "\t\t        (unsigned int)ev.motion.which);\n"
    "\t}\n"
)

new = (
    "\t} else if (ev.type == SDL_MOUSEMOTION) {\n"
    "\t\twarning(\"WEBOS_INPUT mouse x=%d y=%d xrel=%d yrel=%d which=%u\",\n"
    "\t\t        ev.motion.x, ev.motion.y, ev.motion.xrel, ev.motion.yrel,\n"
    "\t\t        (unsigned int)ev.motion.which);\n"
    "\n"
    "\t\t// WEBOS_RESET_MOUSE_STATE: TWP can enter gameplay with SDL still in\n"
    "\t\t// a grabbed/relative mouse state. Opening and closing ScummVM's\n"
    "\t\t// settings dialog resets that state, so reproduce the same reset once\n"
    "\t\t// when the first characteristic synthetic warp event is observed.\n"
    "\t\tstatic bool mouseStateReset = false;\n"
    "\t\tif (!mouseStateReset && ev.motion.x == 0 && ev.motion.y == 0 &&\n"
    "\t\t        (ev.motion.xrel < -200 || ev.motion.xrel > 200 ||\n"
    "\t\t         ev.motion.yrel < -120 || ev.motion.yrel > 120)) {\n"
    "\t\t\tSDL_SetRelativeMouseMode(SDL_FALSE);\n"
    "\t\t\tSDL_CaptureMouse(SDL_FALSE);\n"
    "\t\t\tSDL_Window *window = SDL_GetMouseFocus();\n"
    "\t\t\tif (window)\n"
    "\t\t\t\tSDL_SetWindowGrab(window, SDL_FALSE);\n"
    "\t\t\tSDL_FlushEvent(SDL_MOUSEMOTION);\n"
    "\t\t\tmouseStateReset = true;\n"
    "\t\t\twarning(\"WEBOS_INPUT reset SDL mouse state\");\n"
    "\t\t\treturn false;\n"
    "\t\t}\n"
    "\t}\n"
)

if old not in text:
    raise SystemExit(f"mouse state anchor not found in {path}")

path.write_text(text.replace(old, new, 1), encoding="utf-8")
print(f"patched: {path}")
