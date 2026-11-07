#!/bin/bash

set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
mapper="$script_dir/../../home/.local/bin/aerospace-apply-workspace-layout"
display_handler="$script_dir/../../home/.config/sketchybar/plugins/aerospace-display-change.sh"
fake_aerospace="$script_dir/fake-aerospace"
fake_sketchybar="$script_dir/fake-sketchybar"

wrong_workspace_locations=$'1|99\n2|99\n3|99\n4|99\n5|99\n6|99\n7|99\n8|99\n9|99'

assert_mapping() {
    local name="$1"
    local monitors="$2"
    local expected="$3"
    local actual

    actual="$(FAKE_MONITORS="$monitors" FAKE_WORKSPACES="$wrong_workspace_locations" \
        AEROSPACE_BIN="$fake_aerospace" "$mapper" --dry-run 2>/dev/null)"

    if [[ "$actual" != "$expected" ]]; then
        echo "$name mapping failed" >&2
        diff -u <(printf '%s\n' "$expected") <(printf '%s\n' "$actual") >&2 || true
        exit 1
    fi
}

assert_mapping \
    "laptop" \
    $'1|Built-in Retina Display' \
    $'DRY-RUN workspace=1 target-monitor=1\nDRY-RUN workspace=2 target-monitor=1\nDRY-RUN workspace=3 target-monitor=1\nDRY-RUN workspace=4 target-monitor=1\nDRY-RUN workspace=5 target-monitor=1\nDRY-RUN workspace=6 target-monitor=1\nDRY-RUN workspace=7 target-monitor=1\nDRY-RUN workspace=8 target-monitor=1\nDRY-RUN workspace=9 target-monitor=1'

assert_mapping \
    "laptop-plus-one" \
    $'1|LG UltraFine\n2|Built-in Retina Display' \
    $'DRY-RUN workspace=1 target-monitor=2\nDRY-RUN workspace=2 target-monitor=2\nDRY-RUN workspace=3 target-monitor=2\nDRY-RUN workspace=4 target-monitor=2\nDRY-RUN workspace=5 target-monitor=1\nDRY-RUN workspace=6 target-monitor=1\nDRY-RUN workspace=7 target-monitor=1\nDRY-RUN workspace=8 target-monitor=1\nDRY-RUN workspace=9 target-monitor=1'

assert_mapping \
    "laptop-plus-two" \
    $'1|LG Left\n2|Built-in Retina Display\n3|LG Right' \
    $'DRY-RUN workspace=1 target-monitor=2\nDRY-RUN workspace=2 target-monitor=2\nDRY-RUN workspace=3 target-monitor=2\nDRY-RUN workspace=4 target-monitor=1\nDRY-RUN workspace=5 target-monitor=1\nDRY-RUN workspace=6 target-monitor=1\nDRY-RUN workspace=7 target-monitor=3\nDRY-RUN workspace=8 target-monitor=3\nDRY-RUN workspace=9 target-monitor=3'

assert_sketchybar_mapping() {
    local name="$1"
    local monitors="$2"
    local workspaces="$3"
    local displays="$4"
    local expected="$5"
    local mapping_test_dir mapping_log

    mapping_test_dir="$(mktemp -d)"
    mapping_log="$mapping_test_dir/sketchybar.log"
    FAKE_MONITORS="$monitors" \
        FAKE_WORKSPACES="$workspaces" \
        FAKE_SKETCHYBAR_DISPLAYS="$displays" \
        FAKE_SKETCHYBAR_LOG="$mapping_log" \
        AEROSPACE_BIN="$fake_aerospace" \
        SKETCHYBAR_BIN="$fake_sketchybar" \
        AEROSPACE_ICON_SYNC_HELPER=/bin/true \
        AEROSPACE_LAYOUT_STATE_DIR="$mapping_test_dir/state" \
        PATH=/usr/bin:/bin \
        "$mapper" >/dev/null 2>&1

    if ! rg -qxF -- "$expected" "$mapping_log"; then
        echo "$name SketchyBar mapping failed" >&2
        sed -n '/^--set /p' "$mapping_log" >&2
        rm -rf "$mapping_test_dir"
        exit 1
    fi
    rm -rf "$mapping_test_dir"
}

laptop_airplay_workspaces=$'1|1\n2|1\n3|1\n4|1\n5|2\n6|2\n7|2\n8|2\n9|2'
laptop_three_display_workspaces=$'1|1\n2|1\n3|1\n4|2\n5|2\n6|2\n7|3\n8|3\n9|3'

assert_sketchybar_mapping \
    "laptop-plus-airplay" \
    $'1|Built-in Retina Display|1\n2|Roku (AirPlay)|2' \
    "$laptop_airplay_workspaces" \
    $'[\n{"arrangement-id":1,\n"DirectDisplayID":1},\n{"arrangement-id":2,\n"DirectDisplayID":14}\n]' \
    '--set space.1 display=1 --set space.2 display=1 --set space.3 display=1 --set space.4 display=1 --set space.5 display=2 --set space.6 display=2 --set space.7 display=2 --set space.8 display=2 --set space.9 display=2'

assert_sketchybar_mapping \
    "laptop-plus-monitor-plus-airplay" \
    $'1|Built-in Retina Display|1\n2|LG UltraFine|3\n3|Roku (AirPlay)|2' \
    "$laptop_three_display_workspaces" \
    $'[\n{"arrangement-id":1,\n"DirectDisplayID":1},\n{"arrangement-id":2,\n"DirectDisplayID":14},\n{"arrangement-id":3,\n"DirectDisplayID":3}\n]' \
    '--set space.1 display=1 --set space.2 display=1 --set space.3 display=1 --set space.4 display=3 --set space.5 display=3 --set space.6 display=3 --set space.7 display=2 --set space.8 display=2 --set space.9 display=2'

assert_sketchybar_mapping \
    "laptop-plus-two-airplay" \
    $'1|Built-in Retina Display|1\n2|Living Room (AirPlay)|2\n3|Bedroom (AirPlay)|3' \
    "$laptop_three_display_workspaces" \
    $'[\n{"arrangement-id":1,\n"DirectDisplayID":1},\n{"arrangement-id":2,\n"DirectDisplayID":14},\n{"arrangement-id":3,\n"DirectDisplayID":15}\n]' \
    '--set space.1 display=1 --set space.2 display=1 --set space.3 display=1 --set space.4 display=2 --set space.5 display=2 --set space.6 display=2 --set space.7 display=3 --set space.8 display=3 --set space.9 display=3'

batch_test_dir="$(mktemp -d)"
trap 'rm -rf "$batch_test_dir"' EXIT
batch_log="$batch_test_dir/aerospace.log"
batch_state_dir="$batch_test_dir/state"
FAKE_MONITORS=$'1|LG Left\n2|Built-in Retina Display\n3|LG Right' \
    FAKE_WORKSPACES="$wrong_workspace_locations" \
    FAKE_AEROSPACE_LOG="$batch_log" \
    AEROSPACE_BIN="$fake_aerospace" \
    AEROSPACE_ICON_SYNC_HELPER=/bin/true \
    AEROSPACE_LAYOUT_STATE_DIR="$batch_state_dir" \
    PATH=/usr/bin:/bin \
    "$mapper" >/dev/null 2>&1

expected_batch='eval move-workspace-to-monitor --workspace 1 2;move-workspace-to-monitor --workspace 2 2;move-workspace-to-monitor --workspace 3 2;move-workspace-to-monitor --workspace 4 1;move-workspace-to-monitor --workspace 5 1;move-workspace-to-monitor --workspace 6 1;move-workspace-to-monitor --workspace 7 3;move-workspace-to-monitor --workspace 8 3;move-workspace-to-monitor --workspace 9 3'
if ! rg -qxF "$expected_batch" "$batch_log"; then
    echo "workspace moves were not sent as one AeroSpace eval" >&2
    exit 1
fi

unchanged_bad_layout_log="$batch_test_dir/unchanged-bad-layout-aerospace.log"
unchanged_bad_layout_state="$batch_test_dir/unchanged-bad-layout-state"
mkdir -p "$unchanged_bad_layout_state"
printf '%s\n' $'1|ASUS PB278\n2|Built-in Retina Display' > "$unchanged_bad_layout_state/last-topology"
FAKE_MONITORS=$'1|ASUS PB278\n2|Built-in Retina Display' \
    FAKE_WORKSPACES=$'1|2\n2|2\n3|2\n4|2\n5|1\n6|1\n7|1\n8|2\n9|2' \
    FAKE_AEROSPACE_LOG="$unchanged_bad_layout_log" \
    AEROSPACE_BIN="$fake_aerospace" \
    AEROSPACE_ICON_SYNC_HELPER=/bin/true \
    AEROSPACE_LAYOUT_STATE_DIR="$unchanged_bad_layout_state" \
    AEROSPACE_LAYOUT_STABLE_CHECKS=1 \
    PATH=/usr/bin:/bin \
    "$mapper" --delay 0 --from-display-change >/dev/null 2>&1

if ! rg -qxF 'eval move-workspace-to-monitor --workspace 8 1;move-workspace-to-monitor --workspace 9 1' "$unchanged_bad_layout_log"; then
    echo "unchanged topology preserved an invalid workspace layout" >&2
    exit 1
fi

focus_change_log="$batch_test_dir/focus-change-aerospace.log"
focus_change_sketchybar_log="$batch_test_dir/focus-change-sketchybar.log"
focus_change_calls_file="$batch_test_dir/focus-change-calls"
workspace_display_rows=$'1|1\n2|1\n3|1\n4|3\n5|3\n6|3\n7|2\n8|2\n9|2'
sketchybar_displays=$'[\n  {\n    "arrangement-id": 1,\n    "DirectDisplayID": 1\n  },\n  {\n    "arrangement-id": 2,\n    "DirectDisplayID": 3\n  },\n  {\n    "arrangement-id": 3,\n    "DirectDisplayID": 2\n  }\n]'
ln -s "$fake_sketchybar" "$batch_test_dir/sketchybar"
FAKE_MONITORS=$'1|Built-in Retina Display|1\n3|LG Left|3\n2|LG Right|2' \
    FAKE_WORKSPACES="$workspace_display_rows" \
    FAKE_SKETCHYBAR_DISPLAYS="$sketchybar_displays" \
    FAKE_FOCUSED_WORKSPACES='1,2' \
    FAKE_FOCUSED_WORKSPACE_CALLS_FILE="$focus_change_calls_file" \
    FAKE_AEROSPACE_LOG="$focus_change_log" \
    FAKE_SKETCHYBAR_LOG="$focus_change_sketchybar_log" \
    AEROSPACE_BIN="$fake_aerospace" \
    SKETCHYBAR_BIN="$fake_sketchybar" \
    AEROSPACE_ICON_SYNC_HELPER=/bin/true \
    AEROSPACE_LAYOUT_STATE_DIR="$batch_test_dir/focus-change-state" \
    PATH=/usr/bin:/bin \
    "$mapper" --delay 0 --from-display-change >/dev/null 2>&1

if rg -q '^eval ' "$focus_change_log"; then
    echo "focus change during settling should skip workspace moves" >&2
    exit 1
fi
if ! rg -qxF -- '--set space.1 display=1 --set space.2 display=1 --set space.3 display=1 --set space.4 display=2 --set space.5 display=2 --set space.6 display=2 --set space.7 display=3 --set space.8 display=3 --set space.9 display=3' "$focus_change_sketchybar_log"; then
    echo "focus change during settling did not refresh SketchyBar display assignments" >&2
    exit 1
fi
if [[ "$(rg -c '^reload-config$' "$focus_change_log")" != 1 ]]; then
    echo "display change did not reload AeroSpace config exactly once" >&2
    exit 1
fi
if [[ "$(rg -c '^mode main$' "$focus_change_log")" != 1 ]]; then
    echo "display change did not restore AeroSpace main mode exactly once" >&2
    exit 1
fi
reload_line="$(rg -n '^reload-config$' "$focus_change_log" | cut -d: -f1)"
monitor_line="$(rg -n '^list-monitors ' "$focus_change_log" | cut -d: -f1 | tail -n 1)"
if [[ -z "$reload_line" || -z "$monitor_line" || "$reload_line" -ge "$monitor_line" ]]; then
    echo "AeroSpace hotkeys were not refreshed before display reconciliation" >&2
    exit 1
fi

display_handler_args="$(AEROSPACE_LAYOUT_HELPER=/bin/echo AEROSPACE_LAYOUT_DELAY=0 "$display_handler")"
if [[ "$display_handler_args" != '--delay 0 --from-display-change' ]]; then
    echo "display-change event did not invoke the workspace reconciler" >&2
    exit 1
fi

default_display_handler_args="$(AEROSPACE_LAYOUT_HELPER=/bin/echo "$display_handler")"
if [[ "$default_display_handler_args" != '--delay 0.25 --from-display-change' ]]; then
    echo "display-change event did not use the short quiet-period debounce" >&2
    exit 1
fi

disabled_sketchybar_log="$batch_test_dir/disabled-sketchybar.log"
FAKE_SKETCHYBAR_DISPLAYS=$'[\n  {\n    "arrangement-id": 1,\n    "DirectDisplayID": 1\n  }\n]' \
    FAKE_SKETCHYBAR_LOG="$disabled_sketchybar_log" \
    FAKE_AEROSPACE_DISABLED=true \
    AEROSPACE_BIN="$fake_aerospace" \
    SKETCHYBAR_BIN="$fake_sketchybar" \
    AEROSPACE_LAYOUT_STATE_DIR="$batch_test_dir/disabled-state" \
    PATH=/usr/bin:/bin \
    "$mapper" --delay 0 --from-display-change >/dev/null 2>&1 || {
        echo "disabled AeroSpace fallback failed" >&2
        exit 1
    }

expected_disabled_args='--set space.1 display=1 --set space.2 display=1 --set space.3 display=1 --set space.4 display=1 --set space.5 display=1 --set space.6 display=1 --set space.7 display=1 --set space.8 display=1 --set space.9 display=1'
if ! rg -qxF -- "$expected_disabled_args" "$disabled_sketchybar_log"; then
    echo "disabled AeroSpace fallback did not assign all icons to the only display" >&2
    exit 1
fi
disabled_inventory_checks="$(rg -c '^--query displays$' "$disabled_sketchybar_log")"
if ((disabled_inventory_checks < 8)); then
    echo "display settling did not require repeated stable inventory checks" >&2
    exit 1
fi

echo "workspace layout tests passed"
