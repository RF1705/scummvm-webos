#!/bin/sh
set -eu

app_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

# webOS appends its native lifecycle data as the first argument. ScummVM
# interprets an unfiltered JSON object as a game target and exits immediately.
case "${1-}" in
  \{*\})
    shift
    ;;
esac

export LD_LIBRARY_PATH="$app_dir/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
exec "$app_dir/scummvm.bin" "$@" > /tmp/org.scummvm.scummvm.log 2>&1
