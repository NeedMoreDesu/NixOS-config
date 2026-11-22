#!/usr/bin/env bash
# Restart the keyd -> xremap chain.
#
# Restart the keyd -> xremap chain when remapping wedges without either
# service failing (e.g. a stuck key on keyd's virtual device). Restarting
# keyd first recreates its virtual devices; xremap is then bounced so it
# re-grabs them (event numbers change, and --watch alone is not enough in
# every case). See docs/keyboard.md for the 2026-11-22 layer-0 regression
# that used to require this.
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
