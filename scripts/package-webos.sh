#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source_dir="${SCUMMVM_SOURCE_DIR:-$repo_root/upstream}"
build_dir="${BUILD_DIR:-$repo_root/build}"
dist_dir="${DIST_DIR:-$repo_root/dist}"
package_dir="$dist_dir/package"

if [[ ! -x "$build_dir/scummvm" ]]; then
  echo "Built ScummVM binary not found at $build_dir/scummvm" >&2
  exit 1
fi

if [[ -z "${STAGING_DIR:-}" ]]; then
  echo "Source the webOS NDK environment-setup file before packaging." >&2
  exit 1
fi

if ! command -v ares-package >/dev/null 2>&1; then
  echo "ares-package is required." >&2
  exit 1
fi

upstream_version="$(sed -n 's/^#define SCUMMVM_VERSION "\(.*\)"/\1/p' "$source_dir/base/internal_version.h")"
if [[ -z "$upstream_version" ]]; then
  echo "Could not determine the ScummVM version." >&2
  exit 1
fi
version="${WEBOS_PACKAGE_VERSION:-$upstream_version}"
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Invalid webOS package version: $version" >&2
  exit 1
fi

rm -rf "$dist_dir"
mkdir -p "$package_dir/lib"

install -m 0755 "$build_dir/scummvm" "$package_dir/scummvm.bin"
"${CC:-arm-webos-linux-gnueabi-gcc}" \
  -Os -s \
  "$repo_root/packaging/launch-scummvm.c" \
  -o "$package_dir/scummvm"
sed "s/@VERSION@/$version/g" \
  "$repo_root/packaging/appinfo.json.in" > "$package_dir/appinfo.json"
install -m 0644 \
  "$source_dir/dists/emscripten/assets/scummvm-192.png" \
  "$package_dir/icon160.png"
install -m 0644 \
  "$source_dir/gui/themes/translations.dat" \
  "$source_dir/gui/themes/gui-icons.dat" \
  "$source_dir/gui/themes/scummremastered.zip" \
  "$source_dir/backends/vkeybd/packs/vkeybd_default.zip" \
  "$source_dir/dists/engine-data/fonts.dat" \
  "$package_dir/"

find_sdk_library() {
  local name="$1"
  find "$STAGING_DIR" -name "$name" -print -quit
}

copy_sdk_library() {
  local name="$1"
  local path
  path="$(find_sdk_library "$name")"
  if [[ -z "$path" ]]; then
    echo "Required SDK library not found: $name" >&2
    exit 1
  fi
  cp -L "$path" "$package_dir/lib/$name"
}

copy_sdk_library libstdc++.so.6
copy_sdk_library libatomic.so.1
copy_sdk_library libjpeg.so.8

if [[ -n "${SDL2_BUNDLE_DIR:-}" ]]; then
  sdl_path="$(find "$SDL2_BUNDLE_DIR" -name 'libSDL2-2.0.so.0' -print -quit)"
  if [[ -z "$sdl_path" ]]; then
    echo "Bundled SDL2 library not found in $SDL2_BUNDLE_DIR" >&2
    exit 1
  fi
  cp -L "$sdl_path" "$package_dir/lib/libSDL2-2.0.so.0"
fi

(
  cd "$dist_dir"
  ares-package package
)

ipk="$(find "$dist_dir" -maxdepth 1 -name '*.ipk' -print -quit)"
if [[ -z "$ipk" ]]; then
  echo "ares-package did not produce an IPK." >&2
  exit 1
fi

if [[ -n "${WEBOS_BUILD_SUFFIX:-}" ]]; then
  if [[ ! "$WEBOS_BUILD_SUFFIX" =~ ^[a-z0-9][a-z0-9.-]*$ ]]; then
    echo "Invalid webOS build suffix: $WEBOS_BUILD_SUFFIX" >&2
    exit 1
  fi
  beta_ipk="$dist_dir/org.scummvm.scummvm_${version}-${WEBOS_BUILD_SUFFIX}_arm.ipk"
  mv "$ipk" "$beta_ipk"
  ipk="$beta_ipk"
fi

sha256sum "$ipk" > "$ipk.sha256"
du -h "$ipk"
echo "PACKAGE_PATH=$ipk"
