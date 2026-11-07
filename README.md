# macOS dotfiles

Personal macOS configuration for AeroSpace, SketchyBar, and Kitty. The
repository is organized as a small, self-contained home-directory payload:

```text
home/                         files linked into ~/
  .aerospace.toml             AeroSpace configuration
  .config/aerospace/          icon renderer and icon mappings
  .config/kitty/              Kitty terminal configuration
  .config/sketchybar/         SketchyBar configuration and plugins
  .local/bin/                 AeroSpace helper commands
tests/aerospace/              deterministic workspace-layout tests
vendor/                       ignored, optional local source worktrees
Brewfile                      required GUI tools and font
install                       safe symlink installer
```

## Install

Install the applications and font (Homebrew):

```sh
brew bundle
```

The Brewfile declares item-level trust for the AeroSpace cask, which is hosted
in its official third-party Homebrew tap. This keeps `brew bundle` compatible
with Homebrew 6 without trusting every package in that tap.

Preview the links the installer would create:

```sh
./install --dry-run --backup
```

Install them. The current setup contains links from the previous layout, so
the first migration should back them up:

```sh
./install --backup
```

The installer links individual files instead of replacing `~/.config` or an
entire application directory. Existing conflicting files are moved to
`~/.dotfiles-backups/<timestamp>/`; unrelated configuration remains in place.
Re-running it is idempotent.

## Managed configuration

| Application | Installed path | Source |
| --- | --- | --- |
| AeroSpace | `~/.aerospace.toml` | `home/.aerospace.toml` |
| Kitty | `~/.config/kitty/kitty.conf` | `home/.config/kitty/kitty.conf` |
| SketchyBar | `~/.config/sketchybar/` | `home/.config/sketchybar/` |
| helpers | `~/.local/bin/aerospace-*` | `home/.local/bin/` |

## Global Kitty shortcut

`⌘T` opens Kitty (or brings it to the foreground) through AeroSpace. The
binding is stored in `home/.aerospace.toml`, which the installer links to
`~/.aerospace.toml`; it therefore takes effect on a new computer after
`brew bundle` and `./install --backup`. AeroSpace requires macOS Accessibility
permission for its global shortcuts.

The AeroSpace helpers use their installed locations by default. The app-icon
renderer and mappings live in `~/.config/aerospace`; no path depends on where
this repository is cloned.

Display changes are debounced before the workspace map is reconciled. The
handler requires AeroSpace and SketchyBar's display inventories to remain
unchanged across repeated checks, avoiding the temporary laptop-plus-one state
seen during a fast laptop-plus-two to laptop disconnect. Once the new topology
settles, it reloads AeroSpace's config and restores the main binding mode. This
automatically covers the config reload that was previously done with
`relaunch_bar_and_aero.sh` after a display transition.

Workspace items are assigned through a monitor-to-SketchyBar arrangement map.
Physical displays are matched by their CoreGraphics direct-display IDs first;
unresolved AirPlay displays are then paired with the remaining arrangements.
This handles laptop plus AirPlay, laptop plus a physical monitor and AirPlay,
and laptop plus two AirPlay displays even though AeroSpace may report synthetic
AirPlay IDs (such as `2`) while SketchyBar reports IDs such as `14`.

If Option shortcuts are still unavailable, check for macOS Secure Input:

```sh
ioreg -l -w 0 -d 1 -c IOHIDSystem | grep kCGSSessionSecureInputPID
```

A non-zero PID is an application that macOS is allowing to suppress global
shortcuts. Identify it with `ps -p <PID> -o comm=` and close or unlock that app;
reloading AeroSpace cannot bypass Secure Input.

## Optional CPU-temperature provider

SketchyBar uses the local `~/.local/bin/stats_provider` build when it is
present. Build the optional local worktree when it is present:

```sh
cargo install --path vendor/sketchybar-system-stats --root "$HOME/.local" --force
```

This intentionally is not a Brewfile dependency, so setup does not require
trusting the third-party `joncrangle/tap`.

`vendor/` is ignored so reference repositories and local dependency worktrees
do not become accidental nested Git repositories. See
[`vendor/README.md`](vendor/README.md) for details.

## Media player

The built-in display has a media compartment immediately left of the notch. It
uses macOS Now Playing for system-wide previous/play-pause/next controls and
Cava's Core Audio tap for a 5 FPS spectrum. The spectrum runs only while media
is playing; paused sessions keep their title and controls visible. `brew bundle`
installs the required `cava`, `nowplaying-cli`, and Python tools.

On current macOS releases, Homebrew Cava 1.0.0's Core Audio Tap preflight can
report a false permission denial, even after **System Audio Recording Only** is
enabled. After `brew bundle`, `./install` automatically builds the patched
local Cava on its first run. To do that step manually, run:

```sh
~/.local/bin/cava-audiotap-install
brew services restart sketchybar
```

The installer builds Cava 1.0.0 without that premature preflight and places it
at `~/.local/opt/cava-audiotap/bin/cava`; the media visualizer automatically
uses it. Core Audio then performs the real TCC access check, which works both
from Terminal and SketchyBar's launchd service. Its runtime diagnostics are
available at `$TMPDIR/sketchybar-media/visualizer.log`. The player controls and
metadata do not require audio-capture permission. Use
`SKIP_CAVA_AUDIOTAP_INSTALL=true ./install` to skip the automatic build.

## Validation

```sh
./tests/aerospace/test-workspace-layout.sh
./tests/aerospace/test-workspace-guard.sh
./tests/aerospace/test-workspace-icons.sh
./tests/aerospace/test-workspace-indicators.sh
bash -n home/.local/bin/aerospace-apply-workspace-layout
bash -n home/.local/bin/aerospace-guard-workspaces
bash -n home/.local/bin/aerospace-sync-workspace-icons
bash -n home/.config/sketchybar/plugins/media.sh
PYTHONDONTWRITEBYTECODE=1 python3 -c 'import ast, pathlib; ast.parse(pathlib.Path("home/.config/sketchybar/plugins/media_visualizer.py").read_text())'
bash -n install
```

After editing either configuration, run:

```sh
./relaunch_bar_and_aero.sh
```

This reloads both configurations in place. Use `./relaunch_bar_and_aero.sh
--reboot` to restart both applications; it snapshots and restores the current
workspace-to-monitor and window-to-workspace assignments.
