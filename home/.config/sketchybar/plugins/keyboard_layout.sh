#!/bin/sh

# macOS updates this preference whenever the selected keyboard layout changes.
input_source_id="$(defaults read com.apple.HIToolbox AppleCurrentKeyboardLayoutInputSourceID 2>/dev/null || true)"

case "$input_source_id" in
  com.apple.keylayout.US|com.apple.keylayout.ABC)
    symbol="ABC"
    ;;
  com.apple.keylayout.Canadian)
    symbol="CA"
    ;;
  com.apple.keylayout.Canadian-CSA)
    symbol="CSA"
    ;;
  com.apple.keylayout.*)
    # Keep unfamiliar Apple layout names compact, e.g. "British" -> "BRI".
    layout_name="${input_source_id#com.apple.keylayout.}"
    symbol="$(printf '%s' "$layout_name" | tr -cd '[:alnum:]' | cut -c1-3 | tr '[:lower:]' '[:upper:]')"
    ;;
  *)
    # Input methods do not always have a keyboard-layout ID. Preserve a
    # readable indicator instead of leaving a stale value in the bar.
    symbol="IME"
    ;;
esac

sketchybar --set "$NAME" "icon=$symbol"
