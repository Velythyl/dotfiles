#!/usr/bin/env bash

aerospace_bin="${AEROSPACE_BIN:-/opt/homebrew/bin/aerospace}"
sketchybar_bin="${SKETCHYBAR_BIN:-/opt/homebrew/bin/sketchybar}"
visible_workspaces="${VISIBLE_WORKSPACES:-}"

if [[ -z "$visible_workspaces" ]]; then
    visible_workspaces="$($aerospace_bin list-workspaces --monitor all --visible \
        --format '%{workspace}' 2>/dev/null | /usr/bin/paste -sd, -)"
fi

if [[ ",$visible_workspaces," == *",$1,"* ]]; then
    "$sketchybar_bin" --set "$NAME" icon.color=0xffebdbb2 label.color=0xffebdbb2
else
    "$sketchybar_bin" --set "$NAME" icon.color=0x77ebdbb2 label.color=0x55ebdbb2
fi
