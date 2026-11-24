#!/usr/bin/env bash
# Re-apply the Plasma config to the live session: the same work `nyx -k` does
# after a switch, but forced.
#
# plasma-manager's runner is generation-gated: each desktop script only runs
# when its generated JS differs from the last_run_* stamp. A rebuild changes
# the script content, so `nyx -k` always re-runs it; with no rebuild the stamps
# still match and the runner is a no-op (all it prints is
# "script_reset_lastrun_desktopscripts"). Drop the stamps here so the panel
# layout is pushed into the running plasmashell again.
#
# Then ask KWin to reload its config and the overview/windowview effects:
# plasma-manager only WRITES kwinrc, and KWin caches settings at startup, so a
# screen-edge change would otherwise wait for the next login. See
# docs/rebuild.md#-k--kde.
#
# If plasmashell is wedged it will not answer the scripts' evaluateScript call;
# the apply is bounded by a timeout, and on failure plasmashell is restarted
# and the layout applied once more (the panels script deletes appletsrc before
# evaluating, so that retry is what restores the panels after a restart).
#
# Run as mika; if invoked through sudo it drops back to the user's manager
# (same XDG_RUNTIME_DIR trick as rebuild.sh).
set -euo pipefail

if [[ $EUID -eq 0 ]]; then
  user="${SUDO_USER:-mika}"
  run_as() {
    runuser -u "$user" -- env XDG_RUNTIME_DIR="/run/user/$(id -u "$user")" "$@"
  }
else
  export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
  run_as() { "$@"; }
fi

runner() {
  run_as timeout 30 sh -c '"$HOME/.local/share/plasma-manager/run_all.sh"'
}

run_as sh -c 'rm -f "$HOME/.local/share/plasma-manager/last_run_desktop_script_"*'

if ! runner; then
  echo "kde-restart: plasma config apply failed or timed out - restarting plasmashell" >&2
  if run_as systemctl --user restart plasma-plasmashell.service; then
    sleep 2
    runner \
      || echo "kde-restart: plasma config apply failed again - config applies at next login" >&2
  else
    echo "kde-restart: plasmashell restart failed - config applies at next login" >&2
  fi
fi

run_as sh -c '
  qdbus org.kde.KWin /KWin org.kde.KWin.reconfigure >/dev/null 2>&1
  qdbus org.kde.KWin /Effects org.kde.kwin.Effects.reconfigureEffect overview >/dev/null 2>&1
  qdbus org.kde.KWin /Effects org.kde.kwin.Effects.reconfigureEffect windowview >/dev/null 2>&1
' || echo "kde-restart: KWin reload failed - config applies at next login" >&2
