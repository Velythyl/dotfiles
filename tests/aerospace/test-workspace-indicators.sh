#!/bin/bash

set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
indicator="$script_dir/../../home/.config/sketchybar/plugins/aerospace.sh"
fake_sketchybar="$script_dir/fake-sketchybar"
test_dir="$(mktemp -d)"

cleanup() {
    rm -rf "$test_dir"
}
trap cleanup EXIT

FAKE_SKETCHYBAR_LOG="$test_dir/sketchybar.log" \
SKETCHYBAR_BIN="$fake_sketchybar" \
VISIBLE_WORKSPACES='1,4,7' \
NAME=space.4 \
"$indicator" 4

FAKE_SKETCHYBAR_LOG="$test_dir/sketchybar.log" \
SKETCHYBAR_BIN="$fake_sketchybar" \
VISIBLE_WORKSPACES='1,4,7' \
NAME=space.5 \
"$indicator" 5

if ! rg -q --fixed-strings 'space.4 icon.color=0xffebdbb2 label.color=0xffebdbb2' "$test_dir/sketchybar.log"; then
    echo "visible workspace was not styled as active" >&2
    exit 1
fi

if ! rg -q --fixed-strings 'space.5 icon.color=0x77ebdbb2 label.color=0x55ebdbb2' "$test_dir/sketchybar.log"; then
    echo "hidden workspace was not styled as inactive" >&2
    exit 1
fi

echo "workspace indicator tests passed"
