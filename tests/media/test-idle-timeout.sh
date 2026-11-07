#!/bin/bash

set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
media_script="$script_dir/../../home/.config/sketchybar/plugins/media.sh"
fake_sketchybar="$script_dir/../aerospace/fake-sketchybar"
fake_nowplaying="$script_dir/fake-nowplaying"
test_dir="$(mktemp -d)"

cleanup() {
  rm -rf "$test_dir"
}
trap cleanup EXIT

run_media() {
  FAKE_SKETCHYBAR_LOG="$test_dir/sketchybar.log" \
  FAKE_NOWPLAYING_TITLE='A paused track' \
  FAKE_NOWPLAYING_ARTIST='Test Artist' \
  FAKE_NOWPLAYING_APP='com.example.player' \
  FAKE_NOWPLAYING_RATE="$1" \
  NOWPLAYING_BIN="$fake_nowplaying" \
  SKETCHYBAR_BIN="$fake_sketchybar" \
  PYTHON_BIN=/nonexistent \
  TMPDIR="$test_dir" \
  MEDIA_PAUSE_TIMEOUT_SECONDS=1 \
  SENDER=media_change \
  "$media_script"
}

run_media 0
if ! rg -q --fixed-strings 'media_title drawing=on' "$test_dir/sketchybar.log"; then
  echo 'paused media was hidden before its timeout' >&2
  exit 1
fi

sleep 1.1
run_media 0
if ! tail -n 1 "$test_dir/sketchybar.log" | rg -q --fixed-strings 'media_title drawing=off'; then
  echo 'paused media remained visible after its timeout' >&2
  exit 1
fi

run_media 1
if ! tail -n 2 "$test_dir/sketchybar.log" | rg -q --fixed-strings 'media_title drawing=on'; then
  echo 'media did not reappear when playback resumed' >&2
  exit 1
fi

if [[ -e "$test_dir/sketchybar-media/paused-since" ]]; then
  echo 'playback did not clear the pause timer' >&2
  exit 1
fi

echo 'media idle-timeout tests passed'
