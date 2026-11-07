#!/bin/bash

set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
guard="$script_dir/../../home/.local/bin/aerospace-guard-workspaces"
fake_aerospace="$script_dir/fake-aerospace"
test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT

valid_log="$test_dir/valid.log"
FAKE_AEROSPACE_LOG="$valid_log" AEROSPACE_BIN="$fake_aerospace" "$guard" 4 5
if [[ -e "$valid_log" ]]; then
    echo "valid workspace unnecessarily queried AeroSpace" >&2
    exit 1
fi

invalid_log="$test_dir/invalid.log"
FAKE_WORKSPACES=$'1|3|false\n2|3|false\n5|1|true\n11|3|true' \
    FAKE_WORKSPACE_WINDOWS_11=$'101\n102' \
    FAKE_AEROSPACE_LOG="$invalid_log" \
    AEROSPACE_BIN="$fake_aerospace" \
    "$guard" 1 11

for expected in \
    'move-node-to-workspace --window-id 101 1' \
    'move-node-to-workspace --window-id 102 1' \
    'workspace 1'; do
    if ! rg -qxF "$expected" "$invalid_log"; then
        echo "invalid workspace was not safely replaced: $expected" >&2
        exit 1
    fi
done

fallback_log="$test_dir/fallback.log"
FAKE_WORKSPACES=$'1|1|true\n7|3|false\n8|3|false\n10|3|true' \
    FAKE_AEROSPACE_LOG="$fallback_log" \
    AEROSPACE_BIN="$fake_aerospace" \
    "$guard" 1 10
if ! rg -qxF 'workspace 7' "$fallback_log"; then
    echo "guard did not choose a hidden valid workspace on the invalid workspace monitor" >&2
    exit 1
fi

echo "workspace guard tests passed"
