#!/usr/bin/env bash
# Reload AeroSpace and SketchyBar after editing their dotfiles.
#
# Default mode reloads both configurations in place. `--reboot` fully restarts
# both processes and restores the current workspace-to-monitor and
# window-to-workspace assignments afterwards.

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./relaunch_bar_and_aero.sh [--reboot]

Without arguments, reload the active AeroSpace and SketchyBar configurations.

  --reboot  Restart both applications, then restore the current workspace /
            monitor and window / workspace assignments.
EOF
}

reboot=false
while (($#)); do
  case "$1" in
    --reboot) reboot=true ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
  shift
done

aerospace_bin="${AEROSPACE_BIN:-$(command -v aerospace || true)}"
sketchybar_bin="${SKETCHYBAR_BIN:-$(command -v sketchybar || true)}"
sketchybar_config="${SKETCHYBAR_CONFIG:-$HOME/.config/sketchybar/sketchybarrc}"

[[ -n "$aerospace_bin" && -x "$aerospace_bin" ]] || {
  echo 'AeroSpace CLI not found.' >&2
  exit 1
}
[[ -n "$sketchybar_bin" && -x "$sketchybar_bin" ]] || {
  echo 'SketchyBar CLI not found.' >&2
  exit 1
}
[[ -f "$sketchybar_config" ]] || {
  printf 'SketchyBar config not found: %s\n' "$sketchybar_config" >&2
  exit 1
}

wait_for_aerospace() {
  local attempts=100

  while ((attempts > 0)); do
    if "$aerospace_bin" list-workspaces --all --format '%{workspace}' >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.1
    attempts=$((attempts - 1))
  done

  echo 'Timed out waiting for AeroSpace to start.' >&2
  return 1
}

restart_sketchybar() {
  if command -v brew >/dev/null 2>&1 && brew services list | awk '$1 == "sketchybar" { found = 1 } END { exit !found }'; then
    brew services restart sketchybar
  else
    # AeroSpace can launch SketchyBar directly instead of through Homebrew's
    # service. Stop only the bar daemon, then replace it with the configured one.
    pkill -x sketchybar >/dev/null 2>&1 || true
    "$sketchybar_bin" --config "$sketchybar_config" >/dev/null 2>&1 &
  fi

  # A service restart can return before the daemon has accepted commands.
  local attempts=100
  while ((attempts > 0)); do
    if "$sketchybar_bin" --query bar >/dev/null 2>&1; then
      "$sketchybar_bin" --reload "$sketchybar_config"
      return 0
    fi
    sleep 0.1
    attempts=$((attempts - 1))
  done

  echo 'Timed out waiting for SketchyBar to start.' >&2
  return 1
}

if [[ "$reboot" == false ]]; then
  "$aerospace_bin" reload-config
  "$sketchybar_bin" --reload "$sketchybar_config"
  echo 'Reloaded AeroSpace and SketchyBar configurations.'
  exit 0
fi

state_dir="$(mktemp -d "${TMPDIR:-/tmp}/relaunch-bar-and-aero.XXXXXX")"
trap 'rm -rf "$state_dir"' EXIT
workspace_state="$state_dir/workspaces"
window_state="$state_dir/windows"
focused_workspace_state="$state_dir/focused-workspace"
: > "$workspace_state"
: > "$window_state"
: > "$focused_workspace_state"

# Window IDs remain stable while AeroSpace restarts because the windows
# themselves are never closed. Restoring the snapshots avoids a restart
# reshuffling the user's workspace or monitor assignments.
#
# If AeroSpace has crashed or hung, there is nothing to snapshot; skip straight
# to (re)launching it so the restart still recovers the session.
if "$aerospace_bin" list-workspaces --all --format '%{workspace}|%{monitor-id}' > "$workspace_state" 2>/dev/null; then
  "$aerospace_bin" list-windows --all --format '%{window-id}|%{workspace}' > "$window_state" || : > "$window_state"
  "$aerospace_bin" list-workspaces --focused --format '%{workspace}' > "$focused_workspace_state" || : > "$focused_workspace_state"
else
  : > "$workspace_state"
  echo 'AeroSpace is not responding; relaunching without restoring a snapshot.' >&2
fi

if pgrep -x AeroSpace >/dev/null; then
  osascript -e 'tell application id "bobko.aerospace" to quit' >/dev/null 2>&1 || true
  for _ in {1..50}; do
    pgrep -x AeroSpace >/dev/null || break
    sleep 0.1
  done
  # A hung AeroSpace will not answer the AppleScript quit request.
  if pgrep -x AeroSpace >/dev/null; then
    pkill -x AeroSpace || true
    for _ in {1..50}; do
      pgrep -x AeroSpace >/dev/null || break
      sleep 0.1
    done
  fi
  if pgrep -x AeroSpace >/dev/null; then
    echo 'Timed out waiting for AeroSpace to quit.' >&2
    exit 1
  fi
fi

open -gja AeroSpace
wait_for_aerospace

# Give AeroSpace's after-startup commands time to finish before restoring the
# snapshot. It may initially apply the standard display layout from the config.
sleep 1

while IFS='|' read -r workspace monitor_id; do
  [[ -n "$workspace" && -n "$monitor_id" ]] || continue
  current_monitor="$($aerospace_bin list-workspaces --all --format '%{workspace}|%{monitor-id}' | awk -F '|' -v wanted="$workspace" '$1 == wanted { print $2; exit }')"
  if [[ -n "$current_monitor" && "$current_monitor" != "$monitor_id" ]]; then
    "$aerospace_bin" move-workspace-to-monitor --workspace "$workspace" "$monitor_id"
  fi
done < "$workspace_state"

while IFS='|' read -r window_id workspace; do
  [[ -n "$window_id" && -n "$workspace" ]] || continue
  "$aerospace_bin" move-node-to-workspace --window-id "$window_id" "$workspace" >/dev/null 2>&1 || true
done < "$window_state"

focused_workspace="$(head -n 1 "$focused_workspace_state")"
if [[ -n "$focused_workspace" ]]; then
  "$aerospace_bin" workspace "$focused_workspace"
fi

restart_sketchybar
echo 'Rebooted AeroSpace and SketchyBar; restored workspace assignments.'
