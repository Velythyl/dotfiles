#!/usr/bin/env bash

set -u

# launchd jobs receive a minimal PATH that does not include Homebrew.
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

log_file="${TMPDIR:-/tmp}/restart-aerospace-sketchybar.log"
lock_dir="${TMPDIR:-/tmp}/restart-aerospace-sketchybar.lock"
job_label="com.charlie.restart-aerospace-sketchybar"

if [[ "${1:-}" != "--run" ]]; then
  # The restart stops SketchyBar, so hand the work to launchd instead of
  # leaving it as a child of the click handler that SketchyBar is about to reap.
  : > "$log_file"
  /bin/launchctl submit \
    -l "$job_label" \
    -o "$log_file" \
    -e "$log_file" \
    -- "$0" --run
  exit 0
fi

# Ignore another click while a restart is already underway. Recover if a prior
# restart was terminated while SketchyBar was being replaced and left its lock.
if ! mkdir "$lock_dir" 2>/dev/null; then
  if [[ -r "$lock_dir/pid" ]]; then
    IFS= read -r lock_pid < "$lock_dir/pid" || lock_pid=""
    [[ "$lock_pid" =~ ^[0-9]+$ ]] && kill -0 "$lock_pid" 2>/dev/null && exit 0
  fi
  rm -f "$lock_dir/pid"
  rmdir "$lock_dir" 2>/dev/null || exit 0
  mkdir "$lock_dir" 2>/dev/null || exit 0
fi
printf '%s\n' "$$" > "$lock_dir/pid"
cleanup_lock() {
  rm -f "$lock_dir/pid"
  rmdir "$lock_dir" 2>/dev/null || true
}
trap cleanup_lock EXIT

# Resolve this installed symlink back into the dotfiles checkout, where the
# restart helper lives. The helper preserves workspace and window placement.
script_path="${BASH_SOURCE[0]}"
while [[ -L "$script_path" ]]; do
  script_dir="$(cd "$(dirname "$script_path")" && pwd)"
  link_target="$(readlink "$script_path")"
  if [[ "$link_target" == /* ]]; then
    script_path="$link_target"
  else
    script_path="$script_dir/$link_target"
  fi
done

repo_root="$(cd "$(dirname "$script_path")/../../../.." && pwd)"
if ! "$repo_root/relaunch_bar_and_aero.sh" --reboot; then
  echo 'Failed to restart AeroSpace and SketchyBar.' >&2
fi

# A submitted launchd job is kept alive when it exits unsuccessfully. The
# failure is already logged above, so finish successfully rather than retrying
# a disruptive restart in a loop.
cleanup_lock
trap - EXIT
/bin/launchctl remove "$job_label" >/dev/null 2>&1 || true
exit 0
