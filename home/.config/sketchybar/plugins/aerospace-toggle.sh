#!/usr/bin/env bash

set -u

aerospace_bin="${AEROSPACE_BIN:-/opt/homebrew/bin/aerospace}"
state_file="${TMPDIR:-/tmp}/sketchybar-aerospace-enabled"
item_name="${NAME:-aerospace_toggle}"

state="on"
if [[ -r "$state_file" ]]; then
  IFS= read -r state < "$state_file" || state="on"
fi

if [[ "${1:-}" == "toggle" || "${SENDER:-}" == "mouse.clicked" ]]; then
  # If AeroSpace has crashed, a toggle cannot reach it. Treat the click as
  # "turn tiling back on" and relaunch it instead of silently doing nothing.
  if ! /usr/bin/pgrep -x AeroSpace >/dev/null; then
    /usr/bin/open -gja AeroSpace
    printf 'on\n' > "$state_file"
    sketchybar --set "$item_name" background.drawing=on
    exit 0
  fi

  if ! "$aerospace_bin" enable toggle; then
    exit 0
  fi

  if [[ "$state" == "on" ]]; then
    state="off"
  else
    state="on"
  fi
  printf '%s\n' "$state" > "$state_file"

  # Display changes still occur while AeroSpace is intentionally disabled. On
  # re-enable, reconcile any workspace placement that could not be queried in
  # that state. The single-display fallback already keeps all bar icons visible.
  if [[ "$state" == "on" ]]; then
    "$HOME/.local/bin/aerospace-apply-workspace-layout" >/dev/null 2>&1 &
  fi
fi

if [[ "$state" == "on" ]]; then
  sketchybar --set "$item_name" background.drawing=on
else
  sketchybar --set "$item_name" background.drawing=off
fi
