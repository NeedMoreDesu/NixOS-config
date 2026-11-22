#!/usr/bin/env bash
# Restart the keyd -> xremap chain.
#
# Workaround for the 2026-11-22 regression: after a Bluetooth keyboard
# reconnect keyd keeps running but stops remapping, while xremap still
# holds the old keyd virtual devices. Restarting keyd first is what fixes
# it; xremap is then bounced so it grabs keyd's recreated devices (event
# numbers change, and --watch alone is not enough in every case).
#
# Run as mika (root is only needed for keyd). If invoked through sudo, the
# script finds mika's user manager instead of root's.
set -euo pipefail

if [[ $EUID -eq 0 ]]; then
  user="${SUDO_USER:-mika}"
  systemctl restart keyd
  sleep 1
  runuser -u "$user" -- \
    env XDG_RUNTIME_DIR="/run/user/$(id -u "$user")" \
    systemctl --user restart xremap
else
  sudo systemctl restart keyd
  sleep 1
  systemctl --user restart xremap
fi
