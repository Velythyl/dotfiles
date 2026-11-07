#!/usr/bin/env bash

# Owns the event-driven media UI. Audio frames themselves are handled by the
# separate visualizer process so media events never need to poll. We query the
# active Now Playing session here because SketchyBar's initial media_change
# event can have an empty payload after a reload.
set -u

plugin_dir="${CONFIG_DIR:-$HOME/.config/sketchybar}/plugins"
visualizer="$plugin_dir/media_visualizer.py"
sketchybar_bin="${SKETCHYBAR_BIN:-$(command -v sketchybar 2>/dev/null || true)}"
python_bin="${PYTHON_BIN:-$(command -v python3 2>/dev/null || true)}"
nowplaying_bin="${NOWPLAYING_BIN:-$(command -v nowplaying-cli 2>/dev/null || true)}"
runtime_dir="${TMPDIR:-/tmp}/sketchybar-media"
pause_file="$runtime_dir/paused-since"
pause_timeout="${MEDIA_PAUSE_TIMEOUT_SECONDS:-600}"

if [[ ! "$pause_timeout" =~ ^[0-9]+$ ]]; then
  pause_timeout=600
fi

set_drawing() {
  local drawing="$1"
  "$sketchybar_bin" \
    --set media_title "drawing=$drawing" \
    --set media_previous "drawing=$drawing" \
    --set media_toggle "drawing=$drawing" \
    --set media_next "drawing=$drawing" \
    --set media_compartment "background.drawing=$drawing"
}

clear_pause_timer() {
  rm -f "$pause_file"
}

pause_timeout_reached() {
  local now paused_since

  now="$(date +%s)"
  paused_since=""
  if [[ -r "$pause_file" ]]; then
    IFS= read -r paused_since < "$pause_file" || true
  fi

  if [[ ! "$paused_since" =~ ^[0-9]+$ ]]; then
    mkdir -p "$runtime_dir" || return 1
    printf '%s\n' "$now" > "$pause_file" || return 1
    return 1
  fi

  (( now - paused_since >= pause_timeout ))
}

visualizer_command() {
  if [[ -n "$python_bin" && -x "$visualizer" ]]; then
    "$python_bin" "$visualizer" "$1" >/dev/null 2>&1 || true
  fi
}

case "${1:-}" in
  previous|toggle|next)
    if [[ -n "$nowplaying_bin" ]]; then
      case "$1" in
        previous) "$nowplaying_bin" previous >/dev/null 2>&1 || true ;;
        toggle) "$nowplaying_bin" togglePlayPause >/dev/null 2>&1 || true ;;
        next) "$nowplaying_bin" next >/dev/null 2>&1 || true ;;
      esac

      # Some players do not emit media_change for a click quickly enough for
      # the icon to feel responsive. Re-query after the command so play/pause
      # reflects the new state even when that notification is delayed. Keep
      # this in the click script: SketchyBar may reap a background child as
      # soon as the click handler exits.
      if [[ "$1" == "toggle" ]]; then
        sleep 0.5
        SENDER=media_change CONFIG_DIR="${CONFIG_DIR:-$HOME/.config/sketchybar}" "$0"
      fi
    fi
    exit 0
    ;;
esac

case "${SENDER:-}" in
  media_change|system_woke|routine|aerospace_workspace_change|aerospace_workspace_icons_changed) ;;
  *) exit 0 ;;
esac

if [[ -z "$nowplaying_bin" ]]; then
  clear_pause_timer
  set_drawing off
  visualizer_command stop
  exit 0
fi

title=""
artist=""
playback_rate=""
app=""
{
  IFS= read -r title || true
  IFS= read -r artist || true
  IFS= read -r playback_rate || true
  IFS= read -r app || true
} < <("$nowplaying_bin" get title artist playbackRate clientBundleIdentifier 2>/dev/null)

for field in title artist playback_rate app; do
  if [[ "${!field}" == "null" ]]; then
    printf -v "$field" '%s' ""
  fi
done

# A paused session remains visible for ten minutes so it can be resumed.
# Stopped or empty sessions leave no notch-side chrome behind immediately.
if [[ -z "$app" && -z "$title" && -z "$artist" ]]; then
  clear_pause_timer
  set_drawing off
  visualizer_command stop
  exit 0
fi

if [[ -n "$title" && -n "$artist" ]]; then
  media_label="$title — $artist"
elif [[ -n "$title" ]]; then
  media_label="$title"
elif [[ -n "$artist" ]]; then
  media_label="$artist"
else
  media_label="$app"
fi

if [[ -n "$playback_rate" && "$playback_rate" != "0" ]]; then
  clear_pause_timer
  toggle_icon=""
else
  toggle_icon=""
fi

if [[ -z "$playback_rate" || "$playback_rate" == "0" ]] && pause_timeout_reached; then
  set_drawing off
  visualizer_command stop
  exit 0
fi

set_drawing on
"$sketchybar_bin" --set media_title "label=$media_label" --set media_toggle "icon=$toggle_icon"

if [[ -n "$playback_rate" && "$playback_rate" != "0" ]]; then
  visualizer_command start
else
  visualizer_command stop
fi
