#!/bin/bash

# SketchyBar can emit display_change more than once while macOS settles. The
# layout helper waits for this brief quiet period after the latest event, then
# applies the final topology.
layout_helper="${AEROSPACE_LAYOUT_HELPER:-$HOME/.local/bin/aerospace-apply-workspace-layout}"
delay_seconds="${AEROSPACE_LAYOUT_DELAY:-0.25}"

exec "$layout_helper" --delay "$delay_seconds" --from-display-change
