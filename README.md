# ScummVM for LG webOS TV

Reproducible, storage-conscious ScummVM packages for LG webOS TVs in Developer
Mode. Root access is not required for ScummVM itself.
The repository does not contain ScummVM itself or any game data. CI checks out
an official ScummVM release, cross-compiles it with the webOSbrew NDK, and
produces an installable ARM `.ipk`.

## Current target

- LG webOS TV 6.x
- 32-bit ARMv7 (`arm`)
- native SDL2 application
- package ID: `org.scummvm.scummvm`
- webOS release: `scummvm_2026.3.0_webos_1.2.0`
- ScummVM core: `v2026.3.0`
- OpenGL ES 2 renderer enabled

The application can be installed and used through LG Developer Mode. Root is
only needed for separate system-level tools such as bind-mounting network
storage into an application jail; it is not a requirement of this package.

The small patches in `patches/` handle the webOS ARM target, ignore native
webOS launch metadata, and translate SDL application lifecycle events into a
clean ScummVM suspend/resume sequence. They do not add a custom ScummVM
backend.

The initial **lite** profile contains the engines most useful for classic
point-and-click adventures:

`agi`, `agos`, `drascula`, `gob`, `kyra`, `lure`, `queen`, `saga`, `sci`,
`scumm`, `sky`, `sword1`, `sword2`, `teenagent`, `tinsel`, and `touche`.

The SCUMM engine explicitly includes its v7/v8 subengine for Full Throttle,
The Dig, and The Curse of Monkey Island. CI fails the build if that subengine
is not present.

The webOS 1.2.x Adventure Plus profile also contains `cine`, `cruise`,
`dreamweb`, `groovie`, `hugo`, `made`, `mads`, `mohawk`,
`parallaction`, `tony`, `toon`, `tucker`, `bladerunner`,
`director`, `twp`, and `zvision`.

Mohawk explicitly includes Myst and Riven.

The codec profile builds and statically links the following libraries for the
webOS ARM soft-float ABI:

- Ogg and Vorbis for OGG-compressed audio;
- libmad for MP3-compressed audio;
- FLAC for lossless compressed audio;
- libmpeg2 for MPEG-1 and MPEG-2 video;
- libtheoradec for Theora video.

Static linking keeps the package self-contained and avoids depending on codec
libraries installed by a particular TV firmware. VP8/VP9 through libvpx and
AAC through libfaad remain disabled for now.

## Graphics

The webOS build now includes OpenGL ES 2 support. This enables hardware-
accelerated rendering for engines that require OpenGL, including
Thimbleweed Park.

## Validation status

The following functions have been tested on an LG OLED65B19LA running webOS
6.5.3:

| Function | Validation |
| --- | --- |
| Native application startup | Tested on TV |
| Magic Remote | Tested on TV |
| Magic Remote remote keys (Red/Green/Yellow/Blue, Channel ±) | Tested on TV |
| Thimbleweed Park | Tested on TV |
| Thimbleweed Park subtitle/audio options | Tested on TV |
| OpenGL ES 2 renderer | Tested on TV |
| OGG/Vorbis CD audio | Tested with Monkey Island |
| FLAC decoding | Tested on TV |
| MT-32 emulator | Tested with Sam & Max and MT-32 ROM files |
| MP3/libmad | Real sample decoded by the ARM target library in CI/QEMU |
| MPEG-2/libmpeg2 | Real video frame decoded by the ARM target library in CI/QEMU |
| Theora/libtheoradec | Real video frame decoded by the ARM target library in CI/QEMU |
| Suspend/resume | Tested on TV |
| Gamepads | Not yet validated |

The CI checks `USE_MT32EMU`, all enabled codec defines, and the presence of the
static target libraries. It additionally creates fresh MP3, MPEG-2 and Theora
samples, cross-compiles a decoder smoke test against those exact ARM
libraries, and runs it under QEMU. This verifies actual decoding rather than
only checking configure output. Full playback through individual ScummVM game
engines should still be tested on hardware as suitable games become available.

## Suspend and resume

When webOS moves the application to the background, the SDL lifecycle patch:

- flushes the ScummVM configuration to disk;
- pauses SDL audio;
- emits a focus-lost event and allows the screen saver.

When the application returns, it resumes audio, refreshes the video surface,
and emits a focus-gained event. A webOS termination event also flushes the
configuration before requesting a clean exit.

The webOS build also restores the SDL mouse state when required. This ensures
that games such as Thimbleweed Park immediately use the LG Magic Remote after
startup without requiring additional user interaction.

## Build in GitHub Actions

1. Open **Actions → Build webOS IPK → Run workflow**.
2. Keep the default ScummVM ref or enter another official tag.
3. Download the resulting `scummvm-webos-…` artifact.

Every push to `main` also starts a validation build. Pushing a release tag that
matches `scummvm_*_webos_*` builds the IPK from scratch, verifies its runtime
data and shared libraries, generates the Homebrew Channel manifest, and
publishes all three files as GitHub Release assets.

The workflow uses:

- the official [ScummVM repository](https://github.com/scummvm/scummvm);
- the [webOSbrew native toolchain](https://github.com/webosbrew/native-toolchain);
- the webOSbrew SDL2 compatibility build;
- pinned upstream codec source releases;
- FFmpeg-generated smoke-test media and QEMU target execution;
- `ares-package` from the webOSbrew Rust CLI.

No SDK, compiler binary, codec binary, test media, or game data is committed to
this repository.

## Install

Install the generated `.ipk` using webOS Dev Manager, `ares-install`, or the
Homebrew Channel's manual package installation. LG Developer Mode is
sufficient.

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

A separate rooted network-storage helper may expose SMB or NFS mounts to the
application jail. That helper's root requirement does not apply to ScummVM or
to local and USB game data.

Thimbleweed Park is fully supported by the Adventure Plus profile. The game can
be started directly from its original data files without any modification.

## Local build

CI is the supported build environment. For local builds, install the
webOSbrew NDK, the autotools build dependencies, FFmpeg, QEMU user-mode
emulation, and `ares-package`. Source the NDK's `environment-setup`, then run:

```sh
export CODEC_PREFIX=/tmp/scummvm-webos-codecs

CODEC_SOURCE_DIR=/tmp/scummvm-webos-codec-sources \
  bash scripts/build-codecs.sh

CODEC_PREFIX="$CODEC_PREFIX" \
  bash tests/test-codecs.sh

SCUMMVM_SOURCE_DIR=/path/to/scummvm \
  CODEC_PREFIX="$CODEC_PREFIX" \
  bash scripts/build-webos.sh

bash scripts/package-webos.sh
```

The codec build directory can be reused until the toolchain or
`scripts/build-codecs.sh` changes.

## Project status

The application has been validated on real LG webOS hardware.

The current build supports OpenGL ES 2 rendering, the LG Magic Remote,
suspend/resume handling, OGG/Vorbis, FLAC, MP3, MPEG-2, Theora and MT-32
emulation. Thimbleweed Park has been successfully tested on a real TV,
including subtitle/audio settings, Magic Remote support and native gameplay.

The webOS build additionally exposes the coloured remote buttons (Red, Green,
Yellow and Blue) as assignable ScummVM function keys (F13–F16) together with
Channel Up/Down (F17/F18), allowing users to bind them through the standard
ScummVM keymapper.

Further validation across additional TV models and games is still encouraged.

##Additional webOS-specific improvements include:

- OpenGL ES 2 renderer support
- native application lifecycle integration
- Magic Remote compatibility improvements
- assignable coloured remote buttons
- assignable Channel Up/Down keys
- Thimbleweed Park subtitle/audio options exposed through the standard ScummVM GUI

## Legal

The build and packaging code in this repository is MIT-licensed. The fetched
ScummVM source and the resulting ScummVM binary remain GPL-3.0-or-later.
Third-party codec libraries retain their respective upstream licenses. Game
data and MT-32 ROM images are not included. Use legally obtained files.
