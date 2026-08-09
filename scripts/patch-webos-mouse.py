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

# SDL-webOS exposes the physical LG Back button through its dedicated scancode.
# Convert it to Escape at ScummVM's common SDL keycode boundary so both key-down
# and key-up events use the normal ScummVM back/cancel path in every engine.
path = source_dir / "backends/events/sdl/sdl2-events.cpp"
text = path.read_text(encoding="utf-8")
marker = "WEBOS_BACK_TO_ESCAPE"

if marker not in text:
    old = (
        "SDL_Keycode SdlEventSource::obtainKeycode(const SDL_Keysym keySym) {\n"
        "\treturn keySym.sym;\n"
        "}\n"
    )
    new = (
        "SDL_Keycode SdlEventSource::obtainKeycode(const SDL_Keysym keySym) {\n"
        "\t// WEBOS_BACK_TO_ESCAPE: SDL-webOS assigns scancode 482 to the native\n"
        "\t// LG Back button. Use the numeric value to avoid depending on the\n"
        "\t// SDL-webOS-specific enum name in the SDK headers used for this build.\n"
        "\tif (static_cast<int>(keySym.scancode) == 482)\n"
        "\t\treturn SDLK_ESCAPE;\n"
        "\treturn keySym.sym;\n"
        "}\n"
    )
    if old not in text:
        raise SystemExit(f"Back key anchor not found in {path}")
    path.write_text(text.replace(old, new, 1), encoding="utf-8")
    print(f"patched: {path}")
else:
    print(f"already patched: {path}")

# TV-friendly defaults: Back is translated to Escape above, so make Escape open
# ScummVM's game menu rather than skipping. Leave Skip unbound by default and
# expose the remote/keyboard cursor keys as the default directional bindings.
path = source_dir / "engines/metaengine.cpp"
text = path.read_text(encoding="utf-8")
marker = "WEBOS_TV_DEFAULT_KEYMAP"

if marker not in text:
    old = (
        "\tact = new Action(kStandardActionOpenMainMenu, _(\"Game menu\"));\n"
        "\tact->setKeyEvent(KeyState(KEYCODE_F5, ASCII_F5));\n"
        "\tact->addDefaultInputMapping(\"F5\");\n"
        "\tact->addDefaultInputMapping(\"JOY_LEFT_SHOULDER\");\n"
        "\tact->allowKbdRepeats();\n"
        "\tengineKeyMap->addAction(act);\n"
        "\n"
        "\tact = new Action(kStandardActionSkip, _(\"Skip\"));\n"
        "\tact->setKeyEvent(KeyState(KEYCODE_ESCAPE, ASCII_ESCAPE));\n"
        "\tact->addDefaultInputMapping(\"ESCAPE\");\n"
        "\tact->addDefaultInputMapping(\"JOY_Y\");\n"
        "\tact->allowKbdRepeats();\n"
        "\tengineKeyMap->addAction(act);\n"
        "\n"
        "\tact = new Action(\"SKLI\", _(\"Skip line\"));\n"
        "\tact->setKeyEvent(KeyState(KEYCODE_PERIOD, '.'));\n"
        "\tact->addDefaultInputMapping(\"PERIOD\");\n"
        "\tact->addDefaultInputMapping(\"JOY_X\");\n"
        "\tact->allowKbdRepeats();\n"
        "\tengineKeyMap->addAction(act);\n"
        "\n"
        "\tact = new Action(\"PIND\", _(\"Predictive input dialog\"));\n"
        "\tact->setEvent(EVENT_PREDICTIVE_DIALOG);\n"
        "\tact->allowKbdRepeats();\n"
        "\tengineKeyMap->addAction(act);\n"
        "\n"
        "\tact = new Action(\"RETURN\", _(\"Confirm\"));\n"
        "\tact->setKeyEvent(KeyState(KEYCODE_RETURN, ASCII_RETURN));\n"
        "\tact->addDefaultInputMapping(\"RETURN\");\n"
        "\tact->allowKbdRepeats();\n"
        "\tengineKeyMap->addAction(act);\n"
        "\n"
        "\tact = new Action(kStandardActionMoveUp, _(\"Up\"));\n"
        "\tact->setKeyEvent(KEYCODE_KP8);\n"
        "\tact->addDefaultInputMapping(\"JOY_UP\");\n"
        "\tact->allowKbdRepeats();\n"
        "\tengineKeyMap->addAction(act);\n"
        "\n"
        "\tact = new Action(kStandardActionMoveDown, _(\"Down\"));\n"
        "\tact->setKeyEvent(KEYCODE_KP2);\n"
        "\tact->addDefaultInputMapping(\"JOY_DOWN\");\n"
        "\tact->allowKbdRepeats();\n"
        "\tengineKeyMap->addAction(act);\n"
        "\n"
        "\tact = new Action(kStandardActionMoveLeft, _(\"Left\"));\n"
        "\tact->setKeyEvent(KEYCODE_KP4);\n"
        "\tact->addDefaultInputMapping(\"JOY_LEFT\");\n"
        "\tact->allowKbdRepeats();\n"
        "\tengineKeyMap->addAction(act);\n"
        "\n"
        "\tact = new Action(kStandardActionMoveRight, _(\"Right\"));\n"
        "\tact->setKeyEvent(KEYCODE_KP6);\n"
        "\tact->addDefaultInputMapping(\"JOY_RIGHT\");\n"
        "\tact->allowKbdRepeats();\n"
        "\tengineKeyMap->addAction(act);\n"
    )
    new = (
        "\t// WEBOS_TV_DEFAULT_KEYMAP: use the TV Back/Escape key for the game\n"
        "\t// menu, keep Skip unbound, and bind the four cursor keys by default.\n"
        "\tact = new Action(kStandardActionOpenMainMenu, _(\"Game menu\"));\n"
        "\tact->setKeyEvent(KeyState(KEYCODE_F5, ASCII_F5));\n"
        "\tact->addDefaultInputMapping(\"F5\");\n"
        "\tact->addDefaultInputMapping(\"ESCAPE\");\n"
        "\tact->addDefaultInputMapping(\"JOY_LEFT_SHOULDER\");\n"
        "\tact->allowKbdRepeats();\n"
        "\tengineKeyMap->addAction(act);\n"
        "\n"
        "\tact = new Action(kStandardActionSkip, _(\"Skip\"));\n"
        "\tact->setKeyEvent(KeyState(KEYCODE_ESCAPE, ASCII_ESCAPE));\n"
        "\tact->allowKbdRepeats();\n"
        "\tengineKeyMap->addAction(act);\n"
        "\n"
        "\tact = new Action(\"SKLI\", _(\"Skip line\"));\n"
        "\tact->setKeyEvent(KeyState(KEYCODE_PERIOD, '.'));\n"
        "\tact->addDefaultInputMapping(\"PERIOD\");\n"
        "\tact->addDefaultInputMapping(\"JOY_X\");\n"
        "\tact->allowKbdRepeats();\n"
        "\tengineKeyMap->addAction(act);\n"
        "\n"
        "\tact = new Action(\"PIND\", _(\"Predictive input dialog\"));\n"
        "\tact->setEvent(EVENT_PREDICTIVE_DIALOG);\n"
        "\tact->allowKbdRepeats();\n"
        "\tengineKeyMap->addAction(act);\n"
        "\n"
        "\tact = new Action(\"RETURN\", _(\"Confirm\"));\n"
        "\tact->setKeyEvent(KeyState(KEYCODE_RETURN, ASCII_RETURN));\n"
        "\tact->addDefaultInputMapping(\"RETURN\");\n"
        "\tact->allowKbdRepeats();\n"
        "\tengineKeyMap->addAction(act);\n"
        "\n"
        "\tact = new Action(kStandardActionMoveUp, _(\"Up\"));\n"
        "\tact->setKeyEvent(KEYCODE_KP8);\n"
        "\tact->addDefaultInputMapping(\"UP\");\n"
        "\tact->addDefaultInputMapping(\"JOY_UP\");\n"
        "\tact->allowKbdRepeats();\n"
        "\tengineKeyMap->addAction(act);\n"
        "\n"
        "\tact = new Action(kStandardActionMoveDown, _(\"Down\"));\n"
        "\tact->setKeyEvent(KEYCODE_KP2);\n"
        "\tact->addDefaultInputMapping(\"DOWN\");\n"
        "\tact->addDefaultInputMapping(\"JOY_DOWN\");\n"
        "\tact->allowKbdRepeats();\n"
        "\tengineKeyMap->addAction(act);\n"
        "\n"
        "\tact = new Action(kStandardActionMoveLeft, _(\"Left\"));\n"
        "\tact->setKeyEvent(KEYCODE_KP4);\n"
        "\tact->addDefaultInputMapping(\"LEFT\");\n"
        "\tact->addDefaultInputMapping(\"JOY_LEFT\");\n"
        "\tact->allowKbdRepeats();\n"
        "\tengineKeyMap->addAction(act);\n"
        "\n"
        "\tact = new Action(kStandardActionMoveRight, _(\"Right\"));\n"
        "\tact->setKeyEvent(KEYCODE_KP6);\n"
        "\tact->addDefaultInputMapping(\"RIGHT\");\n"
        "\tact->addDefaultInputMapping(\"JOY_RIGHT\");\n"
        "\tact->allowKbdRepeats();\n"
        "\tengineKeyMap->addAction(act);\n"
    )
    if old not in text:
        raise SystemExit(f"default keymap anchor not found in {path}")
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
