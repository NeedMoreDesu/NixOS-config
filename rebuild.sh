#!/usr/bin/env bash
set -euo pipefail

REPO="/home/mika/nixos_config"

# -u: bump all flake inputs and commit flake.lock before rebuilding.
# Runs as the invoking user (git identity + flake lockfile ownership).
# -r: reboot once the switch succeeds (use after changes that only apply
# on a fresh boot/session, e.g. xkb layout swaps).
# -l: end the graphical session after a successful switch instead of
# rebooting (KWin re-reads kglobalshortcutsrc/xkb at session start).
# Plasma 6.8's ksmserver no longer exposes a logout slot on
# org.kde.KSMServerInterface, so use loginctl: it SIGTERMs all of the
# *user's* processes (the sudo'd root script survives and SDDM comes back
# at the greeter).
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
  loginctl terminate-user "${SUDO_USER:-mika}"
fi

if $reboot_after; then
  reboot
fi
