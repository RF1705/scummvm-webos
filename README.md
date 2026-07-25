# ScummVM for LG webOS TV

Reproducible, storage-conscious ScummVM packages for rooted LG webOS TVs.
The repository does not contain ScummVM itself or any game data. CI checks out
an official ScummVM release, cross-compiles it with the webOSbrew NDK, and
produces an installable ARM `.ipk`.

## Current target

- LG webOS TV 6.x
- 32-bit ARMv7 (`arm`)
- native SDL2 application
- package ID: `org.scummvm.scummvm`
- ScummVM: `v2026.3.0`

The initial **lite** profile contains the engines most useful for classic
point-and-click adventures:

`agi`, `agos`, `drascula`, `gob`, `kyra`, `lure`, `queen`, `saga`, `sci`,
`scumm`, `sky`, `sword1`, `sword2`, `teenagent`, `tinsel`, and `touche`.

Optional compressed-audio and video libraries are disabled in this first
profile. Original uncompressed game data works; MP3/OGG/FLAC-compressed
variants may not. A full codec profile can be added after the first package
has been validated on real hardware.

## Build in GitHub Actions

1. Open **Actions → Build webOS IPK → Run workflow**.
2. Keep the default ScummVM ref or enter another official tag.
3. Download the resulting `scummvm-webos-…` artifact.

Every push to `main` also starts a build. A repository tag beginning with `v`
creates a GitHub Release and attaches the generated `.ipk`.

The workflow uses:

- the official [ScummVM repository](https://github.com/scummvm/scummvm);
- the [webOSbrew native toolchain](https://github.com/webosbrew/native-toolchain);
- the webOSbrew SDL2 compatibility build;
- `ares-package` from the webOSbrew Rust CLI.

No SDK or compiler binary is committed to this repository.

## Install

Install the generated `.ipk` using webOS Dev Manager, `ares-install`, or the
Homebrew Channel's manual package installation.

The package is a native homebrew application and is not intended for the LG
Content Store.

## Storage strategy

The application belongs in internal app storage. Game data should live on a
USB drive:

```text
ScummVM/
  Games/
    Monkey Island/
    Day of the Tentacle/
  Saves/
```

webOS normally mounts USB volumes below paths such as
`/tmp/usb/sda/sda1`. Native applications run inside a jail, so a rooted TV
may need a bind mount before the files become visible inside ScummVM. See
[docs/storage.md](docs/storage.md).

Savegames and configuration are small and can remain in the application's
internal home directory.

## Local build

CI is the supported build environment. For local builds, install the
webOSbrew NDK and `ares-package`, source the NDK's `environment-setup`, then
run:

```sh
SCUMMVM_SOURCE_DIR=/path/to/scummvm bash scripts/build-webos.sh
bash scripts/package-webos.sh
```

## Project status

Early hardware-validation stage. The CI package still needs to be tested for
launch, audio, Magic Remote input, gamepad input, suspend/resume, saves, and
USB visibility on an LG OLED65B19LA running webOS 6.5.3.

## Legal

The build and packaging code in this repository is MIT-licensed. The fetched
ScummVM source and the resulting ScummVM binary remain GPL-3.0-or-later.
Game data is not included. Use legally obtained game files.
