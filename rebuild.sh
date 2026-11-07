#!/usr/bin/env bash
set -euo pipefail

REPO="/home/mika/nixos_config"

# -u: bump all flake inputs and commit flake.lock before rebuilding.
# Runs as the invoking user (git identity + flake lockfile ownership).
# -r: reboot once the switch succeeds (use after changes that only apply
# on a fresh boot/session, e.g. xkb layout swaps).
update=false
reboot_after=false
for arg in "$@"; do
  case "$arg" in
    -u | --update) update=true ;;
    -r | --reboot) reboot_after=true ;;
    *)
      echo "usage: rebuild.sh [-u|--update] [-r|--reboot]" >&2
      exit 2
      ;;
  esac
done

if $update; then
  if [[ -n "${SUDO_USER:-}" ]]; then
    runuser -l "$SUDO_USER" -c "cd $REPO && nix flake update --commit-lock-file"
  else
    (cd "$REPO" && nix flake update --commit-lock-file)
  fi
fi

nixos-rebuild switch --flake "$REPO#nixos"

if $reboot_after; then
  reboot
fi
