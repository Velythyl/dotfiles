#!/bin/bash

set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
sync_icons="$script_dir/../../home/.local/bin/aerospace-sync-workspace-icons"
fake_aerospace="$script_dir/fake-aerospace"
fake_sketchybar="$script_dir/fake-sketchybar"
test_dir="$(mktemp -d)"

cleanup() {
    rm -rf "$test_dir"
}
trap cleanup EXIT

mkdir -p "$test_dir/state" "$test_dir/cache"
cp /usr/bin/true "$test_dir/renderer"
for app in com.example.one com.example.two; do
    : > "$test_dir/cache/$app-active.png"
    : > "$test_dir/cache/$app-inactive.png"
done

printf '%s\n' 'com.example.one|/Applications/One.app' > "$test_dir/state/workspace-1"
printf '%s\n' 'com.example.two|/Applications/Two.app' > "$test_dir/state/workspace-2"
printf '%s\n' 'com.example.one|/Applications/One.app' > "$test_dir/state/workspace-3"
printf '%s\n' 2 4 7 > "$test_dir/state/visible-workspaces"

FAKE_AEROSPACE_LOG="$test_dir/aerospace.log" \
FAKE_SKETCHYBAR_LOG="$test_dir/sketchybar.log" \
FAKE_FOCUSED_WORKSPACE=1 \
FAKE_VISIBLE_WORKSPACES=$'1\n4\n7' \
FAKE_FOCUSED_WINDOW='1|com.example.one|/Applications/One.app' \
FAKE_WORKSPACES=$'1\n2\n4\n7' \
FAKE_WORKSPACE_WINDOWS_1='com.example.one|/Applications/One.app' \
FAKE_WORKSPACE_WINDOWS_2='com.example.two|/Applications/Two.app' \
AEROSPACE_BIN="$fake_aerospace" \
SKETCHYBAR_BIN="$fake_sketchybar" \
AEROSPACE_ICON_STATE_DIR="$test_dir/state" \
AEROSPACE_ICON_CACHE_DIR="$test_dir/cache" \
AEROSPACE_ICON_LOCK_DIR="$test_dir/icon-update.lock" \
AEROSPACE_CONFIG_DIR="$test_dir/config" \
AEROSPACE_ICON_RENDERER="$test_dir/renderer" \
"$sync_icons" --workspace-change 4 1

for workspace in 1 2; do
    if ! rg -q --fixed-strings "list-windows --workspace $workspace" "$test_dir/aerospace.log"; then
        echo "workspace $workspace was not refreshed after focus changed" >&2
        exit 1
    fi
done

for workspace in 4 7; do
    if rg -q --fixed-strings "list-windows --workspace $workspace" "$test_dir/aerospace.log"; then
        echo "unchanged visible workspace $workspace was refreshed after focus changed" >&2
        exit 1
    fi
done

if ! rg -q 'space\.2 .*com\.example\.two-inactive\.png' "$test_dir/sketchybar.log"; then
    echo "the workspace that became hidden did not receive its inactive icon" >&2
    exit 1
fi

if ! rg -q 'space\.1 .*com\.example\.one-active\.png' "$test_dir/sketchybar.log"; then
    echo "the newly visible workspace did not receive its active icon" >&2
    exit 1
fi

if ! rg -q '^--trigger aerospace_workspace_icons_changed$' "$test_dir/sketchybar.log"; then
    echo "workspace icon updates did not notify dependent SketchyBar items" >&2
    exit 1
fi

echo "workspace icon tests passed"
