#!/usr/bin/env bash
# macOS-style screenshots via Spectacle, called from xremap (Cmd = F13):
#   Cmd+Shift+3 -> full screen
#   Cmd+Shift+4 -> rectangular region
#   Cmd+Shift+5 -> Spectacle GUI (launch only)
#   Cmd+Shift+6 -> window picker (KWin "Select Window")
#
# Background mode (-b) ignores Spectacle's GUI auto-save/clipboard settings,
# so pass -o + -c explicitly: a timestamped file in $SPECTACLE_SCREENSHOT_DIR
# AND the image on the clipboard (same as macOS Cmd+Shift+3/4).
#
# xremap's user unit runs with a minimal PATH and no shell, so this script
# sets its own PATH and is invoked with an absolute bash path.
set -euo pipefail

PATH=/run/current-system/sw/bin:/run/current-system/sw/sbin:$PATH
export PATH

mode=${1:-region}
dir=${SPECTACLE_SCREENSHOT_DIR:-$HOME/Pictures/Screenshots}

case "$mode" in
  full)   args=(-f) ;;
  region) args=(-r) ;;
  window) args=(-u) ;;
  gui)    exec spectacle -l ;;
  *)
    printf 'usage: %s full|region|window|gui\n' "${0##*/}" >&2
    exit 2
    ;;
esac

mkdir -p "$dir"
name="Screenshot_$(date +%Y%m%d_%H%M%S_%N).png"
exec spectacle -b -n "${args[@]}" -c -o "$dir/$name"
