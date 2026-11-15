#!/run/current-system/sw/bin/bash
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
# sets its own PATH and is invoked with an absolute bash path. xremap also
# discards the launch child's stdout/stderr, so everything is logged to
# $SCREENSHOT_LOG (default: a file in the repo, visible from the agent box).
set -euo pipefail

PATH=/run/current-system/sw/bin:/run/current-system/sw/sbin:$PATH
export PATH

mode=${1:-region}
dir=${SPECTACLE_SCREENSHOT_DIR:-$HOME/Pictures/Screenshots}
log=${SCREENSHOT_LOG:-/home/mika/nixos_config/.screenshot.log}

{
  printf '\n=== %s mode=%s\n' "$(date -Is)" "$mode"
  id
  printf 'HOME=%s\nXDG_RUNTIME_DIR=%s\nWAYLAND_DISPLAY=%s\nDISPLAY=%s\nDBUS_SESSION_BUS_ADDRESS=%s\nQT_QPA_PLATFORM=%s\n' \
    "${HOME-UNSET}" "${XDG_RUNTIME_DIR-UNSET}" "${WAYLAND_DISPLAY-UNSET}" \
    "${DISPLAY-UNSET}" "${DBUS_SESSION_BUS_ADDRESS-UNSET}" "${QT_QPA_PLATFORM-UNSET}"
  printf 'spectacle=%s\n' "$(command -v spectacle || echo NOT-FOUND)"
} >>"$log" 2>&1

case "$mode" in
  full)   args=(-f) ;;
  region) args=(-r) ;;
  window) args=(-u) ;;
  gui)
    set +e
    spectacle -l >>"$log" 2>&1
    rc=$?
    set -e
    echo "rc=$rc" >>"$log"
    exit "$rc"
    ;;
  *)
    printf 'usage: %s full|region|window|gui\n' "${0##*/}" >&2
    exit 2
    ;;
esac

mkdir -p "$dir"
name="Screenshot_$(date +%Y%m%d_%H%M%S_%N).png"
out="$dir/$name"

set +e
spectacle -b -n "${args[@]}" -c -o "$out" >>"$log" 2>&1
rc=$?
set -e

{
  echo "rc=$rc"
  ls -l "$out" 2>&1 || true
} >>"$log"

exit "$rc"
