#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
codec_prefix="${CODEC_PREFIX:-$repo_root/build/codecs}"
work_dir="${CODEC_TEST_DIR:-$repo_root/build/codec-smoke}"
host_cc="${HOST_CC:-gcc}"

if [[ -z "${AR:-}" || -z "${NM:-}" ]]; then
  echo "Source the webOS NDK environment-setup before running codec tests." >&2
  exit 1
fi

for command in ffmpeg file "$host_cc" "$AR" "$NM"; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "Required test command not found: $command" >&2
    exit 1
  fi
done

rm -rf "$work_dir"
mkdir -p "$work_dir/target-objects"

ffmpeg -hide_banner -loglevel error -y \
  -f lavfi -i 'sine=frequency=440:sample_rate=22050:duration=0.5' \
  -c:a libmp3lame -b:a 64k "$work_dir/test.mp3"

ffmpeg -hide_banner -loglevel error -y \
  -f lavfi -i 'testsrc=size=32x32:rate=5:duration=1' \
  -an -pix_fmt yuv420p -c:v mpeg2video -f mpeg2video "$work_dir/test.m2v"

ffmpeg -hide_banner -loglevel error -y \
  -f lavfi -i 'testsrc=size=32x32:rate=5:duration=1' \
  -an -pix_fmt yuv420p -c:v libtheora -q:v 4 -f ogg "$work_dir/test.ogv"

build_and_run_host_test() {
  local name="$1"
  local define="$2"
  local sample="$3"
  shift 3

  "$host_cc" \
    -std=c99 -Wall -Wextra -Werror -O2 \
    "-D$define" \
    "$repo_root/tests/codec-smoke.c" \
    "$@" \
    -o "$work_dir/codec-smoke-$name"

  echo "Running native $name decoder smoke test"
  "$work_dir/codec-smoke-$name" "$sample"
}

build_and_run_host_test mp3 CODEC_TEST_MP3 "$work_dir/test.mp3" -lmad -lm
build_and_run_host_test mpeg2 CODEC_TEST_MPEG2 "$work_dir/test.m2v" -lmpeg2
build_and_run_host_test theora CODEC_TEST_THEORA "$work_dir/test.ogv" -ltheoradec -logg

check_target_archive() {
  local archive_name="$1"
  local required_symbol="$2"
  local archive="$codec_prefix/lib/$archive_name"
  local member
  local object="$work_dir/target-objects/${archive_name%.a}.o"

  test -s "$archive" || {
    echo "Missing target codec archive: $archive" >&2
    exit 1
  }

  "$NM" -g --defined-only "$archive" | grep -Eq "[[:space:]]$required_symbol$" || {
    echo "Target archive $archive_name does not define $required_symbol" >&2
    exit 1
  }

  member="$("$AR" t "$archive" | head -n 1)"
  test -n "$member" || {
    echo "Target archive is empty: $archive" >&2
    exit 1
  }
  "$AR" p "$archive" "$member" > "$object"
  file "$object" | grep -q 'ARM' || {
    echo "Target archive $archive_name does not contain ARM objects" >&2
    file "$object" >&2
    exit 1
  }

  echo "$archive_name: ARM archive contains $required_symbol"
}

check_target_archive libmad.a mad_frame_decode
check_target_archive libmpeg2.a mpeg2_parse
check_target_archive libtheoradec.a th_decode_packetin
check_target_archive libogg.a ogg_sync_pageout

echo "Native decoder tests and ARM target archive checks passed."
