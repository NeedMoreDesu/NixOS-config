#!/run/current-system/sw/bin/bash
# macOS-style screenshots via Spectacle, called from xremap (Cmd = F13):
#   Cmd+Shift+1 -> current (active) window
#   Cmd+Shift+2 -> window under cursor
#   Cmd+Shift+3 -> full screen
#   Cmd+Shift+4 -> rectangular region
#   Cmd+Shift+5 -> Spectacle GUI (launch only)
#
# Background mode (-b) ignores Spectacle's GUI auto-save/clipboard settings,
# so pass -o + -c explicitly: a timestamped file in $SPECTACLE_SCREENSHOT_DIR
# AND the image on the clipboard (same as macOS Cmd+Shift+3/4).
#
# The shebang is the ABSOLUTE bash on purpose: xremap launches the script as
# `bash /path/screenshot.sh <mode>`, and the xremap unit's PATH contains no
# bash (a `#!/usr/bin/env bash` shebang would die with exit 127 there).
# The script also sets its own PATH because that unit PATH is minimal.
set -euo pipefail

PATH=/run/current-system/sw/bin:/run/current-system/sw/sbin:$PATH
export PATH

mode=${1:-region}
dir=${SPECTACLE_SCREENSHOT_DIR:-$HOME/Pictures/Screenshots}

case "$mode" in
  current) args=(-a) ;;
  window)  args=(-u) ;;
  full)    args=(-f) ;;
  region)  args=(-r) ;;
  gui)     exec spectacle -l ;;
  *)
    printf 'usage: %s current|window|full|region|gui\n' "${0##*/}" >&2
    exit 2
    ;;
esac

mkdir -p "$dir"
name="Screenshot_$(date +%Y-%m-%d_%H-%M-%S).png"
exec spectacle -b -n "${args[@]}" -c -o "$dir/$name"
