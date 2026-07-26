#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source_dir="${SCUMMVM_SOURCE_DIR:-$repo_root/upstream}"
build_dir="${BUILD_DIR:-$repo_root/build}"
cross_patch="$repo_root/patches/0001-configure-webos-arm-little-endian.patch"
launch_patch="$repo_root/patches/0002-ignore-webos-launch-parameters.patch"

if [[ ! -x "$source_dir/configure" ]]; then
  echo "ScummVM source not found at $source_dir" >&2
  exit 1
fi

if [[ -z "${CC:-}" || -z "${CXX:-}" || -z "${STAGING_DIR:-}" ]]; then
  echo "Source the webOS NDK environment-setup file before building." >&2
  exit 1
fi

case "$("$CC" -dumpmachine)" in
  arm-webos-linux-gnueabi | arm-buildroot-linux-gnueabi)
    ;;
  *)
    echo "Unexpected compiler target: $("$CC" -dumpmachine)" >&2
    exit 1
    ;;
esac

if ! grep -q "All supported 32-bit LG webOS TV targets" "$source_dir/configure"; then
  patch --directory="$source_dir" --strip=1 < "$cross_patch"
fi
if ! grep -q "LG webOS passes native lifecycle information" \
  "$source_dir/base/commandLine.cpp"; then
  patch --directory="$source_dir" --strip=1 < "$launch_patch"
fi

engines=(
  agi
  agos
  drascula
  gob
  kyra
  lure
  queen
  saga
  sci
  scumm
  sky
  sword1
  sword2
  teenagent
  tinsel
  touche
)

engine_list="$(IFS=,; echo "${engines[*]}")"

rm -rf "$build_dir"
mkdir -p "$build_dir"
cd "$build_dir"

export PKG_CONFIG_ALLOW_CROSS=1
export PKG_CONFIG_SYSROOT_DIR="$STAGING_DIR"
mapfile -t pkgconfig_dirs < <(find "$STAGING_DIR" -type d -name pkgconfig -print)
if (( ${#pkgconfig_dirs[@]} == 0 )); then
  echo "No target pkg-config directories found below $STAGING_DIR" >&2
  exit 1
fi
export PKG_CONFIG_LIBDIR="$(IFS=:; echo "${pkgconfig_dirs[*]}")"
unset PKG_CONFIG_PATH

if ! pkg-config --exists sdl2; then
  echo "SDL2 metadata was not found in the webOS NDK." >&2
  echo "PKG_CONFIG_LIBDIR=$PKG_CONFIG_LIBDIR" >&2
  exit 1
fi

echo "Using SDL2 $(pkg-config --modversion sdl2)"
export PATH="$repo_root/tools:$PATH"
export SDL_CONFIG=sdl2-config-webos
export CXXFLAGS="${CXXFLAGS:-} -Os -ffunction-sections -fdata-sections -mcpu=cortex-a9 -mfloat-abi=softfp -mfpu=neon"
# The value passes through both make and the shell before reaching the linker:
# $$ survives make, while the single quotes keep the shell from expanding it.
export LDFLAGS="${LDFLAGS:-} -Wl,--gc-sections -Wl,-rpath,'\$\$ORIGIN/lib'"

"$source_dir/configure" \
  --host=arm-webos-linux-gnueabi \
  --backend=sdl \
  --enable-release \
  --disable-debug \
  --disable-Werror \
  --disable-all-engines \
  --enable-engine="$engine_list" \
  --disable-detection-full \
  --enable-ext-neon \
  --enable-vkeybd \
  --disable-taskbar \
  --disable-cloud \
  --disable-eventrecorder \
  --disable-updates \
  --disable-tts \
  --disable-system-dialogs \
  --disable-mt32emu \
  --disable-alsa \
  --disable-seq-midi \
  --disable-timidity \
  --disable-fluidsynth \
  --disable-fluidlite \
  --disable-sonivox \
  --disable-libcurl \
  --disable-sdlnet \
  --disable-enet \
  --disable-discord \
  --disable-ogg \
  --disable-vorbis \
  --disable-tremor \
  --disable-mad \
  --disable-flac \
  --disable-mpeg2 \
  --disable-theoradec \
  --disable-vpx \
  --disable-faad \
  --disable-freetype2 \
  --disable-jpeg \
  --disable-png \
  --disable-gif \
  --opengl-mode=none \
  --disable-opengl-game \
  --disable-tinygl

make -j"${JOBS:-$(getconf _NPROCESSORS_ONLN)}" scummvm

"${STRIP:-strip}" "$build_dir/scummvm"
file "$build_dir/scummvm"
"${READELF:-readelf}" -d "$build_dir/scummvm" | grep NEEDED || true
du -h "$build_dir/scummvm"
