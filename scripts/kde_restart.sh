#!/usr/bin/env bash
# Re-apply the Plasma config to the live session: the same work `nyx -k` does
# after a switch.
#
# Runs the plasma-manager runner, which diffs the generated desktop scripts
# against the last_run_* stamps (a fresh generation always re-runs them),
# pushes the layout into the running plasmashell via qdbus and restarts the
# services the scripts marked. Then asks KWin to reload its config and the
# overview/windowview effects: plasma-manager only WRITES kwinrc, and KWin
# caches settings at startup, so a screen-edge change would otherwise wait
# for the next login. See docs/rebuild.md#-k--kde.
#
# Failures are non-fatal: without a running session or a runner the config
# simply applies at next login.
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
  run_as() { "$@"; }
fi

run_as sh -c '"$HOME/.local/share/plasma-manager/run_all.sh"' \
  || echo "kde-restart: plasma-manager runner failed or absent - config applies at next login" >&2

run_as sh -c '
  qdbus org.kde.KWin /KWin org.kde.KWin.reconfigure >/dev/null 2>&1
  qdbus org.kde.KWin /Effects org.kde.kwin.Effects.reconfigureEffect overview >/dev/null 2>&1
  qdbus org.kde.KWin /Effects org.kde.kwin.Effects.reconfigureEffect windowview >/dev/null 2>&1
' || echo "kde-restart: KWin reload failed - config applies at next login" >&2
