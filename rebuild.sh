#!/usr/bin/env bash
set -euo pipefail

REPO="/home/mika/nixos_config"

# -u: bump flake inputs and commit flake.lock before rebuilding. Inputs in
# scripts/flake-update.sh's HOLD_INPUTS stay pinned and are printed, then
# the per-package holds (scripts/held-packages.nix, overlaid by
# modules/held-packages.nix from the frozen nixpkgs-held input) are listed
# with held-vs-current versions; equal = redundant, release with
# scripts/flake-rollback.sh --release <pkg>. Runs as the invoking user
# (git identity + flake lockfile ownership).
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
# -k: apply the new plasma config to the LIVE session without logging out:
# runs the user's plasma-manager runner. It diffs the generated desktop
# scripts against ~/.local/share/plasma-manager/last_run_* stamps (a fresh
# generation always re-runs them), pushes the layout into the running
# plasmashell via qdbus, and restarts whatever services the scripts marked
# (plasma-plasmashell & co). Needed because nixos-rebuild's own activation
# cannot reach the session bus: the switch flips the ~/.local symlinks but
# the layout only lands on-screen at login (autostart) or here.
# NEVER `loginctl terminate-user`: systemd hits sddm-helper with TERM
# then HUP, Qt reports a SIGHUP death as exit status 1 =
# Auth::HELPER_AUTH_ERROR, and Display.cpp treats that as an auth error
# and skips the greeter restart — dead black console on the session VT
# (sddm#1908, unfixed in 0.21).
# After a successful switch nyx also does the store cleanup (on top of the
# weekly nix-gc timer in modules/nix.nix): cap system + home-manager
# generations at the last KEEP_GENERATIONS, then run nix-collect-garbage.
# The collect is the part that reclaims disk — build inputs (notably the
# local seance flake source, which copies the whole dirty worktree incl.
# .zig-cache) are NOT part of the runtime closure, so no generation-rooted
# GC ever frees them.
update=false
reboot_after=false
logout_after=false
kde_after=false
KEEP_GENERATIONS=10
for arg in "$@"; do
  case "$arg" in
    -u | --update) update=true ;;
    -r | --reboot) reboot_after=true ;;
    -l | --logout) logout_after=true ;;
    -k | --kde) kde_after=true ;;
    *)
      echo "usage: rebuild.sh [-u|--update] [-r|--reboot] [-l|--logout] [-k|--kde]" >&2
      exit 2
      ;;
  esac
done

if $update; then
  if [[ -n "${SUDO_USER:-}" ]]; then
    runuser -l "$SUDO_USER" -c "cd $REPO && ./scripts/flake-update.sh"
  else
    (cd "$REPO" && ./scripts/flake-update.sh)
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

# Store cleanup after a successful switch (see header): keep the last
# KEEP_GENERATIONS generations per profile, then collect every dead path.
# Non-fatal — the switch already succeeded, a hiccup here must not abort
# the -k/-l/-r handling below, but it must be loud or the disk fills
# silently. nix-env only unlinks generation symlinks; the bytes are freed
# by nix-collect-garbage afterwards.
nix-env -p /nix/var/nix/profiles/system \
  --delete-generations "+$KEEP_GENERATIONS" \
  || echo "nyx: system generation prune failed" >&2

gc_user="${SUDO_USER:-mika}"
hm_profile="/home/$gc_user/.local/state/nix/profiles/home-manager"
if [[ -e "$hm_profile" ]]; then
  runuser -u "$gc_user" -- env HOME="/home/$gc_user" \
    "$(command -v nix-env)" -p "$hm_profile" \
    --delete-generations "+$KEEP_GENERATIONS" \
    || echo "nyx: home-manager generation prune failed" >&2
fi

nix-collect-garbage || echo "nyx: garbage collection failed" >&2

# -k: push the new plasma layout into the live session. Non-fatal: no
# runner yet (never logged in since install) or a hiccup here must not
# fail the switch - worst case the config lands at next login anyway.
# Skipped when -l/-r follow: the plasma-manager autostart re-applies on
# the fresh session regardless.
if $kde_after && ! $logout_after && ! $reboot_after; then
  kde_user="${SUDO_USER:-mika}"
  runuser -u "$kde_user" -- \
    env XDG_RUNTIME_DIR="/run/user/$(id -u "$kde_user")" \
    sh -c '"$HOME/.local/share/plasma-manager/run_all.sh"' \
    || echo "nyx -k: plasma-manager runner failed or absent - config applies at next login" >&2

  # plasma-manager only WRITES kwinrc; KWin caches its settings at startup
  # and only reloads when told to. The Screen Edges KCM does two things
  # after saving (src/kcms/screenedges/main.cpp): sends the reloadConfig
  # signal to /KWin (Workspace::slotReloadConfig -> reconfigure) and calls
  # reconfigureEffect on /Effects. Effects that reserve their own border
  # (Overview's kcfg default is ElectricTopLeft) are NOT covered by the
  # [ElectricBorders] reload, so both calls are needed. Non-fatal, same
  # reasoning as above: without a running KWin the next login applies it.
  runuser -u "$kde_user" -- \
    env XDG_RUNTIME_DIR="/run/user/$(id -u "$kde_user")" \
    sh -c '
      qdbus org.kde.KWin /KWin org.kde.KWin.reconfigure >/dev/null 2>&1
      qdbus org.kde.KWin /Effects org.kde.kwin.Effects.reconfigureEffect overview >/dev/null 2>&1
      qdbus org.kde.KWin /Effects org.kde.kwin.Effects.reconfigureEffect windowview >/dev/null 2>&1
    ' \
    || echo "nyx -k: KWin reload failed - config applies at next login" >&2
fi

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
