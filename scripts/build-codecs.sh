#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source_root="${CODEC_SOURCE_DIR:-$repo_root/build/codec-sources}"
prefix="${CODEC_PREFIX:-$repo_root/build/codecs}"
jobs="${JOBS:-$(getconf _NPROCESSORS_ONLN)}"

if [[ -z "${CC:-}" || -z "${AR:-}" || -z "${RANLIB:-}" || -z "${STAGING_DIR:-}" ]]; then
  echo "Source the webOS NDK environment-setup file before building codecs." >&2
  exit 1
fi

for command in curl sha256sum tar make pkg-config autoreconf; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "Required build command not found: $command" >&2
    exit 1
  fi
done

case "$("$CC" -dumpmachine)" in
  arm-webos-linux-gnueabi | arm-buildroot-linux-gnueabi)
    host_triplet=arm-linux-gnueabi
    ;;
  *)
    echo "Unexpected compiler target: $("$CC" -dumpmachine)" >&2
    exit 1
    ;;
esac

download_dir="$source_root/downloads"
build_root="$source_root/build"
mkdir -p "$download_dir" "$build_root" "$prefix"

download() {
  local url="$1"
  local destination="$2"
  local sha256="$3"

  if [[ ! -f "$destination" ]]; then
    curl --fail --location --retry 3 --retry-delay 2 \
      "$url" --output "$destination"
  fi

  if [[ -n "$sha256" ]]; then
    echo "$sha256  $destination" | sha256sum --check -
  else
    echo "Using commit-pinned source without a published archive checksum: $destination"
  fi
}

extract() {
  local archive="$1"
  local destination="$2"

  rm -rf "$destination"
  mkdir -p "$destination"
  tar -xf "$archive" -C "$destination" --strip-components=1
}

configure_make_install() {
  local source_dir="$1"
  shift

  (
    cd "$source_dir"
    env \
      CC="$CC" \
      CXX="${CXX:-}" \
      AR="$AR" \
      RANLIB="$RANLIB" \
      STRIP="${STRIP:-strip}" \
      PKG_CONFIG="${PKG_CONFIG:-pkg-config}" \
      PKG_CONFIG_LIBDIR="$prefix/lib/pkgconfig:$prefix/share/pkgconfig" \
      PKG_CONFIG_SYSROOT_DIR= \
      CPPFLAGS="-I$prefix/include ${CPPFLAGS:-}" \
      CFLAGS="-Os -fPIC -ffunction-sections -fdata-sections -mcpu=cortex-a9 -mfloat-abi=softfp -mfpu=neon ${CFLAGS:-}" \
      CXXFLAGS="-Os -fPIC -ffunction-sections -fdata-sections -mcpu=cortex-a9 -mfloat-abi=softfp -mfpu=neon ${CXXFLAGS:-}" \
      LDFLAGS="-L$prefix/lib ${LDFLAGS:-}" \
      ./configure \
        --build="$(gcc -dumpmachine)" \
        --host="$host_triplet" \
        --prefix="$prefix" \
        --disable-shared \
        --enable-static \
        "$@"
    make -j"$jobs"
    make install
  )
}

build_ogg() {
  local version=1.3.6
  local archive="$download_dir/libogg-$version.tar.xz"
  local source_dir="$build_root/libogg-$version"

  [[ -s "$prefix/lib/libogg.a" ]] && return
  download \
    "https://downloads.xiph.org/releases/ogg/libogg-$version.tar.xz" \
    "$archive" \
    "5c8253428e181840cd20d41f3ca16557a9cc04bad4a3d04cce84808677fa1061"
  extract "$archive" "$source_dir"
  configure_make_install "$source_dir"
}

build_vorbis() {
  local version=1.3.7
  local archive="$download_dir/libvorbis-$version.tar.xz"
  local source_dir="$build_root/libvorbis-$version"

  [[ -s "$prefix/lib/libvorbisfile.a" ]] && return
  download \
    "https://downloads.xiph.org/releases/vorbis/libvorbis-$version.tar.xz" \
    "$archive" \
    "b33cc4934322bcbf6efcbacf49e3ca01aadbea4114ec9589d1b1e9d20f72954b"
  extract "$archive" "$source_dir"
  configure_make_install "$source_dir"
}

build_flac() {
  local version=1.5.0
  local archive="$download_dir/flac-$version.tar.xz"
  local source_dir="$build_root/flac-$version"

  [[ -s "$prefix/lib/libFLAC.a" ]] && return
  download \
    "https://downloads.xiph.org/releases/flac/flac-$version.tar.xz" \
    "$archive" \
    "f2c1c76592a82ffff8413ba3c4a1299b6c7ab06c734dee03fd88630485c2b920"
  extract "$archive" "$source_dir"
  configure_make_install "$source_dir" \
    --disable-cpplibs \
    --disable-programs \
    --disable-examples
}

build_mad() {
  local version=0.15.1b
  local archive="$download_dir/libmad-$version.tar.gz"
  local source_dir="$build_root/libmad-$version"

  [[ -s "$prefix/lib/libmad.a" ]] && return
  download \
    "https://downloads.sourceforge.net/mad/libmad-$version.tar.gz" \
    "$archive" \
    "bbfac3ed6bfbc2823d3775ebb931087371e142bb0e9bb1bee51a76a6e0078690"
  extract "$archive" "$source_dir"

  # GCC removed -fforce-mem years ago, but libmad's generated configure
  # script still adds it for optimized builds.
  sed -i 's/-fforce-mem//g' "$source_dir/configure"
  configure_make_install "$source_dir" \
    --with-pic \
    --enable-fpm=no
}

build_mpeg2() {
  local revision=946bf4b518aacc224f845e73708f99e394744499
  local archive="$download_dir/libmpeg2-$revision.tar.gz"
  local source_dir="$build_root/libmpeg2-$revision"

  [[ -s "$prefix/lib/libmpeg2.a" ]] && return
  download \
    "https://code.videolan.org/videolan/libmpeg2/-/archive/$revision/libmpeg2-$revision.tar.gz" \
    "$archive" \
    "${LIBMPEG2_SHA256:-}"
  extract "$archive" "$source_dir"
  (
    cd "$source_dir"
    autoreconf -fi
  )
  configure_make_install "$source_dir" \
    --disable-sdl
}

build_theora() {
  local version=1.2.0
  local archive="$download_dir/libtheora-$version.tar.gz"
  local source_dir="$build_root/libtheora-$version"

  [[ -s "$prefix/lib/libtheoradec.a" ]] && return
  download \
    "https://downloads.xiph.org/releases/theora/libtheora-$version.tar.gz" \
    "$archive" \
    "279327339903b544c28a92aeada7d0dcfd0397b59c2f368cc698ac56f515906e"
  extract "$archive" "$source_dir"
  configure_make_install "$source_dir" \
    --disable-asm \
    --disable-encode \
    --disable-examples
}

build_ogg
build_vorbis
build_flac
build_mad
build_mpeg2
build_theora

required_archives=(
  libogg.a
  libvorbis.a
  libvorbisfile.a
  libFLAC.a
  libmad.a
  libmpeg2.a
  libmpeg2convert.a
  libtheora.a
  libtheoradec.a
)

for archive in "${required_archives[@]}"; do
  if [[ ! -s "$prefix/lib/$archive" ]]; then
    echo "Codec archive was not installed: $prefix/lib/$archive" >&2
    exit 1
  fi
done

echo "Static webOS codec libraries are ready in $prefix"
