#!/usr/bin/env bash
set -euo pipefail

REPO="/home/mika/nixos_config"

# -u: bump all flake inputs and commit flake.lock before rebuilding.
# Runs as the invoking user (git identity + flake lockfile ownership).
if [[ "${1:-}" == "-u" || "${1:-}" == "--update" ]]; then
  if [[ -n "${SUDO_USER:-}" ]]; then
    runuser -l "$SUDO_USER" -c "cd $REPO && nix flake update --commit-lock-file"
  else
    (cd "$REPO" && nix flake update --commit-lock-file)
  fi
fi

exec nixos-rebuild switch --flake "$REPO#nixos"
