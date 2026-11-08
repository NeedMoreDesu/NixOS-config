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
# org.kde.KSMServerInterface; the replacement is the activatable
# org.kde.Shutdown service (plasma-shutdown) on the user's session bus:
# `logout` ends the session from the inside, so sddm-helper exits 0 and
# SDDM brings the greeter back. No confirmation — apps that block
# logout (unsaved changes) still get their usual say.
# NEVER `loginctl terminate-user`: systemd hits sddm-helper with TERM
# then HUP, Qt reports a SIGHUP death as exit status 1 =
# Auth::HELPER_AUTH_ERROR, and Display.cpp treats that as an auth error
# and skips the greeter restart — dead black console on the session VT
# (sddm#1908, unfixed in 0.21).
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

# xremap cannot live-reload its config: the new yamlConfig only lands on
# disk with the switch, so bounce the user unit here (same runuser trick
# as the logout block: nyx runs as root, systemctl --user must reach
# MIKA's user manager, not root's). A bad config now surfaces loudly:
# the restart fails and the unit shows as failed.
restart_user="${SUDO_USER:-mika}"
runuser -u "$restart_user" -- \
  env XDG_RUNTIME_DIR="/run/user/$(id -u "$restart_user")" \
  systemctl --user restart xremap

# -r wins over -l (a reboot logs the session out anyway)
if $logout_after && ! $reboot_after; then
  logout_user="${SUDO_USER:-mika}"
  runuser -u "$logout_user" -- \
    env XDG_RUNTIME_DIR="/run/user/$(id -u "$logout_user")" \
    qdbus org.kde.Shutdown /Shutdown logout
fi

if $reboot_after; then
  reboot
fi
