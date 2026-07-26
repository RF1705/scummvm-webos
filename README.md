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
- webOS package: `2026.3.1`
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

The application belongs in internal app storage. Game data should preferably
live on a read-only network share. The tested webOS 6.5.3 TV kernel supports
NFS 3 and NFS 4 natively. For FRITZ!NAS and other SMB-only servers, CI also
builds a reduced ARMv7 rclone-over-FUSE helper; no LG kernel modification is
required.

```text
ScummVM/
  Games/
    Monkey Island/
    Day of the Tentacle/
  Saves/
```

The repository includes a persistent webOSbrew NFS mount helper. USB remains
available as an alternative. Native applications run inside a jail, so both
approaches need an additional bind mount before files become visible inside
ScummVM. See [docs/storage.md](docs/storage.md).

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
suspend/resume, saves, and network storage still need broader validation.

## Legal

The build and packaging code in this repository is MIT-licensed. The fetched
ScummVM source and the resulting ScummVM binary remain GPL-3.0-or-later.
Game data is not included. Use legally obtained game files.
