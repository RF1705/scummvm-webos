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
- webOS build: `v2026.3.0-beta1`
- ScummVM core: `v2026.3.0`

The small patch in `patches/` only tells ScummVM's cross-compile configure
step that the supported LG ARM target is little-endian. It does not add a
custom ScummVM backend.

The initial **lite** profile contains the engines most useful for classic
point-and-click adventures:

`agi`, `agos`, `drascula`, `gob`, `kyra`, `lure`, `queen`, `saga`, `sci`,
`scumm`, `sky`, `sword1`, `sword2`, `teenagent`, `tinsel`, and `touche`.

The SCUMM engine explicitly includes its v7/v8 subengine for Full Throttle,
The Dig, and The Curse of Monkey Island. CI fails the build if that subengine
is not present.

The `beta1` Adventure Plus profile also contains `cine`, `cruise`, `dreamweb`,
`groovie`, `hugo`, `made`, `mads`, `mohawk`, `parallaction`, `tony`, `toon`,
and `tucker`. Mohawk explicitly includes Myst and Riven. Riven only requires
the built-in 16-bit graphics support; it does not require the optional
JPEG/PNG or external audio codec libraries.

Optional compressed-audio and video libraries are disabled in this first
profile. Original uncompressed game data works; MP3/OGG/FLAC-compressed
variants may not. A full codec profile can be added after the first package
has been validated on real hardware.

## Build in GitHub Actions

1. Open **Actions → Build webOS IPK → Run workflow**.
2. Keep the default ScummVM ref or enter another official tag.
3. Download the resulting `scummvm-webos-…` artifact.

Every push to `main` also starts a beta build. Builds are provided only as
temporary GitHub Actions artifacts; the workflow does not create GitHub
Releases.

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

## Game launcher generator

Create individual webOS launcher apps for configured ScummVM games with the
[ScummVM webOS game launcher generator](https://rf1705.github.io/scummvm-webos/).
The generated launcher starts the central `org.scummvm.scummvm` installation
with the selected ScummVM target. The target must already exist in the shared
ScummVM configuration.

## Game data

The package contains no games. Store legally obtained game data on a location
that is already visible to the application, for example supported USB storage
or a small local test directory.

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

The native package launches successfully on an LG OLED65B19LA running webOS
6.5.3. The launcher and Magic Remote are functional. Game audio, gamepads,
suspend/resume, saves, and storage access still need broader validation.

## Legal

The build and packaging code in this repository is MIT-licensed. The fetched
ScummVM source and the resulting ScummVM binary remain GPL-3.0-or-later.
Game data is not included. Use legally obtained game files.
