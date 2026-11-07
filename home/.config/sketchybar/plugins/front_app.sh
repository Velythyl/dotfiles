#!/bin/sh

set -eu

aerospace_bin="${AEROSPACE_BIN:-/opt/homebrew/bin/aerospace}"

case "$SENDER" in
  front_app_switched)
    app_name="$INFO"
    workspace="$($aerospace_bin list-workspaces --focused --format '%{workspace}')"
    ;;
  aerospace_workspace_change)
    app_name="${FOCUSED_APP:-—}"
    workspace="${FOCUSED_WORKSPACE:-}"
    ;;
  *)
    exit 0
    ;;
esac

case "$workspace" in
  1) subscript='₁' ;;
  2) subscript='₂' ;;
  3) subscript='₃' ;;
  4) subscript='₄' ;;
  5) subscript='₅' ;;
  6) subscript='₆' ;;
  7) subscript='₇' ;;
  8) subscript='₈' ;;
  9) subscript='₉' ;;
  *) subscript='' ;;
esac

sketchybar --set "$NAME" "label=${app_name}${subscript}"
