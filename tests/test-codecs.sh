#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
codec_prefix="${CODEC_PREFIX:-$repo_root/build/codecs}"
work_dir="${CODEC_TEST_DIR:-$repo_root/build/codec-smoke}"
qemu_arm="${QEMU_ARM:-qemu-arm}"

if [[ -z "${CC:-}" || -z "${STAGING_DIR:-}" ]]; then
  echo "Source the webOS NDK environment-setup before running codec tests." >&2
  exit 1
fi

for command in ffmpeg "$qemu_arm"; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "Required test command not found: $command" >&2
    exit 1
  fi
done

required_archives=(libmad.a libmpeg2.a libtheoradec.a libogg.a)
for archive in "${required_archives[@]}"; do
  test -s "$codec_prefix/lib/$archive" || {
    echo "Missing codec archive: $codec_prefix/lib/$archive" >&2
    exit 1
  }
done

rm -rf "$work_dir"
mkdir -p "$work_dir"

ffmpeg -hide_banner -loglevel error -y \
  -f lavfi -i 'sine=frequency=440:sample_rate=22050:duration=0.5' \
  -c:a libmp3lame -b:a 64k "$work_dir/test.mp3"

ffmpeg -hide_banner -loglevel error -y \
  -f lavfi -i 'testsrc=size=32x32:rate=5:duration=1' \
  -an -pix_fmt yuv420p -c:v mpeg2video -f mpeg2video "$work_dir/test.m2v"

ffmpeg -hide_banner -loglevel error -y \
  -f lavfi -i 'testsrc=size=32x32:rate=5:duration=1' \
  -an -pix_fmt yuv420p -c:v libtheora -q:v 4 -f ogg "$work_dir/test.ogv"

"$CC" \
  -std=c99 -Wall -Wextra -Werror -Os \
  -mcpu=cortex-a9 -mfloat-abi=softfp -mfpu=neon \
  -I"$codec_prefix/include" \
  "$repo_root/tests/codec-smoke.c" \
  -L"$codec_prefix/lib" \
  -Wl,--gc-sections \
  -lmad -lmpeg2 -ltheoradec -logg -lm \
  -o "$work_dir/codec-smoke"

file "$work_dir/codec-smoke"

run_codec_test() {
  local codec="$1"
  local sample="$2"
  echo "Running ARM $codec decoder smoke test under QEMU"
  "$qemu_arm" -cpu cortex-a9 -L "$STAGING_DIR" \
    "$work_dir/codec-smoke" "$codec" "$sample"
}

run_codec_test mp3 "$work_dir/test.mp3"
run_codec_test mpeg2 "$work_dir/test.m2v"
run_codec_test theora "$work_dir/test.ogv"

echo "All target codec smoke tests passed."
