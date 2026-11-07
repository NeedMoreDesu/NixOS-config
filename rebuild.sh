#!/usr/bin/env bash
set -euo pipefail

REPO="/home/mika/nixos_config"

# -u: bump all flake inputs and commit flake.lock before rebuilding.
# Runs as the invoking user (git identity + flake lockfile ownership).
# -r: reboot once the switch succeeds (use after changes that only apply
# on a fresh boot/session, e.g. xkb layout swaps).
# -l: end the graphical session after a successful switch instead of
# rebooting (KWin re-reads kglobalshortcutsrc/xkb at session start). Ask
# ksmserver itself so the session is closed cleanly; only if that call
# cannot be made, hard-kill the user's sessions via loginctl.
update=false
reboot_after=false
logout_after=false
for arg in "$@"; do
  case "$arg" in
    -u | --update) update=true ;;
    -r | --reboot) reboot_after=true ;;
    -l | --logout) logout_after=true ;;
    *)
      echo "usage: rebuild.sh [-u|--update] [-r|--reboot] [-l|--logout]" >&2
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

# -r wins over -l (a reboot logs the session out anyway)
if $logout_after && ! $reboot_after; then
  user="${SUDO_USER:-mika}"
  uid=$(id -u "$user")
  runuser -l "$user" -c "XDG_RUNTIME_DIR=/run/user/$uid DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$uid/bus qdbus org.kde.ksmserver /KSMServer org.kde.KSMServerInterface.logout 0 2 2" \
    || loginctl terminate-user "$user"
fi

if $reboot_after; then
  reboot
fi
