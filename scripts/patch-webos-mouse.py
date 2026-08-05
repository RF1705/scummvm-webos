#!/usr/bin/env python3
from pathlib import Path
import sys

if len(sys.argv) != 2:
    raise SystemExit("usage: patch-webos-mouse.py <scummvm-source-dir>")

source_dir = Path(sys.argv[1])

path = source_dir / "backends/events/sdl/sdl2-events.cpp"
text = path.read_text(encoding="utf-8")
marker = "WEBOS_RESET_TWP_MOUSE_STATE"

if marker not in text:
    old = "\tcase SDL_MOUSEMOTION:\n\t\treturn handleMouseMotion(ev, event);\n"
    new = (
        "\tcase SDL_MOUSEMOTION: {\n"
        "\t\t// WEBOS_RESET_TWP_MOUSE_STATE: TWP can enter gameplay with SDL still\n"
        "\t\t// in a grabbed/relative mouse state. Reset it before processing the\n"
        "\t\t// first Magic Remote motion event, mirroring the state produced after\n"
        "\t\t// opening and closing ScummVM's settings dialog.\n"
        "\t\tstatic bool twpMouseStateReset = false;\n"
        "\t\tif (!twpMouseStateReset && ConfMan.get(\"engineid\") == \"twp\") {\n"
        "\t\t\tSDL_SetRelativeMouseMode(SDL_FALSE);\n"
        "\t\t\tSDL_CaptureMouse(SDL_FALSE);\n"
        "\t\t\tSDL_Window *window = SDL_GetMouseFocus();\n"
        "\t\t\tif (window)\n"
        "\t\t\t\tSDL_SetWindowGrab(window, SDL_FALSE);\n"
        "\t\t\tSDL_FlushEvent(SDL_MOUSEMOTION);\n"
        "\t\t\ttwpMouseStateReset = true;\n"
        "\t\t\treturn false;\n"
        "\t\t}\n"
        "\t\treturn handleMouseMotion(ev, event);\n"
        "\t}\n"
    )

    if old not in text:
        raise SystemExit(f"mouse state anchor not found in {path}")

    path.write_text(text.replace(old, new, 1), encoding="utf-8")
    print(f"patched: {path}")
else:
    print(f"already patched: {path}")

# Keep this change identical to patches/0004-twp-enable-subtitle-options.patch
# so it can be submitted independently to upstream ScummVM.
path = source_dir / "engines/twp/twp.h"
text = path.read_text(encoding="utf-8")
feature = "(f == kSupportsSubtitleOptions)"

if feature not in text:
    old = (
        "\t\t\t   (f == kSupportsReturnToLauncher) ||\n"
        "\t\t\t   (f == kSupportsChangingOptionsDuringRuntime);\n"
    )
    new = (
        "\t\t\t   (f == kSupportsReturnToLauncher) ||\n"
        "\t\t\t   (f == kSupportsChangingOptionsDuringRuntime) ||\n"
        "\t\t\t   (f == kSupportsSubtitleOptions);\n"
    )
    if old not in text:
        raise SystemExit(f"TWP subtitle feature anchor not found in {path}")
    path.write_text(text.replace(old, new, 1), encoding="utf-8")
    print(f"patched: {path}")
else:
    print(f"already patched: {path}")
